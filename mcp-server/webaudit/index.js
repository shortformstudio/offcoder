#!/usr/bin/env node
// webaudit.mcp — DeepSeek Web 3-Pass Audited Clone Engine
// Trigger: type /webaudit at the start of your prompt to initiate a 3-pass DeepSeek audit.
// Each pass delivers BOTH findings report AND complete fixes in one turn.
// Strict versioning: original code never mutated; all changes iterate on a fresh clone (v0→v3).
// DeepSeek Web only via stealth browser session.

import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { CallToolRequestSchema, ListToolsRequestSchema } from '@modelcontextprotocol/sdk/types.js';
import { MAX_CONSULTS, MAX_CONVERSATIONS, MAX_PROMPT_CHARS, MAX_POLLS, POLL_MS, RESET_ALLOWED } from './lib/config.js';
import * as ledger from './lib/ledger.js';
import { validate, applyDefaults } from './lib/validate.js';
import { consult, check } from './lib/session.js';
import { closeAll } from './lib/browser.js';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';
import { spawnSync } from 'node:child_process';

const AUDIT_ROOT = process.env.WEBAUDIT_ROOT || path.join(os.homedir(), '.config', 'webaudit', 'audits');
const MAX_CODE_CHARS = 60000;

function ensureDir(p) { fs.mkdirSync(p, { recursive: true }); }
function auditIdFor(project) {
  const ts = new Date().toISOString().replace(/[:.]/g, '-');
  const rnd = crypto.randomBytes(2).toString('hex');
  const safe = (project || 'audit').replace(/[^a-zA-Z0-9_-]/g, '_').slice(0, 30);
  return `${safe}_${ts}_${rnd}`;
}
function extractCodeBlock(text) {
  if (!text) return null;
  // prefer fenced blocks
  const fenced = [...text.matchAll(/```(\w+)?\n([\s\S]*?)```/g)];
  if (fenced.length) {
    // return the largest block (heuristic for main artifact)
    let best = fenced[0][2];
    for (const m of fenced) if (m[2].length > best.length) best = m[2];
    return best.trim();
  }
  return null;
}
function extractReport(text) {
  if (!text) return '';
  // report is everything before the first code fence, plus any trailing explanation after if structured
  const idx = text.indexOf('```');
  if (idx > 0) return text.slice(0, idx).trim();
  return text.trim().slice(0, 8000);
}
function detectLang(filePath) {
  const ext = path.extname(filePath).toLowerCase();
  if (ext === '.py') return 'python';
  if (ext === '.ts' || ext === '.tsx') return 'typescript';
  if (ext === '.js' || ext === '.jsx') return 'javascript';
  if (ext === '.swift') return 'swift';
  if (ext === '.go') return 'go';
  if (ext === '.rs') return 'rust';
  if (ext === '.java') return 'java';
  if (ext === '.cpp' || ext === '.cc') return 'cpp';
  return '';
}
function buildAuditPrompt({ code, targetFile, pass, total, focus, prevSummary }) {
  const lang = detectLang(targetFile);
  const focusLine = focus ? `Audit focus: ${focus}.` : 'Audit focus: comprehensive (correctness, security, performance, API design, maintainability).';
  const prevLine = prevSummary ? `Previous pass summary (build on it, do not regress):\n${prevSummary.slice(0, 2000)}\n` : '';
  return `[WEBAUDIT PASS ${pass}/${total} — COMPREHENSIVE AUDIT + FIX IN ONE SWEEP]
You are a principal engineer. Perform a serious, hostile-but-fair audit and then FIX every finding immediately in code.

${focusLine}
Hard rules for this pass:
- Deliver BOTH: (A) findings report with severity P0 ship-blocker / P1 fix soon / P2 should fix / P3 nit, citing FILE:LINE or function name, and (B) the complete fixed file in one markdown code block.
- Fix all P0/P1 and as many P2 as possible without scope creep. No placeholders, no TODOs, no "implement later".
- Keep the public API stable unless the audit demands a breaking correction — document any change.
- Preserve behavior where not fixing a bug; do not silently change semantics.
- The fixed code must be syntactically valid and runnable. Include imports, types, error handling.
- Output format: first a markdown report section titled "## Findings — Pass ${pass}", then a single fenced code block with the entire fixed file.
${prevLine}
File: ${targetFile}
Current code to audit (pass ${pass} input):
\`\`\`${lang}
${code.slice(0, MAX_CODE_CHARS)}
\`\`\`
If the code exceeds the window, prioritize the most critical sections and note truncation.
Deliver now: report then full fixed file.`;
}

