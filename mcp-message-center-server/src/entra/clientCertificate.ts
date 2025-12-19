import { DefaultAzureCredential } from '@azure/identity';
import { SecretClient } from '@azure/keyvault-secrets';

function required(name: string, value: string | undefined) {
  if (!value) {
    throw new Error(`Missing required env var: ${name}`);
  }
  return value;
}

let cachedPrivateKeyPromise: Promise<string> | undefined;
let cachedPrivateKey: string | undefined;

export function normalizePrivateKeyFromSecretValue(secretValue: string): string {
  const trimmed = secretValue.trim();

  // Support either raw PEM, or JSON like {"privateKey":"..."}.
  if (trimmed.startsWith('{')) {
    try {
      const parsed = JSON.parse(trimmed) as Record<string, unknown>;
      const candidate =
        (typeof parsed.privateKey === 'string' && parsed.privateKey) ||
        (typeof parsed.privateKeyPem === 'string' && parsed.privateKeyPem);
      if (candidate) return normalizePrivateKeyFromSecretValue(candidate);
    } catch {
      // fall through
    }
  }

  // Many secret stores copy/paste PEM with literal "\n" sequences.
  // Convert those back into actual newlines.
  return trimmed.includes('\\n') ? trimmed.replace(/\\n/g, '\n') : trimmed;
}

export async function getPrivateKeyFromKeyVault(): Promise<string> {
  if (cachedPrivateKey) return cachedPrivateKey;
  if (cachedPrivateKeyPromise) return cachedPrivateKeyPromise;

  cachedPrivateKeyPromise = (async () => {
    const vaultUrl = required('GRAPH_CLIENT_CERT_KEYVAULT_URL', process.env.GRAPH_CLIENT_CERT_KEYVAULT_URL);
    const secretName = required('GRAPH_CLIENT_CERT_SECRET_NAME', process.env.GRAPH_CLIENT_CERT_SECRET_NAME);
    const secretVersion = process.env.GRAPH_CLIENT_CERT_SECRET_VERSION;

    const credential = new DefaultAzureCredential();
    const client = new SecretClient(vaultUrl, credential);

    const secret = await client.getSecret(secretName, {
      version: secretVersion || undefined
    });

    if (!secret.value) {
      throw new Error(
        `Key Vault secret '${secretName}' in '${vaultUrl}' returned no value. Ensure it is a secret (not a certificate object) and has a value.`
      );
    }

    cachedPrivateKey = normalizePrivateKeyFromSecretValue(secret.value);
    return cachedPrivateKey;
  })();

  try {
    return await cachedPrivateKeyPromise;
  } catch (e) {
    cachedPrivateKeyPromise = undefined;
    throw e;
  }
}

export async function getClientCertificateFromEnvOrKeyVault(): Promise<{ thumbprint: string; privateKey: string }> {
  const thumbprint = required('GRAPH_CLIENT_CERT_THUMBPRINT', process.env.GRAPH_CLIENT_CERT_THUMBPRINT);
  const privateKey = await getPrivateKeyFromKeyVault();
  return { thumbprint, privateKey };
}
