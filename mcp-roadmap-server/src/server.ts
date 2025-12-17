import express, { Request, Response } from 'express';
import * as z from 'zod';

import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/streamableHttp.js';
import type { CallToolResult } from '@modelcontextprotocol/sdk/types.js';

import { getRoadmapInputSchema } from './generated/roadmapInputSchema.js';

const ROADMAP_BASE_URL = 'https://www.microsoft.com/releasecommunications/api/v2';

function toTextResult(value: unknown): CallToolResult {
  return {
    content: [
      {
        type: 'text',
        text: JSON.stringify(value, null, 2)
      }
    ]
  };
}

async function fetchJson(url: string, init?: RequestInit) {
  const response = await fetch(url, init);
  const text = await response.text();

  let parsed: unknown = text;
  try {
    parsed = text ? JSON.parse(text) : null;
  } catch {
    parsed = text;
  }

  return {
    ok: response.ok,
    status: response.status,
    statusText: response.statusText,
    data: parsed
  };
}

function buildUrl(baseUrl: string, requestPath: string, query: Record<string, string | undefined>) {
  const base = baseUrl.endsWith('/') ? baseUrl : `${baseUrl}/`;
  const relativePath = requestPath.startsWith('/') ? requestPath.slice(1) : requestPath;
  const url = new URL(relativePath, base);

  for (const [key, value] of Object.entries(query)) {
    if (value !== undefined && value !== '') {
      url.searchParams.set(key, value);
    }
  }

  return url.toString();
}

function getServer() {
  const server = new McpServer(
    { name: 'roadmap-mcp-server', version: '0.1.0' },
    { capabilities: { logging: {} } }
  );

  server.registerTool(
    'getRoadmapInfo',
    {
      description:
        'Retrieve Microsoft 365 Roadmap items from https://www.microsoft.com/releasecommunications/api/v2/m365 using OData query parameters.',
      inputSchema: getRoadmapInputSchema
    },
    async (args): Promise<CallToolResult> => {
      const url = buildUrl(ROADMAP_BASE_URL, '/m365', {
        $filter: (args as any).filter,
        $orderby: (args as any).orderby,
        $top: (args as any).top !== undefined ? String((args as any).top) : undefined,
        $skip: (args as any).skip !== undefined ? String((args as any).skip) : undefined,
        $count: String((args as any).count)
      });

      const result = await fetchJson(url, {
        headers: {
          Accept: 'application/json'
        }
      });

      return toTextResult({ request: { url }, response: result });
    }
  );

  return server;
}

const app = express();
app.use(express.json({ limit: '1mb' }));

app.post('/mcp', async (req: Request, res: Response) => {
  const server = getServer();

  try {
    const transport = new StreamableHTTPServerTransport({
      sessionIdGenerator: undefined
    });

    await server.connect(transport);
    await transport.handleRequest(req, res, req.body);

    res.on('close', () => {
      transport.close();
      server.close();
    });
  } catch (error) {
    console.error('Error handling MCP request:', error);
    if (!res.headersSent) {
      res.status(500).json({
        jsonrpc: '2.0',
        error: { code: -32603, message: 'Internal server error' },
        id: null
      });
    }
  }
});

app.get('/healthz', (_req: Request, res: Response) => {
  res.status(200).json({ ok: true });
});

const port = Number(process.env.PORT ?? 8081);
app.listen(port, () => {
  console.log(`Roadmap MCP server listening on http://localhost:${port}/mcp`);
});
