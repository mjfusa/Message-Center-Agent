function required(name, value) {
    if (!value) {
        throw new Error(`Missing required env var: ${name}`);
    }
    return value;
}
export function getGraphEnvConfig(publicBaseUrl) {
    const tenantId = process.env.GRAPH_TENANT_ID ??
        process.env.TEAMS_APP_TENANT_ID ??
        process.env.AZURE_TENANT_ID;
    const clientId = process.env.GRAPH_CLIENT_ID;
    const clientSecret = process.env.GRAPH_CLIENT_SECRET;
    const redirectUri = process.env.GRAPH_REDIRECT_URI ?? `${publicBaseUrl.replace(/\/$/, '')}/auth/graph/callback`;
    const scopes = (process.env.GRAPH_SCOPES ??
        'https://graph.microsoft.com/ServiceMessage.Read.All offline_access openid profile').split(/\s+/).filter(Boolean);
    return {
        tenantId: required('GRAPH_TENANT_ID (or TEAMS_APP_TENANT_ID)', tenantId),
        clientId: required('GRAPH_CLIENT_ID', clientId),
        clientSecret: required('GRAPH_CLIENT_SECRET', clientSecret),
        redirectUri,
        scopes
    };
}
//# sourceMappingURL=config.js.map