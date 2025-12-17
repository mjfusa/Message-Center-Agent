import express, { Request, Response } from 'express';
import dotenv from 'dotenv';
import fs from 'node:fs';
import path from 'node:path';
import * as z from 'zod';

import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/streamableHttp.js';
import type { CallToolResult, MessageExtraInfo } from '@modelcontextprotocol/sdk/types.js';

import { getGraphEnvConfig } from './graph/config.js';
import { buildLoginUrl, handleCallback, refreshAccessToken } from './graph/graphOAuth.js';
import { acquireGraphAccessTokenOnBehalfOf } from './graph/graphObo.js';
import { clearTokenForSession, getTokenForSession, setTokenForSession } from './graph/tokenStore.js';

import { getMessagesInputSchemaBase } from './generated/messagesInputSchema.js';

function loadEnvLocalIfPresent() {
  // Load env vars automatically in local dev.
  // This avoids a common footgun where the server is started without first dot-sourcing a script.
  const cwd = process.cwd();
  const candidates = [
    path.resolve(cwd, '.env.local'),
    path.resolve(cwd, 'mcp-message-center-server', '.env.local')
  ];

  for (const candidate of candidates) {
    if (fs.existsSync(candidate)) {
      dotenv.config({ path: candidate, override: false });
      break;
    }
  }
}

loadEnvLocalIfPresent();

const GRAPH_BASE_URL = 'https://graph.microsoft.com/v1.0';

const TOKEN_REFRESH_SKEW_MS = 60_000;

const getMessagesInputSchema = {
  ...getMessagesInputSchemaBase,
  accessToken: z
    .string()
    .optional()
    .describe(
      'Optional: Graph access token for proxying requests. Use only for local testing; OAuth flow will replace this after browser sign-in.'
    )
};

const getGraphLoginUrlSchema = {
  // Optional hint for deployments behind a proxy where PUBLIC_BASE_URL can't be inferred.
  publicBaseUrl: z
    .string()
    .url()
    .optional()
    .describe('Optional override for public base URL used to compute redirectUri.')
};

function toTextResult(value: unknown): CallToolResult {
  return {
    content: [
      {
        type: 'text',
        text: JSON.stringify(value, null, 2)
      }
    ]
  };
}

function normalizeHeaderValue(value: unknown): string | undefined {
  if (typeof value === 'string') return value;
  if (Array.isArray(value) && typeof value[0] === 'string') return value[0];
  return undefined;
}

function getBearerTokenFromAuthHeader(headerValue: string | undefined): string | undefined {
  if (!headerValue) return undefined;
  const match = headerValue.match(/^\s*Bearer\s+(.+)\s*$/i);
  return match?.[1];
}

function decodeJwtPayload(token: string): Record<string, unknown> | undefined {
  // Best-effort decoding for routing decisions only. This does NOT validate signatures.
  const parts = token.split('.');
  if (parts.length < 2) return undefined;

  try {
    const base64Url = parts[1];
    const base64 = base64Url.replace(/-/g, '+').replace(/_/g, '/');
    const padded = base64.padEnd(base64.length + ((4 - (base64.length % 4)) % 4), '=');
    const json = Buffer.from(padded, 'base64').toString('utf8');
    const parsed = JSON.parse(json);
    if (parsed && typeof parsed === 'object') {
      return parsed as Record<string, unknown>;
    }
  } catch {
    // ignore
  }
  return undefined;
}

function isGraphAudience(aud: unknown): boolean {
  // Graph resource appId
  if (aud === '00000003-0000-0000-c000-000000000000') return true;
  // Some tokens may carry a URL audience
  if (aud === 'https://graph.microsoft.com') return true;
  return false;
}

async function resolveGraphTokenForRequest(extra?: (MessageExtraInfo & { sessionId?: string }) | undefined): Promise<
  | { accessToken: string; source: 'authorization-header-graph' | 'obo' }
  | { accessToken?: undefined; source: 'none' }
  | { accessToken?: undefined; source: 'obo-error'; error: string }
