# Microsoft 365 Roadmap MCP Server

This MCP (Model Context Protocol) server exposes a tool (getM365RoadmapInfo) for querying the **Microsoft 365 Roadmap** public API at `https://www.microsoft.com/releasecommunications/api/v2/m365`.

This project generates the MCP input schema for the `getM365RoadmapInfo` MCP tool from the OpenAPI description in the spec `roadmap-openapi.json`.

## What this server does

- Queries the **public** Microsoft 365 Roadmap API (no Microsoft Graph).
- Requires **no** Microsoft Entra app registration and **no** OAuth tokens.
- Supports OData-style query parameters via the MCP tool arguments: `filter`, `orderby`, `top`, `skip`, `count`.

What it does not do:

- It does not read from your tenant and cannot access private tenant data.
- It does not implement additional filtering logic beyond passing OData parameters through to the public API.

## Endpoints

- Health check:
  - `GET /healthz`
  - Returns `200 OK` if the server is running.

- MCP endpoint:
  - `POST /mcp`
  - Accepts MCP tool requests for Microsoft 365 Roadmap query operations.
  - Supports both JSON and SSE response formats based on `Accept` header.

## Prereqs

- Node.js `>= 20`
- This server listens on **port 8081** by default (override with `PORT`).

## Runtime configuration

- `PORT`: sets the listening port (default: `8081`).
  - Example: `PORT=9001 npm --prefix mcp-roadmap-server run start`

## Quick start (first successful call)

1) Install + run locally:

- `npm --prefix mcp-roadmap-server install`
- `npm --prefix mcp-roadmap-server run dev`

2) Verify health:

- `GET http://localhost:8081/healthz`

3) Verify MCP is reachable (list tools):

- PowerShell:

```powershell
$body = @{
  jsonrpc = '2.0'
  id      = 1
  method  = 'tools/list'
  params  = @{}
} | ConvertTo-Json -Depth 10

Invoke-RestMethod `
  -Method Post `
  -Uri 'http://localhost:8081/mcp' `
  -ContentType 'application/json' `
  -Headers @{ Accept = 'application/json' } `
  -Body $body
```

4) Call the tool:

```powershell
$body = @{
  jsonrpc = '2.0'
  id      = 2
  method  = 'tools/call'
  params  = @{
    name      = 'getM365RoadmapInfo'
    arguments = @{ top = 5; orderby = 'created desc'; count = $true }
  }
} | ConvertTo-Json -Depth 10

Invoke-RestMethod `
  -Method Post `
  -Uri 'http://localhost:8081/mcp' `
  -ContentType 'application/json' `
  -Headers @{ Accept = 'application/json' } `
  -Body $body
```

## Build and run

From the repo root:

- Install dependencies (recommended):
  - `cd mcp-roadmap-server; npm install`

- Generate schemas from OpenAPI:
  - `npm --prefix mcp-roadmap-server run generate`
- Build:
  - `npm --prefix mcp-roadmap-server run build`
- Run (prod build):
  - `npm --prefix mcp-roadmap-server run start`
- Run (dev watch):
  - `npm --prefix mcp-roadmap-server run dev`

If you are already in the `mcp-roadmap-server` folder, do **not** use `--prefix` (it becomes relative to the current directory and can create a duplicated path like `mcp-roadmap-server\mcp-roadmap-server\package.json`). Use:
- `npm install`
- `npm run dev`

<!-- Note: in the monorepo, there is no root `package.json`. If you run `npm install` or `npm run ...` from the monorepo root without `--prefix`, you may get `ENOENT`. -->

Health check:
- `http://localhost:8081/healthz`

MCP endpoint:
- `http://localhost:8081/mcp`

## Common OData query patterns

- Count-only (no items): set `top=0` and `count=true`.
- Pagination: use `top` + `skip` (for example: `top=20`, `skip=20`).
- Date filtering: use the `created` field (not `createdDateTime`).

## Example queries

These examples go into the `arguments` object for `getM365RoadmapInfo`.

- “Newest 5 items”:

```json
{ "orderby": "created desc", "top": 5, "count": true }
```

- “Title contains ‘copilot’ (case-insensitive)”:

```json
{ "filter": "contains(tolower(title), 'copilot')", "top": 10, "count": true }
```

- “Copilot items since a date”:

```json
{ "filter": "contains(tolower(title), 'copilot') and created ge 2025-10-08T00:00:00Z", "top": 10, "count": true }
```

- “Specific ID (recommended for ID lookups)”:

```json
{ "filter": "id eq 476488", "top": 5, "count": true }
```

- “Multiple IDs”:

