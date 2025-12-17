import { ConfidentialClientApplication } from '@azure/msal-node';

function required(name: string, value: string | undefined) {
  if (!value) {
    throw new Error(`Missing required env var: ${name}`);
  }
  return value;
}

function getTenantId() {
  return (
    process.env.GRAPH_TENANT_ID ??
    process.env.TEAMS_APP_TENANT_ID ??
    process.env.AZURE_TENANT_ID
  );
}

function getOboScopes(): string[] {
  const raw = process.env.GRAPH_OBO_SCOPES ?? 'https://graph.microsoft.com/.default';
  return raw.split(/\s+/).filter(Boolean);
}

let cachedClient: ConfidentialClientApplication | undefined;

function getMsalClient(): ConfidentialClientApplication {
  if (cachedClient) return cachedClient;

  const tenantId = required('GRAPH_TENANT_ID (or TEAMS_APP_TENANT_ID)', getTenantId());
  const clientId = required('GRAPH_CLIENT_ID', process.env.GRAPH_CLIENT_ID);
  const clientSecret = required('GRAPH_CLIENT_SECRET', process.env.GRAPH_CLIENT_SECRET);

  cachedClient = new ConfidentialClientApplication({
    auth: {
      clientId,
      authority: `https://login.microsoftonline.com/${tenantId}`,
      clientSecret
    }
  });

  return cachedClient;
}

export type GraphOboResult = {
  accessToken: string;
  scopes: string[];
  expiresAtEpochMs?: number;
};

export async function acquireGraphAccessTokenOnBehalfOf(userAssertion: string): Promise<GraphOboResult> {
  const client = getMsalClient();
  const scopes = getOboScopes();

  const result = await client.acquireTokenOnBehalfOf({
    oboAssertion: userAssertion,
    scopes
  });

  if (!result?.accessToken) {
    throw new Error('OBO token acquisition returned no access token.');
  }

  return {
    accessToken: result.accessToken,
    scopes,
    expiresAtEpochMs: result.expiresOn?.getTime()
  };
}
