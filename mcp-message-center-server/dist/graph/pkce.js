import crypto from 'crypto';
function base64UrlEncode(buffer) {
    return buffer
        .toString('base64')
        .replace(/\+/g, '-')
        .replace(/\//g, '_')
        .replace(/=+$/g, '');
}
export function generateCodeVerifier() {
    // RFC 7636 suggests 43-128 characters; use 32 random bytes -> ~43 chars base64url.
    return base64UrlEncode(crypto.randomBytes(32));
}
export function codeChallengeS256(verifier) {
    const hash = crypto.createHash('sha256').update(verifier).digest();
    return base64UrlEncode(hash);
}
export function generateState() {
    return base64UrlEncode(crypto.randomBytes(32));
}
//# sourceMappingURL=pkce.js.map