```json
{ "filter": "id in (476488, 501560, 501591)", "top": 10, "count": true }
```

## Direct HTTP examples (no MCP client)

You can call the MCP JSON-RPC endpoint directly.

- `curl` (tools list):

```bash
curl -sS -X POST 'http://localhost:8081/mcp' \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'
```

- `curl` (tool call):

```bash
curl -sS -X POST 'http://localhost:8081/mcp' \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  --data '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"getM365RoadmapInfo","arguments":{"top":5,"orderby":"created desc","count":true}}}'
```

## MCP protocol methods (JSON-RPC)

This server supports the standard MCP JSON-RPC methods over `POST /mcp` (handled by the MCP SDK + Streamable HTTP transport).

- `initialize`
  - MCP handshake method (clients typically call this automatically).
  - Returns `serverInfo` and `capabilities`.

- `tools/list`
  - Lists the available tools and their input schemas.

- `tools/call`
  - Calls a tool by name with an `arguments` object.

Examples (JSON-RPC 2.0):

- List tools:
```json
{ "jsonrpc": "2.0", "id": 1, "method": "tools/list", "params": {} }
```

- Call `getM365RoadmapInfo`:
```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "tools/call",
  "params": {
    "name": "getM365RoadmapInfo",
    "arguments": { "top": 5, "count": true }
  }
}
```

## MCP Tool

- `getM365RoadmapInfo`
  - Fetch Microsoft 365 Roadmap items with OData query support.
  - Supports OData parameters: `filter`, `orderby`, `top`, `skip`, `count`.
  - `top=0` is allowed for count-only queries (returns empty `value` with `@odata.count`).

## Smoke tests

PowerShell scripts:

- Preferred (co-located with this server):
  - `pwsh -File mcp-roadmap-server/scripts/GetRoadMapInfo.ps1 -Top 1 -Count:$true`

Note: in the monorepo, the same script is also available under `mcp-message-center-server/scripts/` (defaults to 8081 as well).

## Schema generation

Tool input schemas are generated from:
- `openapi/roadmap-openapi.json`

Generated file:
- `mcp-roadmap-server/src/generated/roadmapInputSchema.ts`

## MCP request header

When calling `/mcp` directly, include:
- `Accept: application/json, text/event-stream`

The provided scripts already set this header.

## Response shape

- `getM365RoadmapInfo` returns the upstream API payload as **structured content** when possible.
- When a response contains a `value` array, the server adds a per-item `url` field (when it can derive one from `id`) pointing to the public roadmap website.
- On failures, the response includes HTTP status and the parsed error payload from the upstream API.

## Troubleshooting

- `405 Method Not Allowed` on `/mcp`: `/mcp` is **POST-only**.
- Health is OK but tool calls fail: verify outbound HTTPS access to `www.microsoft.com` (corporate proxy / SSL inspection can interfere).
- SSE looks noisy in terminals: set `Accept: application/json` (SSE is enabled when clients request `text/event-stream`).
- Wrong port: the default is `8081`, but deployments often set `PORT`.

## Build/test/deploy automation

This repo includes an end-to-end PowerShell script:

- [dev/BuildTestDeploy.ps1](dev/BuildTestDeploy.ps1)

Common runs:

- Safe validation (no Azure calls):
  - `pwsh -NoProfile -File mcp-roadmap-server/dev/BuildTestDeploy.ps1 -AcrName <acrName> -SkipLocalBuild -SkipAcrBuild -SkipDeploy`

- ACR build + deploy to Azure Container Apps, then verify health + MCP endpoint:
  - `pwsh -NoProfile -File mcp-roadmap-server/dev/BuildTestDeploy.ps1 -AcrName <acrName> -WaitForHealth -TestMcp`

<!-- Monorepo note: the Dockerfile uses monorepo-relative `COPY` paths, so the script automatically uses the monorepo root as the ACR build context when needed. -->

## Setting up Azure resources

See [infra/README.md](infra/README.md) for standalone deployment instructions.

## Deployment notes

- `/mcp` is **POST-only** and may stream responses when clients request `text/event-stream`.
- If you put this behind a reverse proxy (or Container Apps ingress), ensure it allows POSTs to `/mcp` and does not buffer/strip SSE responses.

## Related projects

- [mcp-message-center-server](../mcp-message-center-server/README.md): MCP server for Microsoft Graph Message Center.
- [modelcontextprotocol/typescript-sdk](https://github.com/modelcontextprotocol/typescript-sdk): TypeScript SDK for building MCP servers and clients.
- **Message Center Agent:** https://github.com/microsoft/Message-Center-Agent