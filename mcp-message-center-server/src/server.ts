import express, { Request, Response } from 'express';
import dotenv from 'dotenv';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import * as z from 'zod';

import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/streamableHttp.js';
import type { CallToolResult, MessageExtraInfo } from '@modelcontextprotocol/sdk/types.js';

import { acquireGraphAccessTokenOnBehalfOf } from './graph/graphObo.js';
import { getClientCertificateFromEnvOrKeyVault } from './entra/clientCertificate.js';

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

const getMessagesInputSchema = {
  ...getMessagesInputSchemaBase,
  accessToken: z
    .string()
    .optional()
    .describe(
      'Optional: Graph access token for proxying requests. Use only for local testing.'
    )
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

function toStructuredResult(structuredContent: Record<string, unknown>): CallToolResult {
  return {
    content: [
      {
        type: 'text',
        text: JSON.stringify(structuredContent, null, 2)
      }
    ],
    structuredContent
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

function isExpectedMcpApiAudience(aud: unknown): boolean {
  const clientId = process.env.GRAPH_CLIENT_ID;
  if (!clientId) return false;
  if (aud === clientId) return true;
  if (aud === `api://${clientId}`) return true;
  // Some tokens can use an App ID URI ending with the clientId.
  if (typeof aud === 'string' && aud.endsWith(`/${clientId}`)) return true;
  return false;
}

function isJwtExpired(payload: Record<string, unknown>): boolean {
  const exp = payload.exp;
  if (typeof exp !== 'number') return false;
  const expMs = exp * 1000;
  return Date.now() >= expMs;
}

function setWwwAuthenticate(res: Response, req: Request, details?: { error?: string; errorDescription?: string }) {
  const baseUrl = getPublicBaseUrl(req);
  const authorizeUri = `${baseUrl}/authorize`;
  const tokenUri = `${baseUrl}/token`;

  const parts: string[] = [
    'Bearer realm="mcp-message-center-server"',
    `authorization_uri="${authorizeUri}"`,
    `token_uri="${tokenUri}"`
  ];

  if (details?.error) {
    parts.push(`error="${details.error}"`);
  }
  if (details?.errorDescription) {
    // Keep it short and safe for headers.
    const sanitized = details.errorDescription.replace(/[\r\n"]/g, ' ').slice(0, 300);
    parts.push(`error_description="${sanitized}"`);
  }

  res.setHeader('WWW-Authenticate', parts.join(', '));
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

      // Provide structuredContent so Copilot can apply response_semantics (citations/adaptive card)
      // against a real JSON payload, not a JSON string embedded in text.
      let structuredContent: Record<string, unknown> = {
        request: { url },
        response: result
      };

      if (result.ok && result.data && typeof result.data === 'object') {
        const data = result.data as Record<string, unknown>;
        const value = (data as any).value;
        if (Array.isArray(value)) {
          const withUrls = value.map((m: any) => {
            const id = typeof m?.id === 'string' ? m.id : undefined;
            const portalUrl = id
              ? `https://admin.microsoft.com/#/MessageCenter/:/messages/${id}`
              : undefined;
            return portalUrl ? { ...m, url: portalUrl } : m;
          });
          structuredContent = { ...data, value: withUrls };
        } else {
          structuredContent = data;
        }
      }

      if (!accessToken && result.status === 401) {
        return toStructuredResult({
          note:
            'Graph returned 401. For declarative agents, call /mcp with Authorization: Bearer <user token for this MCP API> so the server can use OBO. For local testing, set GRAPH_ACCESS_TOKEN or pass accessToken to the tool call.',
          request: { url, headers: { ...headers, Authorization: undefined } },
          response: result
        });
      }

      return toStructuredResult(structuredContent);
    }
  );
  return server;
}

const app = express();
app.use(express.json({ limit: '1mb' }));
app.use(express.urlencoded({ extended: false }));

function requiredValue(name: string, value: string | undefined) {
  if (!value) throw new Error(`Missing required value: ${name}`);
  return value;
}

function normalizeString(value: unknown): string | undefined {
  if (typeof value === 'string') return value;
  if (Array.isArray(value) && typeof value[0] === 'string') return value[0];
  return undefined;
}

function base64UrlEncode(input: Buffer | string): string {
  const buf = typeof input === 'string' ? Buffer.from(input, 'utf8') : input;
  return buf
    .toString('base64')
    .replace(/=/g, '')
    .replace(/\+/g, '-')
    .replace(/\//g, '_');
}

function thumbprintHexToX5t(thumbprintHex: string): string {
  const normalized = thumbprintHex.replace(/[^a-fA-F0-9]/g, '');
  if (!normalized || normalized.length % 2 !== 0) {
    throw new Error(
      'Invalid GRAPH_CLIENT_CERT_THUMBPRINT. Expected an even-length hex string.'
    );
  }
  return base64UrlEncode(Buffer.from(normalized, 'hex'));
}

function createClientAssertion(params: {
  clientId: string;
  audience: string;
  thumbprintHex: string;
  privateKeyPem: string;
}): string {
  const nowSeconds = Math.floor(Date.now() / 1000);
  const expSeconds = nowSeconds + 10 * 60;

  const header = {
    alg: 'RS256',
    typ: 'JWT',
    x5t: thumbprintHexToX5t(params.thumbprintHex)
  };

  const payload = {
    aud: params.audience,
    iss: params.clientId,
    sub: params.clientId,
    jti: crypto.randomUUID(),
    nbf: nowSeconds,
    exp: expSeconds
  };

  const signingInput = `${base64UrlEncode(JSON.stringify(header))}.${base64UrlEncode(JSON.stringify(payload))}`;
  const signature = crypto.sign('RSA-SHA256', Buffer.from(signingInput, 'utf8'), params.privateKeyPem);
  return `${signingInput}.${base64UrlEncode(signature)}`;
}

function getTenantIdForVsCodeAuth(): string {
  return (
    process.env.MCP_OAUTH_TENANT_ID ??
    process.env.GRAPH_TENANT_ID ??
    process.env.TEAMS_APP_TENANT_ID ??
    process.env.AZURE_TENANT_ID ??
    'common'
  );
}

function getPublicBaseUrl(req: Request): string {
  const configured = process.env.PUBLIC_BASE_URL;
  if (configured) return configured.replace(/\/$/, '');
  const host = req.get('host');
  return `${req.protocol}://${host}`.replace(/\/$/, '');
}

function authorizeEndpoint(tenantId: string) {
  return `https://login.microsoftonline.com/${tenantId}/oauth2/v2.0/authorize`;
}

function tokenEndpoint(tenantId: string) {
  return `https://login.microsoftonline.com/${tenantId}/oauth2/v2.0/token`;
}

function getDefaultScope(clientId: string): string {
  // Default to requesting an access token for this MCP API.
  // Assumes the app registration exposes an `access_as_user` scope.
  const apiScope = `api://${clientId}/access_as_user`;
  return `openid profile offline_access ${apiScope}`;
}

function getAllowedRedirectUriPrefixes(): string[] {
  const fromEnv = (process.env.MCP_OAUTH_REDIRECT_URI_PREFIXES ?? '').trim();
  if (fromEnv) {
    return fromEnv
      .split(',')
      .map(s => s.trim())
      .filter(Boolean);
  }

  // Default allowlist:
  // - VS Code loopback redirect
  // - Teams OAuth redirect used by declarative agents
  return [
    'http://127.0.0.1',
    'http://localhost',
    'https://teams.microsoft.com/api/platform/v1.0/oAuthRedirect'
  ];
}

function validateClientAndRedirect(clientId: string, redirectUri: string) {
  // Prevent this from becoming an open OAuth proxy.
  const expectedClientId = process.env.MCP_OAUTH_EXPECTED_CLIENT_ID ?? process.env.GRAPH_CLIENT_ID;
  if (expectedClientId && clientId !== expectedClientId) {
    throw new Error(`Unexpected client_id. Expected ${expectedClientId} but got ${clientId}`);
  }

  const allowedPrefixes = getAllowedRedirectUriPrefixes();
  if (!allowedPrefixes.some(prefix => redirectUri.startsWith(prefix))) {
    throw new Error(`redirect_uri not allowed: ${redirectUri}`);
  }
}

// Minimal OIDC discovery for clients that want it
app.get('/.well-known/openid-configuration', (req: Request, res: Response) => {
  const baseUrl = getPublicBaseUrl(req);
  res.setHeader('Cache-Control', 'no-store');
  res.json({
    issuer: baseUrl,
    authorization_endpoint: `${baseUrl}/authorize`,
    token_endpoint: `${baseUrl}/token`,
    response_types_supported: ['code'],
    grant_types_supported: ['authorization_code', 'refresh_token'],
    code_challenge_methods_supported: ['S256'],
    token_endpoint_auth_methods_supported: ['client_secret_post', 'private_key_jwt', 'none']
  });
});

// Alternate (non-standard) discovery endpoint for clients that want a single place
// to learn the auth requirements without parsing OIDC metadata.
app.get('/discover', (req: Request, res: Response) => {
  const baseUrl = getPublicBaseUrl(req);
  const tenantId = getTenantIdForVsCodeAuth();
  const clientId = process.env.MCP_OAUTH_EXPECTED_CLIENT_ID ?? process.env.GRAPH_CLIENT_ID ?? '';
  const scopes =
    process.env.MCP_OAUTH_SCOPES ?? (clientId ? getDefaultScope(clientId) : 'openid profile offline_access');

  res.setHeader('Cache-Control', 'no-store');
  res.json({
    issuer: baseUrl,
    tenantId,
    authorizationUrl: `${baseUrl}/authorize`,
    tokenUrl: `${baseUrl}/token`,
    scopes,
    pkceRequired: true,
    grantTypesSupported: ['authorization_code', 'refresh_token']
  });
});

// VS Code starts auth by opening this URL in the browser
app.get(['/authorize', '/oauth2/v2.0/authorize'], (req: Request, res: Response) => {
  try {
    const tenantId = getTenantIdForVsCodeAuth();

    const clientId = requiredValue('client_id', normalizeString(req.query.client_id));
    const redirectUri = requiredValue('redirect_uri', normalizeString(req.query.redirect_uri));
    const state = requiredValue('state', normalizeString(req.query.state));
    const codeChallenge = requiredValue('code_challenge', normalizeString(req.query.code_challenge));
    const codeChallengeMethod = normalizeString(req.query.code_challenge_method) ?? 'S256';

    validateClientAndRedirect(clientId, redirectUri);

    const scope =
      normalizeString(req.query.scope) ?? process.env.MCP_OAUTH_SCOPES ?? getDefaultScope(clientId);

    const upstream = new URL(authorizeEndpoint(tenantId));
    upstream.searchParams.set('client_id', clientId);
    upstream.searchParams.set('response_type', 'code');
    upstream.searchParams.set('redirect_uri', redirectUri);
    upstream.searchParams.set('response_mode', 'query');
    upstream.searchParams.set('scope', scope);
    upstream.searchParams.set('state', state);
    upstream.searchParams.set('code_challenge_method', codeChallengeMethod);
    upstream.searchParams.set('code_challenge', codeChallenge);

    // Optional passthroughs
    const prompt = normalizeString(req.query.prompt);
    if (prompt) upstream.searchParams.set('prompt', prompt);
    const loginHint = normalizeString(req.query.login_hint);
    if (loginHint) upstream.searchParams.set('login_hint', loginHint);

    res.redirect(upstream.toString());
  } catch (e) {
    res.status(400).send(String(e));
  }
});

// VS Code exchanges the auth code for tokens here
app.post(['/token', '/oauth2/v2.0/token'], async (req: Request, res: Response) => {
  try {
    const tenantId = getTenantIdForVsCodeAuth();

    const clientId = requiredValue('client_id', normalizeString((req.body as any)?.client_id));
    const redirectUri = requiredValue('redirect_uri', normalizeString((req.body as any)?.redirect_uri));
    validateClientAndRedirect(clientId, redirectUri);

    const grantType = requiredValue('grant_type', normalizeString((req.body as any)?.grant_type));

    const body = new URLSearchParams();
    body.set('client_id', clientId);
    body.set('grant_type', grantType);
    body.set('redirect_uri', redirectUri);

    const clientSecret = process.env.MCP_OAUTH_CLIENT_SECRET ?? process.env.GRAPH_CLIENT_SECRET;
    if (clientSecret) {
      body.set('client_secret', clientSecret);
    } else {
      const { thumbprint, privateKey } = await getClientCertificateFromEnvOrKeyVault();
      body.set('client_assertion_type', 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer');
      body.set(
        'client_assertion',
        createClientAssertion({
          clientId,
          audience: tokenEndpoint(tenantId),
          thumbprintHex: thumbprint,
          privateKeyPem: privateKey
        })
      );
    }

    const scope = normalizeString((req.body as any)?.scope);
    if (scope) {
      body.set('scope', scope);
    }

    if (grantType === 'authorization_code') {
      body.set('code', requiredValue('code', normalizeString((req.body as any)?.code)));
      const verifier = normalizeString((req.body as any)?.code_verifier);
      if (verifier) body.set('code_verifier', verifier);
    } else if (grantType === 'refresh_token') {
      body.set(
        'refresh_token',
        requiredValue('refresh_token', normalizeString((req.body as any)?.refresh_token))
      );
    } else {
      res
        .status(400)
        .json({ error: 'unsupported_grant_type', error_description: `Unsupported grant_type: ${grantType}` });
      return;
    }

    const upstream = await fetch(tokenEndpoint(tenantId), {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body
    });

    const text = await upstream.text();
    res.setHeader('Cache-Control', 'no-store');
    res.setHeader('Pragma', 'no-cache');
    res.status(upstream.status);

    try {
      res.json(text ? JSON.parse(text) : {});
    } catch {
      res.type('text/plain').send(text);
    }
  } catch (e) {
    res.status(400).json({ error: 'invalid_request', error_description: String(e) });
  }
});


app.post('/mcp', async (req: Request, res: Response) => {
  const server = getServer();

  try {
    if (process.env.MCP_REQUIRE_AUTH === 'true') {
      const bearer = getBearerTokenFromAuthHeader(req.header('authorization'));
      if (!bearer) {
        setWwwAuthenticate(res, req, {
          error: 'invalid_request',
          errorDescription: 'Missing Authorization bearer token'
        });
        res.status(401).json({
          jsonrpc: '2.0',
          error: { code: -32001, message: 'Unauthorized: missing Authorization bearer token' },
          id: null
        });
        return;
      }

      // Best-effort guidance for clients: reject clearly unusable/expired tokens.
      // This does NOT validate signatures.
      const payload = decodeJwtPayload(bearer);
      if (payload) {
        if (isJwtExpired(payload)) {
          setWwwAuthenticate(res, req, {
            error: 'invalid_token',
            errorDescription: 'Access token expired'
          });
          res.status(401).json({
            jsonrpc: '2.0',
            error: { code: -32001, message: 'Unauthorized: access token expired' },
            id: null
          });
          return;
        }

        // Accept either:
        // - A Graph token (aud=Graph) OR
        // - A token for this MCP API (aud matches this app) so OBO can run
        if (!isGraphAudience(payload.aud) && !isExpectedMcpApiAudience(payload.aud)) {
          setWwwAuthenticate(res, req, {
            error: 'invalid_token',
            errorDescription: 'Token audience is not accepted for this service'
          });
          res.status(401).json({
            jsonrpc: '2.0',
            error: { code: -32001, message: 'Unauthorized: invalid token audience' },
            id: null
          });
          return;
        }
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