> {
  const authHeader =
    normalizeHeaderValue(extra?.requestInfo?.headers?.authorization) ??
    normalizeHeaderValue((extra?.requestInfo?.headers as any)?.Authorization);

  const bearer = getBearerTokenFromAuthHeader(authHeader);
  if (!bearer) {
    return { source: 'none' };
  }

  const payload = decodeJwtPayload(bearer);
  if (payload && isGraphAudience(payload.aud)) {
    return { accessToken: bearer, source: 'authorization-header-graph' };
  }

  try {
    const result = await acquireGraphAccessTokenOnBehalfOf(bearer);
    return { accessToken: result.accessToken, source: 'obo' };
  } catch (e) {
    return { source: 'obo-error', error: String(e) };
  }
}

async function fetchJson(url: string, init?: RequestInit) {
  const response = await fetch(url, init);
  const text = await response.text();

  let parsed: unknown = text;
  try {
    parsed = text ? JSON.parse(text) : null;
  } catch {
    parsed = text;
  }

  return {
    ok: response.ok,
    status: response.status,
    statusText: response.statusText,
    data: parsed
  };
}

function buildUrl(baseUrl: string, path: string, query: Record<string, string | undefined>) {
  const base = baseUrl.endsWith('/') ? baseUrl : `${baseUrl}/`;
  const relativePath = path.startsWith('/') ? path.slice(1) : path;
  const url = new URL(relativePath, base);
  for (const [key, value] of Object.entries(query)) {
    if (value !== undefined && value !== '') {
      url.searchParams.set(key, value);
    }
  }
  return url.toString();
}

function getServer() {
  const server = new McpServer(
    { name: 'mcp-message-center-server', version: '0.1.0' },
    { capabilities: { logging: {} } }
  );

  server.registerTool(
    'getGraphLoginUrl',
    {
      description:
        'Returns an Azure AD login URL to authorize Microsoft Graph ServiceMessage.Read.All for this MCP session. Open the URL in a browser to complete sign-in.',
      inputSchema: getGraphLoginUrlSchema
    },
    async (args, extra): Promise<CallToolResult> => {
      const sessionId = extra?.sessionId ?? 'unknown-session';
      const publicBaseUrl =
        (args as any).publicBaseUrl ??
        process.env.PUBLIC_BASE_URL ??
        `http://localhost:${process.env.PORT ?? 8080}`;

      const config = getGraphEnvConfig(publicBaseUrl);
      const { loginUrl } = buildLoginUrl(config, sessionId);
      return toTextResult({ sessionId, loginUrl, redirectUri: config.redirectUri, scopes: config.scopes });
    }
  );

  server.registerTool(
    'getMessages',
    {
      description:
        'Retrieve Microsoft 365 Message Center messages from Microsoft Graph (admin/serviceAnnouncement/messages).',
      inputSchema: getMessagesInputSchema
    },
    async (args, extra): Promise<CallToolResult> => {
      const sessionId = (extra as any)?.sessionId ?? 'unknown-session';
      const publicBaseUrl =
        process.env.PUBLIC_BASE_URL ?? `http://localhost:${process.env.PORT ?? 8080}`;

      // Preferred for declarative agent callers:
      // - Client sends Authorization: Bearer <user token for this MCP API>
      // - Server uses OBO to acquire a Graph token on behalf of the user
      const requestToken = await resolveGraphTokenForRequest(extra as any);
      if (requestToken.source === 'obo-error') {
        return toTextResult({
          note:
            'OBO token exchange failed. Ensure the caller sends a valid Entra user access token for this MCP API (not a random token), and that this server app registration has delegated Microsoft Graph permissions with admin consent.',
          error: requestToken.error,
          sessionId
        });
      }

      const argToken = (args as { accessToken?: string }).accessToken;
      const envToken = process.env.GRAPH_ACCESS_TOKEN;

      let accessToken =
        requestToken.source === 'obo' || requestToken.source === 'authorization-header-graph'
          ? requestToken.accessToken
          : argToken ?? envToken;

      if (!accessToken) {
        const cached = getTokenForSession(sessionId);
        if (cached) {
          const shouldRefresh = cached.expiresAtEpochMs - Date.now() <= TOKEN_REFRESH_SKEW_MS;
          if (shouldRefresh && cached.refreshToken) {
            try {
              const config = getGraphEnvConfig(publicBaseUrl);
              const refreshed = await refreshAccessToken(config, cached.refreshToken);
              setTokenForSession(sessionId, refreshed);
              accessToken = refreshed.accessToken;
            } catch (e) {
              return toTextResult({
                note: 'Failed to refresh token; please re-authenticate.',
                error: String(e),
                sessionId
              });
            }
          } else {
            accessToken = cached.accessToken;
          }
        }
      }

      const url = buildUrl(GRAPH_BASE_URL, '/admin/serviceAnnouncement/messages', {
        $orderby: (args as any).orderby,
        $count: String((args as any).count),
        $top: (args as any).top !== undefined ? String((args as any).top) : undefined,
        $skip: (args as any).skip !== undefined ? String((args as any).skip) : undefined,
        $filter: (args as any).filter
      });

      const headers: Record<string, string> = {
        Accept: 'application/json'
      };

      const prefer = (args as any).prefer;
      if (prefer) {
        headers.Prefer = prefer;
      }

      if (accessToken) {
        headers.Authorization = `Bearer ${accessToken}`;
      }

      const result = await fetchJson(url, { headers });

      if (!accessToken && result.status === 401) {
        return toTextResult({
          note:
            'Graph returned 401. For declarative agents, call /mcp with Authorization: Bearer <user token for this MCP API> so the server can use OBO. For local testing, set GRAPH_ACCESS_TOKEN, or call getGraphLoginUrl then complete browser sign-in so this session can call Graph without passing a token.',
          request: { url, headers: { ...headers, Authorization: undefined } },
          response: result
        });
      }

      return toTextResult({ request: { url }, response: result });
    }
  );
  return server;
}

