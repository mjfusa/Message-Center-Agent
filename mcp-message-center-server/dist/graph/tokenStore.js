const sessionTokens = new Map();
export function getTokenForSession(sessionId) {
    return sessionTokens.get(sessionId);
}
export function setTokenForSession(sessionId, token) {
    sessionTokens.set(sessionId, token);
}
export function clearTokenForSession(sessionId) {
    sessionTokens.delete(sessionId);
}
//# sourceMappingURL=tokenStore.js.map