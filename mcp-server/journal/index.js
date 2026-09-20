#!/usr/bin/env node
// journal.mcp — autonomous designed PDF artifacts.
// Tools: journal_create (markdown -> designed folio), journal_visual (generative plate),
//        journal_list, journal_open.
// Rendering: scripts/journal_render.py (reportlab, vector, Avenir + Menlo from system TTCs).

import { existsSync, mkdirSync, readdirSync, statSync, writeFileSync, rmSync } from 'node:fs';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { homedir, tmpdir } from 'node:os';
import path from 'node:path';
import { serve, textResult, errorResult } from '../lib/mcp-stdio.js';

const execFileAsync = promisify(execFile);

const OFFCODER_HOME = path.join(homedir(), '.offcoder');
const DEFAULT_JOURNAL_DIR = path.join(OFFCODER_HOME, 'journal');
const WORKSPACES = path.join(homedir(), 'code', 'qwythos-agent', 'projects');
const REPO_ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..', '..');
const RENDERER = path.join(REPO_ROOT, 'scripts', 'journal_render.py');

function resolveOutDir(args) {
  if (args.out_dir) return args.out_dir;
  if (args.project) return path.join(WORKSPACES, args.project, 'journal');
  return DEFAULT_JOURNAL_DIR;
}

function slugify(text) {
  return String(text).toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 60) || 'journal';
}

async function render(spec) {
  const specPath = path.join(tmpdir(), `offcoder-journal-${process.pid}-${Date.now()}.json`);
  writeFileSync(specPath, JSON.stringify(spec), 'utf-8');
  try {
    const { stdout, stderr } = await execFileAsync('/usr/bin/python3', [RENDERER, '--spec', specPath], { timeout: 120000 });
    if (stderr && stderr.trim()) process.stderr.write(stderr);
    const line = stdout.trim().split('\n').pop();
    return JSON.parse(line);
  } finally {
    rmSync(specPath, { force: true });
  }
}

const tools = [
  {
    name: 'journal_create',
    description: 'Render a designed PDF folio from markdown. The layout is autonomous: cover, alchemy gradient bar, seeded ornament plate, typographic hierarchy, vector type. Returns the pdf path.',
    inputSchema: {
      type: 'object', additionalProperties: false, required: ['title', 'content'],
      properties: {
        title: { type: 'string', description: 'folio title (rendered lowercase, ultra light)' },
        content: { type: 'string', description: 'markdown body: headings, lists, code fences, quotes, links' },
        subtitle: { type: 'string' },
        project: { type: 'string', description: 'workspace project name; writes to <project>/journal/' },
        out_dir: { type: 'string', description: 'explicit output directory' },
      },
    },
  },
  {
    name: 'journal_visual',
    description: 'Generate a visual experiment: a seeded sacred-geometry plate rendered as a designed PDF. Deterministic from the seed; same seed reproduces the same plate.',
    inputSchema: {
      type: 'object', additionalProperties: false, required: ['title'],
      properties: {
        title: { type: 'string' },
        seed: { type: 'string', description: 'seed phrase; same seed reproduces the same plate' },
        caption: { type: 'string' },
        project: { type: 'string' },
        out_dir: { type: 'string' },
      },
    },
  },
  {
    name: 'journal_list',
    description: 'List journal artifacts (pdf folios and visual plates).',
    inputSchema: { type: 'object', additionalProperties: false, properties: { project: { type: 'string' }, out_dir: { type: 'string' } } },
  },
  {
    name: 'journal_open',
    description: 'Reveal a journal pdf in Finder.',
    inputSchema: { type: 'object', additionalProperties: false, required: ['path'], properties: { path: { type: 'string' } } },
  },
];

const handlers = {
  async journal_create(args) {
    const title = args.title ?? 'untitled folio';
    const outDir = resolveOutDir(args);
    mkdirSync(outDir, { recursive: true });
    const stamp = new Date().toISOString().slice(0, 10);
    const pdfPath = path.join(outDir, `${stamp}-${slugify(title)}.pdf`);
    const result = await render({
      mode: 'folio',
      title,
      subtitle: args.subtitle ?? '',
      meta: `offcoder journal · ${stamp}`,
      markdown: args.content ?? '',
      seed: title,
      out_path: pdfPath,
    });
    return textResult(JSON.stringify({ ok: true, ...result }, null, 2));
  },

  async journal_visual(args) {
    const title = args.title ?? 'visual experiment';
    const seed = args.seed ?? title;
    const outDir = resolveOutDir(args);
    mkdirSync(outDir, { recursive: true });
    const stamp = new Date().toISOString().slice(0, 10);
    const pdfPath = path.join(outDir, `${stamp}-plate-${slugify(title)}.pdf`);
    const result = await render({
      mode: 'plate',
      title,
      subtitle: 'visual experiment',
      meta: `seed · ${seed}`,
      caption: args.caption ?? '',
      seed,
      out_path: pdfPath,
    });
    return textResult(JSON.stringify({ ok: true, ...result, seed }, null, 2));
  },

  async journal_list(args) {
    const outDir = resolveOutDir(args);
    if (!existsSync(outDir)) return textResult(JSON.stringify({ ok: true, dir: outDir, entries: [] }, null, 2));
    const entries = readdirSync(outDir)
      .filter((name) => name.endsWith('.pdf'))
      .map((name) => {
        const full = path.join(outDir, name);
        const stat = statSync(full);
        return { name, path: full, bytes: stat.size, modified: stat.mtime.toISOString() };
      })
      .sort((a, b) => b.modified.localeCompare(a.modified));
    return textResult(JSON.stringify({ ok: true, dir: outDir, entries }, null, 2));
  },

  async journal_open(args) {
    const target = args.path ?? '';
    if (!target || !existsSync(target)) return errorResult(`not found: ${target}`);
    await execFileAsync('/usr/bin/open', ['-R', target]).catch(() => execFileAsync('/usr/bin/open', [target]));
    return textResult(`revealed ${target}`);
  },
};

serve({ name: 'journal', version: '1.0.0', tools, handlers });
