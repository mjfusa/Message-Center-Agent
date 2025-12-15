import dotenv from 'dotenv';
import fs from 'node:fs';
import path from 'node:path';
import * as z from 'zod';
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { createMcpExpressApp } from '@modelcontextprotocol/sdk/server/express.js';
import { StreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/streamableHttp.js';
import { getGraphEnvConfig } from './graph/config.js';
import { buildLoginUrl, handleCallback, refreshAccessToken } from './graph/graphOAuth.js';
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
        .describe('Optional: Graph access token for proxying requests. Use only for local testing; OAuth flow will replace this after browser sign-in.')
};
const getGraphLoginUrlSchema = {
    // Optional hint for deployments behind a proxy where PUBLIC_BASE_URL can't be inferred.
    publicBaseUrl: z
        .string()
        .url()
        .optional()
        .describe('Optional override for public base URL used to compute redirectUri.')
};
function toTextResult(value) {
    return {
        content: [
            {
                type: 'text',
                text: JSON.stringify(value, null, 2)
            }
        ]
    };
}
async function fetchJson(url, init) {
    const response = await fetch(url, init);
    const text = await response.text();
    let parsed = text;
    try {
        parsed = text ? JSON.parse(text) : null;
    }
    catch {
        parsed = text;
    }
    return {
        ok: response.ok,
        status: response.status,
        statusText: response.statusText,
        data: parsed
    };
}
function buildUrl(baseUrl, path, query) {
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
    const server = new McpServer({ name: 'mcp-message-center-server', version: '0.1.0' }, { capabilities: { logging: {} } });
    server.registerTool('getGraphLoginUrl', {
        description: 'Returns an Azure AD login URL to authorize Microsoft Graph ServiceMessage.Read.All for this MCP session. Open the URL in a browser to complete sign-in.',
        inputSchema: getGraphLoginUrlSchema
    }, async (args, extra) => {
        const sessionId = extra?.sessionId ?? 'unknown-session';
        const publicBaseUrl = args.publicBaseUrl ??
            process.env.PUBLIC_BASE_URL ??
            `http://localhost:${process.env.PORT ?? 8080}`;
        const config = getGraphEnvConfig(publicBaseUrl);
        const { loginUrl } = buildLoginUrl(config, sessionId);
        return toTextResult({ sessionId, loginUrl, redirectUri: config.redirectUri, scopes: config.scopes });
    });
    server.registerTool('getMessages', {
        description: 'Retrieve Microsoft 365 Message Center messages from Microsoft Graph (admin/serviceAnnouncement/messages).',
        inputSchema: getMessagesInputSchema
    }, async (args, extra) => {
        const sessionId = extra?.sessionId ?? 'unknown-session';
        const publicBaseUrl = process.env.PUBLIC_BASE_URL ?? `http://localhost:${process.env.PORT ?? 8080}`;
        const argToken = args.accessToken;
        const envToken = process.env.GRAPH_ACCESS_TOKEN;
        let accessToken = argToken ?? envToken;
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
                    }
                    catch (e) {
                        return toTextResult({
                            note: 'Failed to refresh token; please re-authenticate.',
                            error: String(e),
                            sessionId
                        });
                    }
                }
                else {
                    accessToken = cached.accessToken;
                }
            }
        }
        const url = buildUrl(GRAPH_BASE_URL, '/admin/serviceAnnouncement/messages', {
            $orderby: args.orderby,
            $count: String(args.count),
            $top: args.top !== undefined ? String(args.top) : undefined,
            $skip: args.skip !== undefined ? String(args.skip) : undefined,
            $filter: args.filter
        });
        const headers = {
            Accept: 'application/json'
        };
        const prefer = args.prefer;
        if (prefer) {
            headers.Prefer = prefer;
        }
        if (accessToken) {
            headers.Authorization = `Bearer ${accessToken}`;
        }
        const result = await fetchJson(url, { headers });
        if (!accessToken && result.status === 401) {
            return toTextResult({
                note: 'Graph returned 401. Set GRAPH_ACCESS_TOKEN, or call getGraphLoginUrl then complete browser sign-in so this session can call Graph without passing a token.',
                request: { url, headers: { ...headers, Authorization: undefined } },
                response: result
            });
        }
        return toTextResult({ request: { url }, response: result });
    });
    return server;
}
const app = createMcpExpressApp();
app.get('/auth/graph/login', (req, res) => {
    try {
        const sessionId = String(req.query.sessionId ?? '');
        if (!sessionId) {
            res.status(400).send('Missing required query param: sessionId');
            return;
        }
        const publicBaseUrl = String(req.query.publicBaseUrl ?? '') ||
            process.env.PUBLIC_BASE_URL ||
            `http://localhost:${process.env.PORT ?? 8080}`;
        const config = getGraphEnvConfig(publicBaseUrl);
        const { loginUrl } = buildLoginUrl(config, sessionId);
        res.redirect(loginUrl);
    }
    catch (e) {
        res.status(500).send(String(e));
    }
});
app.get('/auth/graph/callback', async (req, res) => {
    try {
        const code = String(req.query.code ?? '');
        const state = String(req.query.state ?? '');
        if (!code || !state) {
            res.status(400).send('Missing required query params: code, state');
            return;
        }
        const publicBaseUrl = process.env.PUBLIC_BASE_URL ?? `http://localhost:${process.env.PORT ?? 8080}`;
        const config = getGraphEnvConfig(publicBaseUrl);
        const { sessionId } = await handleCallback(config, code, state);
        res
            .status(200)
            .send(`<html><body><h3>Graph authorization complete</h3><p>You can close this window.</p><p>Session: ${sessionId}</p></body></html>`);
    }
    catch (e) {
        res.status(500).send(String(e));
    }
});
app.get('/auth/graph/logout', (req, res) => {
    const sessionId = String(req.query.sessionId ?? '');
    if (!sessionId) {
        res.status(400).send('Missing required query param: sessionId');
        return;
    }
    clearTokenForSession(sessionId);
    res.status(200).send('Logged out');
});
app.post('/mcp', async (req, res) => {
    const server = getServer();
    try {
        const transport = new StreamableHTTPServerTransport({
            sessionIdGenerator: undefined
        });
        await server.connect(transport);
        await transport.handleRequest(req, res, req.body);
        res.on('close', () => {
            transport.close();
            server.close();
        });
    }
    catch (error) {
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
app.get('/healthz', (_req, res) => {
    res.status(200).json({ ok: true });
});
const port = Number(process.env.PORT ?? 8080);
app.listen(port, () => {
    console.log(`MCP server listening on http://localhost:${port}/mcp`);
});
//# sourceMappingURL=server.js.map