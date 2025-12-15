import { codeChallengeS256, generateCodeVerifier, generateState } from './pkce.js';
import { setTokenForSession, type GraphTokenSet } from './tokenStore.js';

export type GraphOAuthConfig = {
  tenantId: string;
  clientId: string;
  clientSecret: string;
  redirectUri: string;
  scopes: string[];
};

type PendingAuth = {
  sessionId: string;
  codeVerifier: string;
  createdAtEpochMs: number;
};

const pendingByState = new Map<string, PendingAuth>();

const PENDING_TTL_MS = 10 * 60 * 1000;

function cleanupPending() {
  const now = Date.now();
  for (const [state, pending] of pendingByState.entries()) {
    if (now - pending.createdAtEpochMs > PENDING_TTL_MS) {
      pendingByState.delete(state);
    }
  }
}

function tokenEndpoint(tenantId: string) {
  return `https://login.microsoftonline.com/${tenantId}/oauth2/v2.0/token`;
}

function authorizeEndpoint(tenantId: string) {
  return `https://login.microsoftonline.com/${tenantId}/oauth2/v2.0/authorize`;
}

export function buildLoginUrl(config: GraphOAuthConfig, sessionId: string) {
  cleanupPending();

  const codeVerifier = generateCodeVerifier();
  const state = generateState();

  pendingByState.set(state, {
    sessionId,
    codeVerifier,
    createdAtEpochMs: Date.now()
  });

  const url = new URL(authorizeEndpoint(config.tenantId));
  url.searchParams.set('client_id', config.clientId);
  url.searchParams.set('response_type', 'code');
  url.searchParams.set('redirect_uri', config.redirectUri);
  url.searchParams.set('response_mode', 'query');
  url.searchParams.set('scope', config.scopes.join(' '));
  url.searchParams.set('state', state);
  url.searchParams.set('code_challenge_method', 'S256');
  url.searchParams.set('code_challenge', codeChallengeS256(codeVerifier));

  return { loginUrl: url.toString(), state };
}

export async function handleCallback(config: GraphOAuthConfig, code: string, state: string) {
  cleanupPending();

  const pending = pendingByState.get(state);
  if (!pending) {
    throw new Error('Invalid or expired state. Please restart login.');
  }
  pendingByState.delete(state);

  const tokenUrl = tokenEndpoint(config.tenantId);
  const body = new URLSearchParams();
  body.set('client_id', config.clientId);
  body.set('client_secret', config.clientSecret);
  body.set('grant_type', 'authorization_code');
  body.set('code', code);
  body.set('redirect_uri', config.redirectUri);
  body.set('code_verifier', pending.codeVerifier);

  const response = await fetch(tokenUrl, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded'
    },
    body
  });

  const json = (await response.json()) as any;
  if (!response.ok) {
    const message = json?.error_description ?? json?.error ?? response.statusText;
    throw new Error(`Token exchange failed: ${message}`);
  }

  const expiresInSec = Number(json.expires_in ?? 0);
  const token: GraphTokenSet = {
    accessToken: String(json.access_token),
    refreshToken: json.refresh_token ? String(json.refresh_token) : undefined,
    scope: json.scope ? String(json.scope) : undefined,
    expiresAtEpochMs: Date.now() + expiresInSec * 1000
  };

  setTokenForSession(pending.sessionId, token);
  return { sessionId: pending.sessionId, token };
}

export async function refreshAccessToken(config: GraphOAuthConfig, refreshToken: string) {
  const tokenUrl = tokenEndpoint(config.tenantId);
  const body = new URLSearchParams();
  body.set('client_id', config.clientId);
  body.set('client_secret', config.clientSecret);
  body.set('grant_type', 'refresh_token');
  body.set('refresh_token', refreshToken);
  body.set('scope', config.scopes.join(' '));

  const response = await fetch(tokenUrl, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded'
    },
    body
  });

  const json = (await response.json()) as any;
  if (!response.ok) {
    const message = json?.error_description ?? json?.error ?? response.statusText;
    throw new Error(`Token refresh failed: ${message}`);
  }

  const expiresInSec = Number(json.expires_in ?? 0);
  const token: GraphTokenSet = {
    accessToken: String(json.access_token),
    refreshToken: json.refresh_token ? String(json.refresh_token) : refreshToken,
    scope: json.scope ? String(json.scope) : undefined,
    expiresAtEpochMs: Date.now() + expiresInSec * 1000
  };

  return token;
}
