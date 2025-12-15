import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StreamableHTTPClientTransport } from '@modelcontextprotocol/sdk/client/streamableHttp.js';

async function main() {
  const baseUrl = process.env.MCP_URL ?? 'http://localhost:8080/mcp';

  const client = new Client({ name: 'smoke-client', version: '0.1.0' });
  const transport = new StreamableHTTPClientTransport(new URL(baseUrl));

  await client.connect(transport);

  const tools = await client.listTools();
  console.log('Tools:', tools.tools.map(t => t.name));

  await client.close();
}

main().catch(err => {
  console.error(err);
  process.exitCode = 1;
});
