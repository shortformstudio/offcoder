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
    summary: 'PDF Folio Architect: Renders autonomous designed typographic PDF documents',
    description: 'Render an autonomously designed, high-resolution PDF folio document from markdown text. Generates typographic hierarchy, vector styling, metadata headers, and cover ornamentation. Returns the generated PDF filesystem path.',
    inputSchema: {
      type: 'object',
      additionalProperties: false,
      required: ['title', 'content'],
      properties: {
        title: {
          type: 'string',
          description: 'Document title printed on cover and folio headers.',
        },
        content: {
          type: 'string',
          description: 'Markdown formatted body text (supports headings, code fences, blockquotes, lists, bold/italics).',
        },
        subtitle: {
          type: 'string',
          description: 'Optional secondary subtitle displayed beneath the main heading.',
        },
        project: {
          type: 'string',
          description: 'Optional project name; when set, writes directly to <project>/journal/.',
        },
        out_dir: {
          type: 'string',
          description: 'Optional explicit filesystem destination directory for the generated PDF.',
        },
      },
    },
  },
  {
    name: 'journal_visual',
    summary: 'Sacred Plate Generator: Creates generative vector geometry plates',
    description: 'Generate a seeded generative art plate rendered as a designed PDF artifact. Output is completely deterministic based on seed phrase (same seed creates identical vector geometry).',
    inputSchema: {
      type: 'object',
      additionalProperties: false,
      required: ['title'],
      properties: {
        title: {
          type: 'string',
          description: 'Title of the visual artwork plate.',
        },
        seed: {
          type: 'string',
          description: 'Seed phrase or token driving deterministic procedural generation.',
        },
        caption: {
          type: 'string',
          description: 'Explanatory or poetic caption rendered at bottom margin.',
        },
        project: {
          type: 'string',
          description: 'Optional project name context.',
        },
        out_dir: {
          type: 'string',
          description: 'Optional output destination directory.',
        },
      },
    },
  },
  {
    name: 'journal_list',
    summary: 'Folio Catalog: Lists existing PDF folios and design artifacts',
    description: 'List all generated PDF artifacts in the target project or global journal directory, sorted by newest modification date.',
    inputSchema: {
      type: 'object',
      additionalProperties: false,
      properties: {
        project: {
          type: 'string',
          description: 'Filter listing to specific workspace project.',
        },
        out_dir: {
          type: 'string',
          description: 'Custom directory path to inspect.',
        },
      },
    },
  },
  {
    name: 'journal_open',
    summary: 'Finder Revealer: Opens or highlights PDF in macOS Finder',
    description: 'Reveal or open the generated PDF file directly in macOS Finder or default PDF viewer.',
    inputSchema: {
      type: 'object',
      additionalProperties: false,
      required: ['path'],
      properties: {
        path: {
          type: 'string',
          description: 'Absolute filesystem path to the PDF artifact.',
        },
      },
    },
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
