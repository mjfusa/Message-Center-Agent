# Message Center MCP Server (Graph)

This server exposes MCP tools for **Microsoft Graph Message Center**.

## Prereqs

- Node.js `>= 20`
- This server listens on **port 8080** by default.

## Build and run

From the repo root (`C:\p\Message-Center-Agent`):

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

If you are already in the server folder (`C:\p\Message-Center-Agent\mcp-message-center-server`), do **not** use `--prefix` (it becomes relative to the current directory and can create a duplicated path). Use:
- `npm install`
- `npm run dev`

Note: this repo does not have a root `package.json`. If you run `npm install` or `npm run ...` from the repo root without `--prefix`, you may get `ENOENT`.

Health check:
- `http://localhost:8080/healthz`

MCP endpoint:
- `http://localhost:8080/mcp`

## Configuration (Graph OAuth)

This server supports Authorization Code + PKCE for Microsoft Graph.

Create and fill:
- `mcp-message-center-server/.env.local` (gitignored)

Typical variables:
- `PORT=8080`
- `PUBLIC_BASE_URL=http://localhost:8080`
- `GRAPH_TENANT_ID=...`
- `GRAPH_CLIENT_ID=...`
- `GRAPH_CLIENT_SECRET=...`
- `GRAPH_REDIRECT_URI=http://localhost:8080/auth/graph/callback`
- `GRAPH_SCOPES=https://graph.microsoft.com/ServiceMessage.Read.All offline_access openid profile`

Notes:
- The server auto-loads `.env.local` at startup (via `dotenv`).
- Tokens are cached **in-memory**, so restarting the server requires signing in again.

## Smoke tests

PowerShell scripts are in `mcp-message-center-server/scripts/`.

- Get Graph login URL (interactive sign-in):
  - `pwsh -File mcp-message-center-server/scripts/GetGraphLoginUrl.ps1`
  - Open the returned `loginUrl` in a browser and complete sign-in.

- Fetch messages:
  - `pwsh -File mcp-message-center-server/scripts/GetMessages.ps1 -Top 5 -Count:$true`

If you see `401 InvalidAuthenticationToken` with `Access token is empty`, you have not completed sign-in for the currently running server process.

## Schema generation

Tool input schemas are generated from:
- `appPackage/apiSpecificationFile/openapi.json`

Generated file:
- `mcp-message-center-server/src/generated/messagesInputSchema.ts`

The `accessToken` tool argument remains MCP-only (not in OpenAPI) and is layered on top of the generated schema.

## MCP request header

When calling `/mcp` directly, include:
- `Accept: application/json, text/event-stream`

The provided scripts already set this header.
