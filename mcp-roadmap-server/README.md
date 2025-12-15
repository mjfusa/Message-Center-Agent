# Roadmap MCP Server

This server exposes MCP tools for the **Microsoft 365 Roadmap** public API.

## Prereqs

- Node.js `>= 20`
- This server listens on **port 8081** by default.

## Build and run

From the repo root (`C:\p\Message-Center-Agent`):

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

If you are already in the server folder (`C:\p\Message-Center-Agent\mcp-roadmap-server`), do **not** use `--prefix` (it becomes relative to the current directory and can create a duplicated path like `mcp-roadmap-server\mcp-roadmap-server\package.json`). Use:
- `npm install`
- `npm run dev`

Note: this repo does not have a root `package.json`. If you run `npm install` or `npm run ...` from the repo root without `--prefix`, you may get `ENOENT`.

Health check:
- `http://localhost:8081/healthz`

MCP endpoint:
- `http://localhost:8081/mcp`

## Smoke tests

PowerShell scripts:

- Preferred (co-located with this server):
  - `pwsh -File mcp-roadmap-server/scripts/GetRoadMapInfo.ps1 -Top 1 -Count:$true`

- Also available under the message server folder (defaults to 8081 as well):
  - `pwsh -File mcp-message-center-server/scripts/GetRoadMapInfo.ps1 -Top 1 -Count:$true`

## Tool behavior

- Supports OData parameters: `filter`, `orderby`, `top`, `skip`, `count`.
- `top=0` is allowed for count-only queries (returns empty `value` with `@odata.count`).

## Schema generation

Tool input schemas are generated from:
- `appPackage/apiSpecificationFile/roadmap-openapi.json`

Generated file:
- `mcp-roadmap-server/src/generated/roadmapInputSchema.ts`

## MCP request header

When calling `/mcp` directly, include:
- `Accept: application/json, text/event-stream`

The provided scripts already set this header.