const app = express();
app.use(express.json({ limit: '1mb' }));

app.get('/auth/graph/login', (req: Request, res: Response) => {
  try {
    const sessionId = String(req.query.sessionId ?? '');
    if (!sessionId) {
      res.status(400).send('Missing required query param: sessionId');
      return;
    }

    const publicBaseUrl =
      String(req.query.publicBaseUrl ?? '') ||
      process.env.PUBLIC_BASE_URL ||
      `http://localhost:${process.env.PORT ?? 8080}`;

    const config = getGraphEnvConfig(publicBaseUrl);
    const { loginUrl } = buildLoginUrl(config, sessionId);
    res.redirect(loginUrl);
  } catch (e) {
    res.status(500).send(String(e));
  }
});

app.get('/auth/graph/callback', async (req: Request, res: Response) => {
  try {
    const code = String(req.query.code ?? '');
    const state = String(req.query.state ?? '');
    if (!code || !state) {
      res.status(400).send('Missing required query params: code, state');
      return;
    }

    const publicBaseUrl =
      process.env.PUBLIC_BASE_URL ?? `http://localhost:${process.env.PORT ?? 8080}`;
    const config = getGraphEnvConfig(publicBaseUrl);
    const { sessionId } = await handleCallback(config, code, state);

    res
      .status(200)
      .send(
        `<html><body><h3>Graph authorization complete</h3><p>You can close this window.</p><p>Session: ${sessionId}</p></body></html>`
      );
  } catch (e) {
    res.status(500).send(String(e));
  }
});

app.get('/auth/graph/logout', (req: Request, res: Response) => {
  const sessionId = String(req.query.sessionId ?? '');
  if (!sessionId) {
    res.status(400).send('Missing required query param: sessionId');
    return;
  }
  clearTokenForSession(sessionId);
  res.status(200).send('Logged out');
});

app.post('/mcp', async (req: Request, res: Response) => {
  const server = getServer();

  try {
    if (process.env.MCP_REQUIRE_AUTH === 'true') {
      const bearer = getBearerTokenFromAuthHeader(req.header('authorization'));
      if (!bearer) {
        res.status(401).json({
          jsonrpc: '2.0',
          error: { code: -32001, message: 'Unauthorized: missing Authorization bearer token' },
          id: null
        });
        return;
      }
    }

    const transport = new StreamableHTTPServerTransport({
      sessionIdGenerator: undefined
    });

    await server.connect(transport);
    await transport.handleRequest(req, res, req.body);

    res.on('close', () => {
      transport.close();
      server.close();
    });
  } catch (error) {
    console.error('Error handling MCP request:', error);
    if (!res.headersSent) {
      res.status(500).json({
        jsonrpc: '2.0',
        error: { code: -32603, message: 'Internal server error' },
        id: null
      });
    }
  }
});

app.get('/healthz', (_req: Request, res: Response) => {
  res.status(200).json({ ok: true });
});

const port = Number(process.env.PORT ?? 8080);
app.listen(port, () => {
  console.log(`MCP server listening on http://localhost:${port}/mcp`);
});