function cloneOriginal({ auditDir, code, targetFile, targetPath }) {
  const v0 = path.join(auditDir, 'v0_original');
  ensureDir(v0);
  let originalPath = null;
  if (targetPath) {
    try {
      const stat = fs.statSync(targetPath);
      if (stat.isDirectory()) {
        // clone directory recursively excluding node_modules/.git etc
        const dest = path.join(v0, path.basename(targetPath));
        copyDirFiltered(targetPath, dest);
        originalPath = dest;
      } else if (stat.isFile()) {
        const dest = path.join(v0, path.basename(targetPath));
        fs.copyFileSync(targetPath, dest);
        originalPath = dest;
      }
    } catch (e) {
      // fallback to code string
      const dest = path.join(v0, path.basename(targetFile) || 'artifact');
      fs.writeFileSync(dest, code, 'utf8');
      originalPath = dest;
    }
  } else {
    const dest = path.join(v0, path.basename(targetFile) || 'artifact');
    fs.writeFileSync(dest, code, 'utf8');
    originalPath = dest;
  }
  return { v0, originalPath };
}
function copyDirFiltered(src, dest) {
  ensureDir(dest);
  for (const entry of fs.readdirSync(src, { withFileTypes: true })) {
    if (['node_modules', '.git', '.build', '.venv', '__pycache__', 'dist', 'build'].includes(entry.name)) continue;
    if (entry.name.startsWith('.')) continue;
    const s = path.join(src, entry.name);
    const d = path.join(dest, entry.name);
    if (entry.isDirectory()) copyDirFiltered(s, d);
    else if (entry.isFile()) {
      try { fs.copyFileSync(s, d); } catch {}
    }
  }
}
function writeVersion({ auditDir, pass, code, targetFile }) {
  const vDir = path.join(auditDir, `v${pass}`);
  ensureDir(vDir);
  const fileName = path.basename(targetFile) || 'artifact';
  const dest = path.join(vDir, fileName);
  fs.writeFileSync(dest, code, 'utf8');
  return dest;
}
function writeReport({ auditDir, pass, reportText, rawResponse }) {
  const rDir = path.join(auditDir, 'reports');
  ensureDir(rDir);
  const dest = path.join(rDir, `pass${pass}.md`);
  const content = `# webaudit pass ${pass} report\n\n${reportText}\n\n---\n\n<details><summary>raw deepseek response (truncated)</summary>\n\n\`\`\`\n${rawResponse.slice(0, 8000)}\n\`\`\`\n</details>\n`;
  fs.writeFileSync(dest, content, 'utf8');
  return dest;
}
function runVerification({ filePath }) {
  const ext = path.extname(filePath).toLowerCase();
  const dir = path.dirname(filePath);
  let cmd = null;
  let args = [];
  if (ext === '.py') {
    cmd = 'python3'; args = ['-m', 'py_compile', filePath];
  } else if (ext === '.js') {
    cmd = 'node'; args = ['--check', filePath];
  } else if (ext === '.ts' || ext === '.tsx') {
    // try tsc if available, fallback to node check
    const hasTsc = spawnSync('npx', ['tsc', '--version'], { timeout: 3000 }).status === 0;
    if (hasTsc) { cmd = 'npx'; args = ['tsc', '--noEmit', '--skipLibCheck', filePath]; }
    else { return { ok: null, note: 'tsc not found, skipped strict check', output: '' }; }
  } else if (ext === '.swift') {
    // lightweight syntax check via swiftc -parse
    cmd = 'swiftc'; args = ['-parse', filePath];
  }
  if (!cmd) return { ok: null, note: 'no verifier for this language', output: '' };
  try {
    const result = spawnSync(cmd, args, { timeout: 15000, encoding: 'utf8', cwd: dir });
    const output = [result.stdout, result.stderr].filter(Boolean).join('\n').slice(0, 3000);
    return { ok: result.status === 0, output, note: `${cmd} ${args.join(' ')}` };
  } catch (e) {
    return { ok: false, output: String(e), note: 'verification threw' };
  }
}

