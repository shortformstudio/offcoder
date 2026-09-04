import { spawn } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const entry = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'index.js');
const child = spawn(process.execPath, [entry], { stdio: ['pipe', 'pipe', 'pipe'] });

child.stderr.on('data', (d) => process.stderr.write(`[server] ${d}`));

let buf = '';
const pending = new Map();

child.stdout.on('data', (chunk) => {
  buf += chunk.toString();
  let idx;
  while ((idx = buf.indexOf('\n')) >= 0) {
    const line = buf.slice(0, idx).trim();
    buf = buf.slice(idx + 1);
    if (!line) continue;
    let msg;
    try {
      msg = JSON.parse(line);
    } catch {
      continue;
    }
    if (msg.id != null && pending.has(msg.id)) {
      pending.get(msg.id)(msg);
      pending.delete(msg.id);
    }
  }
});

function rpc(method, params, id) {
  return new Promise((resolve) => {
    pending.set(id, resolve);
    child.stdin.write(JSON.stringify({ jsonrpc: '2.0', id, method, ...(params ? { params } : {}) }) + '\n');
  });
}

const fail = (why) => {
  console.error('SMOKE FAIL:', why);
  child.kill('SIGTERM');
  process.exit(1);
};

const init = await rpc('initialize', { protocolVersion: '2025-06-18', capabilities: {}, clientInfo: { name: 'smoke', version: '0.0.0' } }, 1);
if (!init.result?.serverInfo) fail('initialize returned no serverInfo');
console.log('server:', init.result.serverInfo.name, init.result.serverInfo.version);

child.stdin.write(JSON.stringify({ jsonrpc: '2.0', method: 'notifications/initialized' }) + '\n');

const tools = await rpc('tools/list', {}, 2);
const names = (tools.result?.tools ?? []).map((t) => t.name);
console.log('tools:', names.join(', '));

const expected = ['consult_gemini', 'consult_deepseek', 'consult_kimi', 'consult_check', 'consult_list', 'consult_prompts', 'consult_reset'];
const missing = expected.filter((n) => !names.includes(n));
if (missing.length) fail(`missing tools: ${missing.join(', ')}`);

const prompts = await rpc('tools/call', { name: 'consult_prompts', arguments: {} }, 3);
const promptsText = prompts.result?.content?.[0]?.text ?? '';
if (!promptsText.includes('code_audit_deep') || !promptsText.includes('verify_findings')) fail('prompt catalog incomplete');
console.log('prompt catalog ok:', JSON.parse(promptsText).count, 'templates');

const one = await rpc('tools/call', { name: 'consult_prompts', arguments: { template_id: 'code_audit_deep' } }, 4);
const oneObj = JSON.parse(one.result?.content?.[0]?.text ?? '{}');
if (!oneObj.text?.includes('{{CODE}}')) fail('template fetch missing body text');
console.log('template fetch ok:', oneObj.id);

const list = await rpc('tools/call', { name: 'consult_list', arguments: {} }, 5);
const listObj = JSON.parse(list.result?.content?.[0]?.text ?? '{}');
if (typeof listObj.budget?.consults_remaining !== 'number') fail('consult_list missing budget');
console.log('list ok:', listObj.conversations.length, 'conversations | budget:', listObj.budget.consults_remaining, 'remaining');

const badPrompt = await rpc('tools/call', { name: 'consult_gemini', arguments: { prompt: '' } }, 6);
const badObj = JSON.parse(badPrompt.result?.content?.[0]?.text ?? '{}');
if (badObj.ok !== false || !/(at least|non-empty|required)/i.test(badObj.error ?? '')) fail('empty prompt validation leaky:', badObj.error);
console.log('validation ok:', badObj.error);

console.log('\nSMOKE PASS');
child.kill('SIGTERM');
process.exit(0);
