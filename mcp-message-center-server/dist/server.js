import express from 'express';
import dotenv from 'dotenv';
import fs from 'node:fs';
import path from 'node:path';
import * as z from 'zod';
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/streamableHttp.js';
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
function normalizeHeaderValue(value) {
    if (typeof value === 'string')
        return value;
    if (Array.isArray(value) && typeof value[0] === 'string')
        return value[0];
    return undefined;
}
function getBearerTokenFromAuthHeader(headerValue) {
    if (!headerValue)
        return undefined;
    const match = headerValue.match(/^\s*Bearer\s+(.+)\s*$/i);
    return match?.[1];
}
function decodeJwtPayload(token) {
    // Best-effort decoding for routing decisions only. This does NOT validate signatures.
    const parts = token.split('.');
    if (parts.length < 2)
        return undefined;
    try {
        const base64Url = parts[1];
        const base64 = base64Url.replace(/-/g, '+').replace(/_/g, '/');
        const padded = base64.padEnd(base64.length + ((4 - (base64.length % 4)) % 4), '=');
        const json = Buffer.from(padded, 'base64').toString('utf8');
        const parsed = JSON.parse(json);
        if (parsed && typeof parsed === 'object') {
            return parsed;
        }
    }
    catch {
        // ignore
    }
    return undefined;
}
function isGraphAudience(aud) {
    // Graph resource appId
    if (aud === '00000003-0000-0000-c000-000000000000')
        return true;
    // Some tokens may carry a URL audience
    if (aud === 'https://graph.microsoft.com')
        return true;
    return false;
}
async function resolveGraphTokenForRequest(extra) {
    const authHeader = normalizeHeaderValue(extra?.requestInfo?.headers?.authorization) ??
        normalizeHeaderValue(extra?.requestInfo?.headers?.Authorization);
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
    }
    catch (e) {
        return { source: 'obo-error', error: String(e) };
    }
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
        // Preferred for declarative agent callers:
        // - Client sends Authorization: Bearer <user token for this MCP API>
        // - Server uses OBO to acquire a Graph token on behalf of the user
        const requestToken = await resolveGraphTokenForRequest(extra);
        if (requestToken.source === 'obo-error') {
            return toTextResult({
                note: 'OBO token exchange failed. Ensure the caller sends a valid Entra user access token for this MCP API (not a random token), and that this server app registration has delegated Microsoft Graph permissions with admin consent.',
                error: requestToken.error,
                sessionId
            });
        }
        const argToken = args.accessToken;
        const envToken = process.env.GRAPH_ACCESS_TOKEN;
        let accessToken = requestToken.source === 'obo' || requestToken.source === 'authorization-header-graph'
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
                note: 'Graph returned 401. For declarative agents, call /mcp with Authorization: Bearer <user token for this MCP API> so the server can use OBO. For local testing, set GRAPH_ACCESS_TOKEN, or call getGraphLoginUrl then complete browser sign-in so this session can call Graph without passing a token.',
                request: { url, headers: { ...headers, Authorization: undefined } },
                response: result
            });
        }
        return toTextResult({ request: { url }, response: result });
    });
    return server;
}
const app = express();
app.use(express.json({ limit: '1mb' }));
app.use(express.urlencoded({ extended: false }));
function requiredValue(name, value) {
    if (!value)
        throw new Error(`Missing required value: ${name}`);
    return value;
}
function normalizeString(value) {
    if (typeof value === 'string')
        return value;
    if (Array.isArray(value) && typeof value[0] === 'string')
        return value[0];
    return undefined;
}
function getTenantIdForVsCodeAuth() {
    return (process.env.MCP_OAUTH_TENANT_ID ??
        process.env.GRAPH_TENANT_ID ??
        process.env.TEAMS_APP_TENANT_ID ??
        process.env.AZURE_TENANT_ID ??
        'common');
}
function getPublicBaseUrl(req) {
    const configured = process.env.PUBLIC_BASE_URL;
    if (configured)
        return configured.replace(/\/$/, '');
    const host = req.get('host');
    return `${req.protocol}://${host}`.replace(/\/$/, '');
}
function authorizeEndpoint(tenantId) {
    return `https://login.microsoftonline.com/${tenantId}/oauth2/v2.0/authorize`;
}
function tokenEndpoint(tenantId) {
    return `https://login.microsoftonline.com/${tenantId}/oauth2/v2.0/token`;
}
function getDefaultScope(clientId) {
    // Default to requesting an access token for this MCP API.
    // Assumes the app registration exposes an `access_as_user` scope.
    const apiScope = `api://${clientId}/access_as_user`;
    return `openid profile offline_access ${apiScope}`;
}
function getAllowedRedirectUriPrefixes() {
    const fromEnv = (process.env.MCP_OAUTH_REDIRECT_URI_PREFIXES ?? '').trim();
    if (fromEnv) {
        return fromEnv
            .split(',')
            .map(s => s.trim())
            .filter(Boolean);
    }
    // VS Code loopback redirect
    return ['http://127.0.0.1', 'http://localhost'];
}
function validateClientAndRedirect(clientId, redirectUri) {
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
app.get('/.well-known/openid-configuration', (req, res) => {
    const baseUrl = getPublicBaseUrl(req);
    res.setHeader('Cache-Control', 'no-store');
    res.json({
        issuer: baseUrl,
        authorization_endpoint: `${baseUrl}/authorize`,
        token_endpoint: `${baseUrl}/token`,
        response_types_supported: ['code'],
        grant_types_supported: ['authorization_code', 'refresh_token'],
        code_challenge_methods_supported: ['S256'],
        token_endpoint_auth_methods_supported: ['client_secret_post', 'none']
    });
});
// VS Code starts auth by opening this URL in the browser
app.get(['/authorize', '/oauth2/v2.0/authorize'], (req, res) => {
    try {
        const tenantId = getTenantIdForVsCodeAuth();
        const clientId = requiredValue('client_id', normalizeString(req.query.client_id));
        const redirectUri = requiredValue('redirect_uri', normalizeString(req.query.redirect_uri));
        const state = requiredValue('state', normalizeString(req.query.state));
        const codeChallenge = requiredValue('code_challenge', normalizeString(req.query.code_challenge));
        const codeChallengeMethod = normalizeString(req.query.code_challenge_method) ?? 'S256';
        validateClientAndRedirect(clientId, redirectUri);
        const scope = normalizeString(req.query.scope) ?? process.env.MCP_OAUTH_SCOPES ?? getDefaultScope(clientId);
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
        if (prompt)
            upstream.searchParams.set('prompt', prompt);
        const loginHint = normalizeString(req.query.login_hint);
        if (loginHint)
            upstream.searchParams.set('login_hint', loginHint);
        res.redirect(upstream.toString());
    }
    catch (e) {
        res.status(400).send(String(e));
    }
});
// VS Code exchanges the auth code for tokens here
app.post(['/token', '/oauth2/v2.0/token'], async (req, res) => {
    try {
        const tenantId = getTenantIdForVsCodeAuth();
        const clientId = requiredValue('client_id', normalizeString(req.body?.client_id));
        const redirectUri = requiredValue('redirect_uri', normalizeString(req.body?.redirect_uri));
        validateClientAndRedirect(clientId, redirectUri);
        const grantType = requiredValue('grant_type', normalizeString(req.body?.grant_type));
        const body = new URLSearchParams();
        body.set('client_id', clientId);
        body.set('grant_type', grantType);
        body.set('redirect_uri', redirectUri);
        const clientSecret = process.env.MCP_OAUTH_CLIENT_SECRET ?? process.env.GRAPH_CLIENT_SECRET;
        if (clientSecret) {
            body.set('client_secret', clientSecret);
        }
        const scope = normalizeString(req.body?.scope);
        if (scope) {
            body.set('scope', scope);
        }
        if (grantType === 'authorization_code') {
            body.set('code', requiredValue('code', normalizeString(req.body?.code)));
            const verifier = normalizeString(req.body?.code_verifier);
            if (verifier)
                body.set('code_verifier', verifier);
        }
        else if (grantType === 'refresh_token') {
            body.set('refresh_token', requiredValue('refresh_token', normalizeString(req.body?.refresh_token)));
        }
        else {
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
        }
        catch {
            res.type('text/plain').send(text);
        }
    }
    catch (e) {
        res.status(400).json({ error: 'invalid_request', error_description: String(e) });
    }
});
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