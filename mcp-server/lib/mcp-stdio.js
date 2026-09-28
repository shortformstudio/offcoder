// Minimal MCP stdio server kernel — zero dependencies, JSON-RPC 2.0.
// Implements initialize, tools/list, tools/call, and notifications with
// hardened input validation and actionable error boundaries for LLMs.

import readline from 'node:readline';

export const PROTOCOL_VERSION = '2024-11-05';

export function textResult(text) {
  return {
    content: [{ type: 'text', text: typeof text === 'string' ? text : JSON.stringify(text, null, 2) }],
  };
}

export function errorResult(err, toolName = '') {
  let payload;
  if (typeof err === 'object' && err !== null) {
    payload = {
      ok: false,
      isError: true,
      error: {
        code: err.code || 'TOOL_EXECUTION_ERROR',
        message: err.message || String(err),
        remediation: err.remediation || 'Inspect the tool inputSchema and provide valid parameters.',
        details: err.details ?? undefined,
      },
    };
  } else {
    payload = {
      ok: false,
      isError: true,
      error: {
        code: 'TOOL_ERROR',
        message: String(err),
        remediation: 'Check arguments against inputSchema requirements.',
      },
    };
  }
  return {
    content: [{ type: 'text', text: JSON.stringify(payload, null, 2) }],
    isError: true,
  };
}

function validateToolInput(toolDef, args) {
  if (!toolDef || !toolDef.inputSchema) return null;
  const schema = toolDef.inputSchema;

  if (schema.type === 'object' && (typeof args !== 'object' || args === null || Array.isArray(args))) {
    return {
      code: 'INVALID_ARGUMENT_TYPE',
      message: `Expected arguments object, received ${Array.isArray(args) ? 'array' : typeof args}`,
      remediation: `Pass arguments as a JSON key-value object conforming to ${toolDef.name} inputSchema.`,
    };
  }

  if (Array.isArray(schema.required)) {
    for (const requiredKey of schema.required) {
      if (args[requiredKey] === undefined || args[requiredKey] === null || args[requiredKey] === '') {
        return {
          code: 'MISSING_REQUIRED_ARG',
          message: `Missing required argument: "${requiredKey}"`,
          remediation: `Tool "${toolDef.name}" requires [${schema.required.join(', ')}]. Provide non-empty "${requiredKey}".`,
        };
      }
    }
  }

  if (schema.properties) {
    for (const [key, prop] of Object.entries(schema.properties)) {
      const val = args[key];
      if (val === undefined || val === null) continue;

      if (prop.type === 'string' && typeof val !== 'string') {
        return {
          code: 'TYPE_MISMATCH',
          message: `Property "${key}" must be a string, got ${typeof val}`,
          remediation: `Format "${key}" as a string.`,
        };
      }
      if (prop.type === 'integer' && (!Number.isInteger(val) || (typeof val !== 'number'))) {
        return {
          code: 'TYPE_MISMATCH',
          message: `Property "${key}" must be an integer, got ${typeof val}`,
          remediation: `Provide an integer value for "${key}".`,
        };
      }
      if (prop.minimum !== undefined && typeof val === 'number' && val < prop.minimum) {
        return {
          code: 'VALUE_OUT_OF_RANGE',
          message: `Property "${key}" value ${val} is less than minimum ${prop.minimum}`,
          remediation: `Increase "${key}" to at least ${prop.minimum}.`,
        };
      }
      if (prop.maximum !== undefined && typeof val === 'number' && val > prop.maximum) {
        return {
          code: 'VALUE_OUT_OF_RANGE',
          message: `Property "${key}" value ${val} exceeds maximum ${prop.maximum}`,
          remediation: `Reduce "${key}" to at most ${prop.maximum}.`,
        };
      }
    }
  }

  return null;
}

export function serve({ name, version = '1.0.0', tools, handlers }) {
  const rl = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
  const write = (message) => process.stdout.write(JSON.stringify(message) + '\n');
  const toolMap = new Map((tools || []).map((t) => [t.name, t]));

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
            reply(errorResult({
              code: 'UNKNOWN_TOOL',
              message: `Unknown tool: ${toolName}`,
              remediation: `Available tools: [${[...toolMap.keys()].join(', ')}]`,
            }));
            break;
          }

          const toolDef = toolMap.get(toolName);
          const validationError = validateToolInput(toolDef, args);
          if (validationError) {
            reply(errorResult(validationError, toolName));
            break;
          }

          try {
            const result = await handler(args);
            reply(result);
          } catch (handlerErr) {
            reply(errorResult({
              code: 'TOOL_EXECUTION_FAILURE',
              message: handlerErr?.message ?? String(handlerErr),
              remediation: 'Verify underlying resources, network connectivity, or arguments and retry.',
            }, toolName));
          }
          break;
        }
        default:
          fail(-32601, `method not found: ${request.method}`);
      }
    } catch (error) {
      fail(-32603, error?.message ?? String(error));
    }
  });

  rl.on('close', () => {});
  process.stderr.write(`[${name}] mcp server listening on stdio (hardened)\n`);
}
