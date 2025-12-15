import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { createMcpExpressApp } from '@modelcontextprotocol/sdk/server/express.js';
import { StreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/streamableHttp.js';
import { getRoadmapInputSchema } from './generated/roadmapInputSchema.js';
const ROADMAP_BASE_URL = 'https://www.microsoft.com/releasecommunications/api/v2';
function toTextResult(value) {
    return {
        content: [
            {
                type: 'text',
                text: JSON.stringify(value, null, 2)
            }
        ]
    };
}
async function fetchJson(url, init) {
    const response = await fetch(url, init);
    const text = await response.text();
    let parsed = text;
    try {
        parsed = text ? JSON.parse(text) : null;
    }
    catch {
        parsed = text;
    }
    return {
        ok: response.ok,
        status: response.status,
        statusText: response.statusText,
        data: parsed
    };
}
function buildUrl(baseUrl, requestPath, query) {
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
    const server = new McpServer({ name: 'roadmap-mcp-server', version: '0.1.0' }, { capabilities: { logging: {} } });
    server.registerTool('getRoadmapInfo', {
        description: 'Retrieve Microsoft 365 Roadmap items from https://www.microsoft.com/releasecommunications/api/v2/m365 using OData query parameters.',
        inputSchema: getRoadmapInputSchema
    }, async (args) => {
        const url = buildUrl(ROADMAP_BASE_URL, '/m365', {
            $filter: args.filter,
            $orderby: args.orderby,
            $top: args.top !== undefined ? String(args.top) : undefined,
            $skip: args.skip !== undefined ? String(args.skip) : undefined,
            $count: String(args.count)
        });
        const result = await fetchJson(url, {
            headers: {
                Accept: 'application/json'
            }
        });
        return toTextResult({ request: { url }, response: result });
    });
    return server;
}
const app = createMcpExpressApp();
app.post('/mcp', async (req, res) => {
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
    }
    catch (error) {
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
app.get('/healthz', (_req, res) => {
    res.status(200).json({ ok: true });
});
const port = Number(process.env.PORT ?? 8081);
app.listen(port, () => {
    console.log(`Roadmap MCP server listening on http://localhost:${port}/mcp`);
});
//# sourceMappingURL=server.js.map