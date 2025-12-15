export type GraphTokenSet = {
  accessToken: string;
  refreshToken?: string;
  expiresAtEpochMs: number;
  scope?: string;
};

const sessionTokens = new Map<string, GraphTokenSet>();

export function getTokenForSession(sessionId: string): GraphTokenSet | undefined {
  return sessionTokens.get(sessionId);
}

export function setTokenForSession(sessionId: string, token: GraphTokenSet) {
  sessionTokens.set(sessionId, token);
}

export function clearTokenForSession(sessionId: string) {
  sessionTokens.delete(sessionId);
}