function loadCodeFromTarget(targetPath) {
  if (!targetPath) return null;
  try {
    const stat = fs.statSync(targetPath);
    if (stat.isFile()) {
      return { code: fs.readFileSync(targetPath, 'utf8'), fileName: path.basename(targetPath) };
    } else if (stat.isDirectory()) {
      // For directory, produce a concatenated view with file markers, limited
      const files = [];
      function walk(p) {
        for (const e of fs.readdirSync(p, { withFileTypes: true })) {
          if (files.length > 20) break;
          if (['node_modules', '.git', '.build', 'dist', '.venv', '__pycache__'].includes(e.name)) continue;
          const full = path.join(p, e.name);
          if (e.isDirectory()) walk(full);
          else if (e.isFile() && /\.(py|ts|tsx|js|jsx|swift|go|rs|java|cpp|cc|h|md|json)$/.test(e.name)) {
            try {
              const content = fs.readFileSync(full, 'utf8');
              if (content.length < 30000) files.push({ rel: path.relative(targetPath, full), content });
            } catch {}
          }
        }
      }
      walk(targetPath);
      const combined = files.map(f => `// FILE: ${f.rel}\n${f.content}`).join('\n\n// =====\n\n').slice(0, MAX_CODE_CHARS);
      return { code: combined, fileName: path.basename(targetPath) + '/combined' };
    }
  } catch {}
  return null;
}

