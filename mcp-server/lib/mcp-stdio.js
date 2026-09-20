// Minimal MCP stdio server kernel — zero dependencies, JSON-RPC 2.0.
// Implements initialize, tools/list, tools/call, and notifications.

import readline from 'node:readline';

export const PROTOCOL_VERSION = '2024-11-05';

export function textResult(text) {
  return { content: [{ type: 'text', text: typeof text === 'string' ? text : JSON.stringify(text, null, 2) }] };
}

export function errorResult(text) {
  return { content: [{ type: 'text', text: String(text) }], isError: true };
}

export function serve({ name, version = '1.0.0', tools, handlers }) {
  const rl = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
  const write = (message) => process.stdout.write(JSON.stringify(message) + '\n');

  rl.on('line', async (line) => {
    const trimmed = line.trim();
    if (!trimmed) return;
    let request;
    try {
      request = JSON.parse(trimmed);
    } catch {
      return;
    }
    if (request.id === undefined || request.id === null) return;

    const reply = (result) => write({ jsonrpc: '2.0', id: request.id, result });
    const fail = (code, message) => write({ jsonrpc: '2.0', id: request.id, error: { code, message } });

    try {
      switch (request.method) {
        case 'initialize':
          reply({
            protocolVersion: PROTOCOL_VERSION,
            capabilities: { tools: {} },
            serverInfo: { name, version },
          });
          break;
        case 'ping':
          reply({});
          break;
        case 'tools/list':
          reply({ tools });
          break;
        case 'tools/call': {
          const toolName = request.params?.name;
          const args = request.params?.arguments ?? {};
          const handler = handlers[toolName];
          if (!handler) {
            fail(-32601, `unknown tool: ${toolName}`);
            break;
          }
          const result = await handler(args);
          reply(result);
          break;
        }
        default:
          fail(-32601, `method not found: ${request.method}`);
      }
    } catch (error) {
      fail(-32603, error?.message ?? String(error));
    }
  });

  // On stdin close, let in-flight handlers finish; node exits when the loop drains.
  rl.on('close', () => {});
  process.stderr.write(`[${name}] mcp server listening on stdio\n`);
}
