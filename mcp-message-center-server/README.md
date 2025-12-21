# Microsoft Admin Message Center MCP Server (Microsoft Graph)

This MCP (Model Context Protocol) server exposes a tool (**getMessages**) for querying Microsoft Admin Center Message Center messages via the [/admin/serviceAnnouncement/messages](https://learn.microsoft.com/en-us/graph/api/serviceannouncement-list-messages?view=graph-rest-1.0&tabs=http) API.

This project generates the MCP input schema for the `getMessages` MCP tool from the OpenAPI description in the spec for the graph API in the spec `openapi.json`.

## Endpoints
- Health check:
  - `GET /healthz`
  - Returns `200 OK` if the server is running.

- Discovery:
  - `GET /.well-known/openid-configuration` or `GET /discover`
  - Returns MCP service discovery information.

- MCP endpoint:
  - `POST /mcp`
  - Accepts MCP tool requests for Message Center message query operations.
  - Requires authentication/authorization (see below).
  - Supports both JSON and SSE response formats based on `Accept` header.

## MCP protocol methods (JSON-RPC)

This server supports the standard MCP JSON-RPC methods over `POST /mcp` (handled by the MCP SDK + Streamable HTTP transport. Both implemented here: https://github.com/modelcontextprotocol/typescript-sdk).

- `initialize`
  - MCP handshake method (clients typically call this automatically).
  - Returns `serverInfo` and `capabilities`.

- `tools/list`
  - Lists the available tools and their input schemas.

- `tools/call`
  - Calls a tool by name with an `arguments` object. Calls the `getMessages` tool in this server.

Examples (JSON-RPC 2.0):

- List tools:
```json
{ "jsonrpc": "2.0", "id": 1, "method": "tools/list", "params": {} }
```

- Call `getMessages`:
```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "tools/call",
  "params": {
    "name": "getMessages",
    "arguments": { "top": 5, "count": true }
  }
}
```

## MCP Tool
- `getMessages`
  - Fetch Message Center messages with OData query support.
  - See [Microsoft Graph docs](https://learn.microsoft.com/en-us/graph/api/serviceannouncement-list-messages?view=graph-rest-1.0&tabs=http) for details on supported query parameters.
  - Supports OData parameters: `filter`, `orderby`, `top`, `skip`, `count`.
  - `top=0` is allowed for count-only queries (returns empty `value` with `@odata.count`).
  - Requires Microsoft Graph **Message Center Reader** role.
  - Authentication: The server will attempt to acquire a token using OBO (On-Behalf-Of) flow based on the caller's token.
  - If the caller's token is already a Microsoft Graph token, it will be used as-is.
  - If no valid token can be acquired, the server returns `401 InvalidAuthenticationToken`.
  - If the caller's token lacks the required role, Microsoft Graph returns `403 Forbidden`.
  - The server propagates this `403` back to the caller.
  - accessToken (optional): MCP-only argument to provide a Microsoft Graph access token directly.
    - If provided, this token is used as-is for Microsoft Graph calls.
    - Useful for testing or scenarios where the caller manages tokens directly.
    - Production safety: this bypass is disabled when `NODE_ENV=production` unless `ALLOW_MCP_ACCESS_TOKEN_ARG=true`.

## Quick start

Local (no Azure):

- `cd mcp-message-center-server; npm install`
- `npm run dev`
- Verify health: `http://localhost:8080/healthz`

Then call the tool (recommended path):

- Get an MCP API token (first time may require consent):
  - `pwsh -File mcp-message-center-server/scripts/GetMcpAccessToken.ps1 -Login -TenantId <tenantGuidOrDomain>`
- Fetch messages:
  - `pwsh -File mcp-message-center-server/scripts/GetMessages.ps1 -McpAccessToken (pwsh -File mcp-message-center-server/scripts/GetMcpAccessToken.ps1) -Top 5 -Count:$true`

## Authentication overview

Preferred for most clients (including declarative agents):

- Send `Authorization: Bearer <user token for this MCP API>` to `POST /mcp`
- Server uses OBO to acquire a delegated Microsoft Graph token

Testing-only bypasses:

- Provide a Graph token via the MCP tool argument `accessToken`, or set `GRAPH_ACCESS_TOKEN`
- These bypasses are disabled when `NODE_ENV=production` unless `ALLOW_MCP_ACCESS_TOKEN_ARG=true`

## Prereqs

- Node.js `>= 20`
- This server listens on **port 8080** by default.

## Build and run

From the repo root:

- Install dependencies (recommended):
  - `cd mcp-message-center-server; npm install`

- Generate schemas from OpenAPI:
  - `npm --prefix mcp-message-center-server run generate`
- Build:
  - `npm --prefix mcp-message-center-server run build`
- Run (prod build):
  - `npm --prefix mcp-message-center-server run start`
- Run (dev watch):
  - `npm --prefix mcp-message-center-server run dev`

If you are already in the `mcp-message-center-server` folder, do **not** use `--prefix` (it becomes relative to the current directory and can create a duplicated path). Use:
- `npm install`
- `npm run dev`

<!-- Note: in the monorepo, there is no root `package.json`. If you run `npm install` or `npm run ...` from the monorepo root without `--prefix`, you may get `ENOENT`. -->

Health check:
- `http://localhost:8080/healthz`

MCP endpoint:
- `http://localhost:8080/mcp`

## App registration requirements (Microsoft Entra ID)

This server expects a **single** Microsoft Entra app registration to act as both:

- The **MCP API resource** (audience for callers of `POST /mcp`)
- The **confidential client** used by the server to perform OBO to Microsoft Graph, and to proxy `/authorize` + `/token`

Minimum configuration:

- **Expose an API**
  - Set the Application ID URI (recommended): `api://<clientId>`
  - Add an OAuth2 delegated scope named: `access_as_user`
    - This is the scope requested by the helper scripts (e.g., `api://<clientId>/access_as_user`).

- **API permissions (Microsoft Graph)**
  - Add **Delegated** permission: `ServiceMessage.Read.All`
  - Grant **admin consent** for the tenant
  - Note: the calling **user** still needs the Microsoft 365 admin role (e.g., *Message Center Reader*) for Message Center access.

- **Authentication (redirect URIs)**
  - Add the redirect URI your client uses for the auth code flow.
    - Default for `scripts/SmokeTokenProxyPkce.ps1`: `http://127.0.0.1:8400/`
    - If using Teams declarative agents: `https://teams.microsoft.com/api/platform/v1.0/oAuthRedirect`
  - The server also enforces an allowlist for redirect URIs (see `MCP_OAUTH_REDIRECT_URI_PREFIXES`). Ensure your app registration redirect URIs are compatible with that allowlist.

- **Certificates & secrets**
  - Local/dev (simplest): create a **client secret** and set `GRAPH_CLIENT_SECRET` (and optionally `MCP_OAUTH_CLIENT_SECRET`).
  - Azure-hosted (recommended): add a **certificate** to the app registration (public key), store the private key PEM in Key Vault, and configure:
    - `GRAPH_CLIENT_CERT_THUMBPRINT`
    - `GRAPH_CLIENT_CERT_KEYVAULT_URL`
    - `GRAPH_CLIENT_CERT_SECRET_NAME` (this is only the secret name, not the secret value)
    - Optional: `GRAPH_CLIENT_CERT_SECRET_VERSION`

## Configuration (OBO for declarative agents)

For **Microsoft declarative agent clients** (non-interactive callers), the recommended pattern is:

- The client calls `POST /mcp` with `Authorization: Bearer <user token for this MCP API>`.
- This server uses **On-Behalf-Of (OBO)** to exchange that token for a **Microsoft Graph delegated** access token.
- Microsoft Graph enforces the user role requirement (e.g., Message Center Reader).

Required variables (same app registration as above):
- `GRAPH_TENANT_ID=...`
- `GRAPH_CLIENT_ID=...`

Credential options (choose one):

- **Preferred (Azure-hosted)**: certificate private key loaded from **Azure Key Vault** using managed identity
  - `GRAPH_CLIENT_CERT_KEYVAULT_URL=https://<vault>.vault.azure.net/`
  - `GRAPH_CLIENT_CERT_SECRET_NAME=<secretName>`
  - `GRAPH_CLIENT_CERT_THUMBPRINT=<hexThumbprint>`
  - Optional: `GRAPH_CLIENT_CERT_SECRET_VERSION=<version>`

Note: the `/token` OAuth proxy endpoint also uses these credentials. If no client secret is configured (`MCP_OAUTH_CLIENT_SECRET`/`GRAPH_CLIENT_SECRET`), it will authenticate to Entra using `private_key_jwt` with the Key Vault certificate settings.

Optional variables:
- `GRAPH_OBO_SCOPES=https://graph.microsoft.com/.default`
  - Default is `https://graph.microsoft.com/.default` (recommended when Graph delegated permissions are pre-consented).
- `MCP_REQUIRE_AUTH=true`
  - When set, `POST /mcp` returns `401` if the `Authorization` header is missing.

Notes:
- If a caller sends a **Graph** token directly in `Authorization`, the server will use it as-is.
- The legacy dev/test paths still work (tool arg `accessToken` or `GRAPH_ACCESS_TOKEN`).
  - When `NODE_ENV=production`, these dev/test bypasses are disabled unless `ALLOW_MCP_ACCESS_TOKEN_ARG=true`.

## OAuth redirect allowlist (VS Code + Teams)

This server intentionally enforces an allowlist for `redirect_uri` on the `/authorize` and `/token` endpoints to avoid becoming an open OAuth proxy.

Defaults:
- VS Code loopback (`http://127.0.0.1`, `http://localhost`)
- Teams declarative agent redirect (`https://teams.microsoft.com/api/platform/v1.0/oAuthRedirect`)

If you use a different redirect (e.g., a custom localhost hostname or a different Teams endpoint), set:
- `MCP_OAUTH_REDIRECT_URI_PREFIXES=<comma-separated prefixes>`

Example:
- `MCP_OAUTH_REDIRECT_URI_PREFIXES=http://127.0.0.1,http://localhost,https://teams.microsoft.com/api/platform/v1.0/oAuthRedirect`

## Smoke tests

PowerShell scripts are in `mcp-message-center-server/scripts/`.

- Fetch messages:
  - `pwsh -File mcp-message-center-server/scripts/GetMessages.ps1 -Top 5 -Count:$true`

- Smoke test `/authorize` + `/token` proxy using PKCE (manual paste of the redirect URL):
  - `pwsh -File mcp-message-center-server/scripts/SmokeTokenProxyPkce.ps1`

### Smoke test using OBO (non-interactive)

If you want to test the OBO path end-to-end (send a user token for this MCP API to `/mcp`):

1) Get an MCP API user token via Azure CLI (first time may require consent):

- First-time interactive consent/login:
  - `pwsh -File mcp-message-center-server/scripts/GetMcpAccessToken.ps1 -Login -TenantId <tenantGuidOrDomain>`

- Subsequent token fetch (prints the token):
  - `pwsh -File mcp-message-center-server/scripts/GetMcpAccessToken.ps1`

2) Call `getMessages` with the MCP token:

- `pwsh -File mcp-message-center-server/scripts/GetMessages.ps1 -McpAccessToken (pwsh -File mcp-message-center-server/scripts/GetMcpAccessToken.ps1) -Top 5 -Count:$true`

If you see `401 InvalidAuthenticationToken` with `Access token is empty`, you have not completed sign-in for the currently running server process.

## Schema generation

Tool input schemas are generated from:
- `openapi/openapi.json`

Generated file:
- `mcp-message-center-server/src/generated/messagesInputSchema.ts`

The `accessToken` tool argument remains MCP-only (not in OpenAPI) and is layered on top of the generated schema.

## MCP request header

When calling `/mcp` directly, include:
- `Accept: application/json, text/event-stream`

The provided scripts already set this header.

## Calling `/mcp` directly (PowerShell)

The scripts in `mcp-message-center-server/scripts/` are the easiest way to call the server. If you want to call `/mcp` directly, these examples work on Windows PowerShell / pwsh:

- List tools:

```powershell
$body = @{ jsonrpc = '2.0'; id = 1; method = 'tools/list'; params = @{} } | ConvertTo-Json -Depth 10
Invoke-RestMethod -Method Post -Uri 'http://localhost:8080/mcp' -ContentType 'application/json' -Headers @{ Accept = 'application/json, text/event-stream' } -Body $body
```

- Call `getMessages` (using an MCP API token):

```powershell
$mcpToken = pwsh -File mcp-message-center-server/scripts/GetMcpAccessToken.ps1
$body = @{ jsonrpc = '2.0'; id = 2; method = 'tools/call'; params = @{ name = 'getMessages'; arguments = @{ top = 5; count = $true } } } | ConvertTo-Json -Depth 10
Invoke-RestMethod -Method Post -Uri 'http://localhost:8080/mcp' -ContentType 'application/json' -Headers @{ Accept = 'application/json, text/event-stream'; Authorization = "Bearer $mcpToken" } -Body $body
```

## Response format

- Tool results are returned as MCP `content` (text) and may also include `structuredContent`.
- Responses can be JSON or SSE depending on the `Accept` header.

## Environment variables (reference)

For a complete template, see [mcp-message-center-server/.env.local.sample](mcp-message-center-server/.env.local.sample).

Common variables:

- Required for OBO: `GRAPH_TENANT_ID`, `GRAPH_CLIENT_ID`
- Confidential client (choose one):
  - `GRAPH_CLIENT_SECRET` (local/dev), or
  - `GRAPH_CLIENT_CERT_THUMBPRINT`, `GRAPH_CLIENT_CERT_KEYVAULT_URL`, `GRAPH_CLIENT_CERT_SECRET_NAME` (+ optional `GRAPH_CLIENT_CERT_SECRET_VERSION`) (Azure-hosted)
- OAuth proxy: `MCP_OAUTH_REDIRECT_URI_PREFIXES`, `MCP_OAUTH_SCOPES` (optional)
- Behavior toggles: `MCP_REQUIRE_AUTH`, `ALLOW_MCP_ACCESS_TOKEN_ARG`, `PUBLIC_BASE_URL`, `PORT`

## Troubleshooting

- `Cannot GET /mcp`: expected. MCP requests use `POST /mcp`.
- `401` from this server: missing `Authorization` header while `MCP_REQUIRE_AUTH=true`, or caller token is invalid.
- `401` from Graph:
  - OBO token exchange failed (app registration missing delegated Graph permission/admin consent), or
  - caller did not send an MCP API token (so the server could not do OBO)
- `403` from Graph: the user likely lacks the required Microsoft 365 admin role (e.g., Message Center Reader).
- `accessToken_disabled`: you are using the testing bypass in production; switch to OBO or set `ALLOW_MCP_ACCESS_TOKEN_ARG=true` explicitly.

## Build/test/deploy automation

This repo includes an end-to-end PowerShell script:

- [mcp-message-center-server/dev/BuildTestDeploy.ps1](mcp-message-center-server/dev/BuildTestDeploy.ps1)

Common runs:

- Safe validation (no Azure calls):
  - `pwsh -NoProfile -File mcp-message-center-server/dev/BuildTestDeploy.ps1 -AcrName <acrName> -SkipLocalTest -SkipAcrBuild -SkipDeploy`

- ACR build + deploy to Azure Container Apps, then verify health + MCP endpoint:
  - `pwsh -NoProfile -File mcp-message-center-server/dev/BuildTestDeploy.ps1 -AcrName <acrName> -WaitForHealth -TestMcp`

<!-- Monorepo note: the Dockerfile uses monorepo-relative `COPY` paths, so the script automatically uses the monorepo root as the ACR build context when needed. -->

## OAuth flow diagram

Client (VS Code / Bruno)
  |
  | (1) GET http://localhost:8080/authorize?client_id=...&redirect_uri=http://127.0.0.1:<port>/&code_challenge=...
  v
MCP Server (/authorize)
  |
  | (2) 302 redirect to Entra authorize endpoint
  v
Entra ID (MCP API)
  |
  | (3) User signs in + consents
  | (4) Redirects back to VS Code loopback redirect_uri with ?code=...&state=...
  v
Client (VS Code / Bruno)
  |
  | (5) POST http://localhost:8080/token (includes code + code_verifier)
  v
MCP Server (/token)
  |
  | (6) Proxies token exchange to Entra /token
  v
Entra ID (MCP API)
  |
  | (7) Returns MCP-API access_token (+ refresh_token if allowed)
  v
Client (VS Code / Bruno)
  |
  | (8) Now call POST /mcp with Authorization: Bearer <MCP-API token>
  v
MCP Server -> (OBO) -> Entra -> Graph

## Setting up Azure resources
See [mcp-message-center-server/infra/README.md](mcp-message-center-server/infra/README.md) for standalone deployment instructions.
<!-- See [monorepo infra/README.md](../infra/README.md) for monorepo-wide deployment instructions. -->

## Related projects
- [mcp-roadmap-server](../mcp-roadmap-server/README.md): MCP server for Microsoft 365 Roadmap data.
- [modelcontextprotocol/typescript-sdk](https://github.com/modelcontextprotocol/typescript-sdk): TypeScript SDK for building MCP servers and clients.
- [Microsoft Graph Message Center API docs](https://learn.microsoft.com/en-us/graph/api/serviceannouncement-list-messages?view=graph-rest-1.0&tabs=http)
- **Message Center Agent:** https://github.com/microsoft/Message-Center-Agent