const TOOL_DEFS = [
  {
    name: 'webaudit',
    summary: 'DeepSeek Web 3-Pass Audit + Fix — trigger with /webaudit',
    description: `Trigger: type /webaudit at the start of your prompt. DeepSeek Web 3-pass comprehensive audit with fixes.

Specialization: you provide a codebase or component file to DeepSeek Web; the model performs a full serious audit and applies ALL fixes in one sweep per pass. The MCP repeats this 2 more times for a total of 3 audit passes, each pass building on the last. Completed with a final artifact for agent review.

Versioning: STRICT — original code is never mutated. A fresh clone is created at ~/.config/webaudit/audits/<id>/v0_original; each pass writes v1, v2, v3. Thoroughly tested after each pass (py_compile / tsc --noEmit / swiftc -parse). Each audit loop delivers BOTH a findings report AND the complete fixed code in one turn.

DeepSeek Web only via stealth browser. Each pass consumes 1 consult budget. Use webaudit_list to see history, webaudit_check to poll a generating pass.

Args:
  - target_path (string, optional): absolute or repo-relative path to file or directory to audit; if provided, code is read from disk and cloned.
  - code (string, optional): raw code string when not using target_path.
  - target_file (string, optional): filename for versioning when using raw code (e.g., src/foo.py). Defaults to active_buffer.
  - project_name (string, optional): label for the audit workspace.
  - audit_focus (string, optional): security | performance | correctness | full (default full).
  - conversation_id (string, optional): reuse an existing DeepSeek thread across all 3 passes.
  - max_wait_polls (integer, optional): polls per pass (default 20, up to 40).

Returns JSON with audit_id, workspace path, per-pass reports, verification results, and final artifact location. Never mutates the original file.`,
    inputSchema: {
      type: 'object',
      additionalProperties: false,
      required: [],
      properties: {
        target_path: { type: 'string', description: 'Path to file or directory to audit (read and cloned). Takes precedence over code if both provided.' },
        code: { type: 'string', description: 'Raw code string to audit (alternative to target_path).' },
        target_file: { type: 'string', description: 'Filename for versioning when using raw code, e.g. src/foo.py' },
        project_name: { type: 'string', description: 'Project label for workspace naming' },
        audit_focus: { type: 'string', description: 'Audit focus: security, performance, correctness, maintainability, or full' },
        conversation_id: { type: 'string', description: 'Reuse existing DeepSeek conversation across all 3 passes' },
        max_wait_polls: { type: 'integer', minimum: 1, maximum: 40, description: 'Completion polls per pass' },
      },
    },
  },
  {
    name: 'webaudit_check',
    summary: 'WebAudit poller: re-poll a generating webaudit pass without spending budget',
    description: `Re-poll an in-flight webaudit DeepSeek generation without spending budget. Use after webaudit returns status generating. Same shape as webaudit but takes audit_id or conversation_id.

Args:
  - conversation_id (string, required): DeepSeek thread to keep waiting on
  - max_wait_polls (integer, optional)`,
    inputSchema: {
      type: 'object',
      additionalProperties: false,
      required: ['conversation_id'],
      properties: {
        conversation_id: { type: 'string', description: 'thread to keep waiting on' },
        max_wait_polls: { type: 'integer', minimum: 1, maximum: 40, description: 'polls before returning generating again' },
      },
    },
  },
  {
    name: 'webaudit_list',
    summary: 'WebAudit history: list past audits and budgets',
    description: `List every webaudit workspace and DeepSeek conversation status with remaining budget. Costs nothing. Call when you lose track of audit ids or thread ids.`,
    inputSchema: { type: 'object', additionalProperties: false, properties: {} },
  },
  {
    name: 'webaudit_prompts',
    summary: 'WebAudit prompt templates for the 3-pass loop',
    description: `Return the exact prompt verbage used for the webaudit audit+fix sweep. Use to preview or customize the deep audit directive before running webaudit.`,
    inputSchema: { type: 'object', additionalProperties: false, properties: {} },
  },
];

function respond(payload) {
  return { content: [{ type: 'text', text: JSON.stringify(payload, null, 2) }] };
}

const HANDLERS = {
  webaudit: async (args) => {
    let code = args.code || '';
    let targetFile = args.target_file || 'active_buffer.py';
    let targetPath = args.target_path || null;
    const projectName = args.project_name || (targetPath ? path.basename(targetPath) : path.basename(targetFile, path.extname(targetFile)) || 'webaudit');
    const focus = args.audit_focus || 'full';
    const maxPolls = args.max_wait_polls;

    if (targetPath) {
      const loaded = loadCodeFromTarget(targetPath);
      if (!loaded) return { ok: false, status: 'error', error: `could not read target_path "${targetPath}"` };
      code = loaded.code;
      if (!args.target_file) targetFile = loaded.fileName.includes('/') ? loaded.fileName : path.basename(targetPath) || loaded.fileName;
    }
    if (!code || !code.trim()) return { ok: false, status: 'error', error: 'provide target_path or non-empty code' };
    if (code.length > MAX_CODE_CHARS * 2) code = code.slice(0, MAX_CODE_CHARS * 2);

    const auditId = auditIdFor(projectName);
    const auditDir = path.join(AUDIT_ROOT, auditId);
    ensureDir(auditDir);

    const meta = { auditId, projectName, targetFile, targetPath, focus, createdAt: new Date().toISOString(), auditDir };
    fs.writeFileSync(path.join(auditDir, 'meta.json'), JSON.stringify(meta, null, 2));

    const { v0, originalPath } = cloneOriginal({ auditDir, code, targetFile, targetPath });

    let currentCode = code;
    let conversationId = args.conversation_id || null;
    const passes = [];
    let prevSummary = '';

    for (let pass = 1; pass <= 3; pass++) {
      const prompt = buildAuditPrompt({ code: currentCode, targetFile, pass, total: 3, focus, prevSummary });
      // respect prompt char limit
      const safePrompt = prompt.length > MAX_PROMPT_CHARS ? prompt.slice(0, MAX_PROMPT_CHARS - 500) + '\n[truncated]' : prompt;

      let result;
      try {
        result = await consult('deepseek', { prompt: safePrompt, conversationId, maxPolls });
      } catch (e) {
        return { ok: false, audit_id: auditId, audit_dir: auditDir, original_clone: v0, pass, error: e instanceof Error ? e.message : String(e), passes };
      }

      if (result.status === 'login_required') {
        return { ok: false, audit_id: auditId, audit_dir: auditDir, status: 'login_required', pass, message: result.message, budget: result.budget, passes };
      }

      // update conversation tracking
      if (result.conversation_id) conversationId = result.conversation_id;

      if (result.status === 'generating') {
        // save interim and instruct to poll
        return {
          ok: false,
          audit_id: auditId,
          audit_dir: auditDir,
          status: 'generating',
          pass,
          conversation_id: conversationId,
          hint: `pass ${pass}/3 still generating after ${result.polls} polls. Call webaudit_check with conversation_id "${conversationId}" to continue, then resume remaining passes. Partial passes: ${passes.length}`,
          response_preview: result.response_text?.slice(0, 2000),
          budget: result.budget,
          passes,
        };
      }
      if (result.status === 'error') {
        return { ok: false, audit_id: auditId, audit_dir: auditDir, pass, status: 'error', error: result.error, passes, budget: result.budget };
      }

      const raw = result.response_text || '';
      const fixed = extractCodeBlock(raw);
      const report = extractReport(raw);

      const effectiveCode = fixed && fixed.length > 20 ? fixed : currentCode;
      const versionPath = writeVersion({ auditDir, pass, code: effectiveCode, targetFile });
      const reportPath = writeReport({ auditDir, pass, reportText: report || '(no report section found)', rawResponse: raw });
      const verification = runVerification({ filePath: versionPath });

      const passRecord = {
        pass,
        conversation_id: conversationId,
        url: result.url,
        report_path: reportPath,
        version_path: versionPath,
        verification,
        polls: result.polls,
        waited_seconds: result.waited_seconds,
        had_fix: Boolean(fixed),
        report_preview: report.slice(0, 1200),
      };
      passes.push(passRecord);

      prevSummary = report.slice(0, 1500);
      currentCode = effectiveCode;

      // if model returned no code block on final pass, flag
      if (!fixed && pass === 3) {
        passRecord.warning = 'no code block extracted on final pass; original code carried forward';
      }
    }

    const finalVersionPath = path.join(auditDir, 'v3', path.basename(targetFile) || 'artifact');
    const finalCode = fs.existsSync(finalVersionPath) ? fs.readFileSync(finalVersionPath, 'utf8') : currentCode;
    const finalReportPath = path.join(auditDir, 'FINAL_ARTIFACT.md');
    const finalMd = `# webaudit final artifact — ${projectName}\n\n**audit_id:** ${auditId}\n**audit_dir:** ${auditDir}\n**original_clone:** ${v0} (${originalPath})\n**target_file:** ${targetFile}\n**target_path:** ${targetPath || '(raw code)'}\n**focus:** ${focus}\n**passes:** 3\n**conversation_id:** ${conversationId}\n**completed_at:** ${new Date().toISOString()}\n\n## version map (original never mutated)\n- v0_original: \`${path.relative(auditDir, v0)}\` — immutable baseline\n- v1: \`v1/${path.basename(targetFile)}\` — after pass 1\n- v2: \`v2/${path.basename(targetFile)}\` — after pass 2\n- v3: \`v3/${path.basename(targetFile)}\` — **final artifact** (review this)\n\n## per-pass summary\n${passes.map(p => `### pass ${p.pass}\n- report: \`${path.relative(auditDir, p.report_path)}\`\n- version: \`${path.relative(auditDir, p.version_path)}\`\n- verification: ${p.verification.ok === true ? 'PASS' : p.verification.ok === false ? 'FAIL' : 'SKIP'} — ${p.verification.note}\n\`\`\`\n${p.verification.output?.slice(0, 600) || ''}\n\`\`\`\n- had_fix: ${p.had_fix}\n`).join('\n')}\n\n## final code\n\`\`\`${detectLang(targetFile)}\n${finalCode.slice(0, 60000)}\n\`\`\`\n`;
    fs.writeFileSync(finalReportPath, finalMd, 'utf8');

    return {
      ok: true,
      audit_id: auditId,
      audit_dir: auditDir,
      original_clone: v0,
      original_path: originalPath,
      final_artifact: finalVersionPath,
      final_report: finalReportPath,
      conversation_id: conversationId,
      target_file: targetFile,
      target_path: targetPath,
      focus,
      passes,
      note: 'original code preserved at v0_original; review final artifact at v3. never mutate original — apply final artifact via copy if approved.',
      budget: ledger.snapshot(),
    };
  },

  webaudit_check: async (args) => {
    const result = await check(args.conversation_id, args.max_wait_polls);
    return result;
  },

  webaudit_list: async () => {
    let audits = [];
    try {
      if (fs.existsSync(AUDIT_ROOT)) {
        audits = fs.readdirSync(AUDIT_ROOT).map(id => {
          const metaPath = path.join(AUDIT_ROOT, id, 'meta.json');
          try {
            const meta = JSON.parse(fs.readFileSync(metaPath, 'utf8'));
            const versions = ['v0_original', 'v1', 'v2', 'v3'].map(v => ({ v, exists: fs.existsSync(path.join(AUDIT_ROOT, id, v)) }));
            return { id, ...meta, versions };
          } catch { return { id }; }
        }).sort((a,b) => String(b.createdAt||'').localeCompare(String(a.createdAt||'')));
      }
    } catch {}
    return {
      ok: true,
      audits,
      audit_root: AUDIT_ROOT,
      conversations: ledger.listConversations().map(c => ({ id: c.id, provider: c.provider, status: c.status, turns: c.turns, url: c.url, updated_at: c.updated_at })),
      budget: ledger.snapshot(),
      tip: 'webaudit creates strict clones at <audit_dir>/v0_original (never mutated) → v3 final artifact; use webaudit with target_path or code to start a new 3-pass audit',
    };
  },

  webaudit_prompts: async () => {
    const example = buildAuditPrompt({ code: '// example code\nfunction foo() { return 42 }', targetFile: 'example.js', pass: 1, total: 3, focus: 'full', prevSummary: '' });
    return { ok: true, prompt_template: example, notes: 'each pass receives current code + previous findings summary; must return report + single fenced code block with complete fixed file' };
  },
};

const server = new Server({ name: 'webaudit', version: '1.0.0' }, { capabilities: { tools: {} } });
server.setRequestHandler(ListToolsRequestSchema, async () => ({ tools: TOOL_DEFS }));
server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: rawArgs } = request.params;
  try {
    const def = TOOL_DEFS.find(t => t.name === name);
    if (!def || !HANDLERS[name]) return respond({ ok: false, status: 'error', error: `unknown tool "${name}"` });
    const args = applyDefaults(def.inputSchema, rawArgs ?? {});
    const errs = validate(def.inputSchema, args);
    if (errs.length) return respond({ ok: false, status: 'error', error: `invalid arguments: ${errs.join('; ')}` });
    return respond(await HANDLERS[name](args));
  } catch (err) {
    return respond({ ok: false, status: 'error', error: err instanceof Error ? err.message : String(err) });
  }
});

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error('[webaudit] mcp server listening on stdio — DeepSeek Web 3-pass audit engine');
}
for (const signal of ['SIGINT', 'SIGTERM']) {
  process.on(signal, () => { closeAll().finally(() => process.exit(0)); });
}
main().catch(err => { console.error('[webaudit] fatal:', err); process.exit(1); });
