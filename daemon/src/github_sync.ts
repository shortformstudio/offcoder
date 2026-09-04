import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, statSync } from 'node:fs';
import path from 'node:path';
import Parser from 'tree-sitter';
import type { Database } from 'better-sqlite3';
import { WORKSPACE_ROOT } from './config.js';
import { unixNow } from './util.js';

export interface RepoDescriptor {
  repo_id: string;
  url: string;
  default_branch: string;
}

const TOP_LEVELS = 4;
const MAX_FILE_BYTES = 400_000;
const SYNC_CHUNK = 200;

const LANG_BY_EXT: Record<string, string> = {
  '.ts': 'typescript',
  '.tsx': 'typescript',
  '.js': 'typescript',
  '.mjs': 'typescript',
  '.py': 'python',
  '.rs': 'rust',
  '.go': 'go',
};

const GRAMMAR_MODULES: Record<string, string> = {
  typescript: 'tree-sitter-typescript',
  python: 'tree-sitter-python',
  rust: 'tree-sitter-rust',
  go: 'tree-sitter-go',
};

const SYMBOL_NODE_TYPES: Record<string, string[]> = {
  typescript: ['function_declaration', 'method_definition', 'class_declaration', 'interface_declaration', 'type_alias_declaration', 'enum_declaration', 'function_signature', 'method_signature'],
  python: ['function_definition', 'class_definition'],
  rust: ['function_item', 'impl_item', 'struct_item', 'enum_item', 'trait_item', 'type_item', 'mod_item'],
  go: ['function_declaration', 'method_declaration', 'type_declaration'],
};

const SYMBOL_REGEX: Record<string, RegExp> = {
  typescript: /^\s*(?:export\s+)?(?:async\s+)?(?:function|class|interface|type|enum|const|let|var)\s+[\w$.]+/,
  python: /^\s*(?:async\s+)?def\s+\w+|^\s*class\s+\w+|^\s*@\w+/,
  rust: /^\s*(?:pub\s+)?(?:async\s+)?fn\s+\w+|^\s*(?:pub\s+)?(?:struct|enum|trait|type|impl|mod)\s+\w+|^\s*pub\s+use\s+/,
  go: /^\s*func\s+(?:\([^)]*\)\s+)?\w+|^\s*type\s+\w+\s+(?:struct|interface|map|slice)|^\s*var\s+\w+|^\s*const\s+\w+/,
};

const DEP_REGEX: Record<string, RegExp> = {
  typescript: /^\s*(?:import|from)\s+['"][^'"]+['"]|^\s*require\(\s*['"][^'"]+['"]\s*\)/,
  python: /^\s*(?:import|from)\s+[\w.]+(?:[\s,]+\w+)?/,
  rust: /^\s*use\s+[\w:]+/,
  go: /^\s*import\s+(?:[("]|[^")]*"?)/,
};

export function workspacePath(repoId: string): string {
  return path.join(WORKSPACE_ROOT, repoId.replace('/', '__'));
}

export async function listOrgRepos(org: string): Promise<RepoDescriptor[]> {
  try {
    const out = execFileSync(
      'gh',
      ['repo', 'list', org, '--json', 'name,url,defaultBranchRef'],
      { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }
    );
    const rows = JSON.parse(out) as Array<{ name: string; url: string; defaultBranchRef: any }>;
    return rows.map((r) => {
      let branch = 'main';
      if (typeof r.defaultBranchRef === 'object' && r.defaultBranchRef !== null && r.defaultBranchRef.name) {
        branch = r.defaultBranchRef.name;
      } else if (typeof r.defaultBranchRef === 'string' && r.defaultBranchRef.trim()) {
        branch = r.defaultBranchRef.trim();
      }
      return {
        repo_id: `${org}/${r.name}`,
        url: r.url,
        default_branch: branch,
      };
    });
  } catch {
    return restList(org);
  }
}

async function restList(org: string): Promise<RepoDescriptor[]> {
  const token = process.env.GITHUB_TOKEN;
  const headers: Record<string, string> = { Accept: 'application/vnd.github+json' };
  if (token) headers.Authorization = `Bearer ${token}`;
  const res = await fetch(`https://api.github.com/users/${org}/repos?per_page=100&sort=updated`, { headers });
  if (!res.ok) throw new Error(`github api failed: ${res.status}`);
  const rows = (await res.json()) as Array<{ name: string; clone_url: string; default_branch: string | null }>;
  return rows.map((r) => ({
    repo_id: `${org}/${r.name}`,
    url: r.clone_url,
    default_branch: r.default_branch ?? 'main',
  }));
}

export async function registerRepo(db: Database, descriptor: RepoDescriptor): Promise<{ files: number }> {
  const localPath = workspacePath(descriptor.repo_id);
  mkdirSync(path.dirname(localPath), { recursive: true });
  if (!existsSync(localPath)) {
    execFileSync('git', ['clone', '--depth', '1', '--branch', descriptor.default_branch, descriptor.url, localPath], {
      stdio: 'pipe',
    });
  } else {
    execFileSync('git', ['-C', localPath, 'pull', '--ff-only'], { stdio: 'pipe' });
  }
  return syncIndex(db, descriptor.repo_id, localPath, descriptor.default_branch);
}

interface IndexEntry {
  file: string;
  astSummary: string;
  dependencies: string;
  checksum: string;
  now: number;
  repoId: string;
}

export async function syncIndex(
  db: Database,
  repoId: string,
  localPath: string,
  defaultBranch = 'main'
): Promise<{ files: number; tree: Record<string, unknown> }> {
  const files = execFileSync('git', ['-C', localPath, 'ls-files'], { encoding: 'utf8' })
    .split('\n')
    .filter(Boolean);
  const tree = buildTree(files);
  const now = unixNow();

  const upsert = db.prepare(
    `INSERT INTO context_nodes (file_path, repo_id, ast_summary, dependencies, checksum, last_indexed)
     VALUES (@file_path, @repo_id, @ast_summary, @dependencies, @checksum, @last_indexed)
     ON CONFLICT(file_path) DO UPDATE SET
       ast_summary = excluded.ast_summary,
       dependencies = excluded.dependencies,
       checksum = excluded.checksum,
       last_indexed = excluded.last_indexed`
  );

  const entries: IndexEntry[] = [];
  for (const file of files) {
    const absolute = path.join(localPath, file);
    if (!existsSync(absolute)) continue;
    const size = statSync(absolute).size;
    if (size === 0 || size > MAX_FILE_BYTES) continue;
    const content = readFileSync(absolute, 'utf8');
    if (content.includes('\u0000')) continue;
    entries.push({
      file,
      repoId,
      astSummary: await extractSignatures(content, LANG_BY_EXT[path.extname(file).toLowerCase()] ?? 'plain', file),
      dependencies: JSON.stringify(extractDependencies(content, LANG_BY_EXT[path.extname(file).toLowerCase()] ?? 'plain')),
      checksum: createHash('sha256').update(content).digest('hex'),
      now,
    });
  }

  for (let i = 0; i < entries.length; i += SYNC_CHUNK) {
    const chunk = entries.slice(i, i + SYNC_CHUNK);
    const tx = db.transaction(() => {
      for (const entry of chunk) {
        upsert.run({
          file_path: entry.file,
          repo_id: entry.repoId,
          ast_summary: entry.astSummary,
          dependencies: entry.dependencies,
          checksum: entry.checksum,
          last_indexed: entry.now,
        });
      }
    });
    tx();
  }

  db.prepare(
    `INSERT INTO repo_registry (repo_id, local_path, default_branch, indexed_tree, last_synced)
     VALUES (@repo_id, @local_path, @default_branch, @indexed_tree, @last_synced)
     ON CONFLICT(repo_id) DO UPDATE SET
       indexed_tree = excluded.indexed_tree,
       last_synced = excluded.last_synced`
  ).run({
    repo_id: repoId,
    local_path: localPath,
    default_branch: defaultBranch,
    indexed_tree: JSON.stringify(tree),
    last_synced: now,
  });

  return { files: entries.length, tree };
}

function buildTree(files: string[]): Record<string, unknown> {
  const root: Record<string, unknown> = {};
  for (const file of files) {
    const parts = file.split('/');
    let level: Record<string, unknown> = root;
    for (let i = 0; i < parts.length - 1; i++) {
      if (i >= TOP_LEVELS - 1) break;
      level = level[parts[i]] as Record<string, unknown> ?? (level[parts[i]] = {});
      level.__kind = 'dir';
    }
    level[parts[parts.length - 1]] = { __kind: 'file' };
  }
  return root;
}

const grammarCache = new Map<string, Parser.Language | null>();

async function loadLanguage(lang: string): Promise<Parser.Language | null> {
  if (grammarCache.has(lang)) return grammarCache.get(lang) ?? null;
  const moduleSpec = GRAMMAR_MODULES[lang];
  if (!moduleSpec) {
    grammarCache.set(lang, null);
    return null;
  }
  try {
    const mod = (await import(moduleSpec)) as Record<string, unknown>;
    const container = (mod.default ?? mod) as Record<string, unknown>;
    let language: Parser.Language | null = null;
    if (typeof container.language === 'function') language = (container.language as () => Parser.Language)();
    const nested = (container as Record<string, { language: () => Parser.Language }>).typescript;
    if (!language && typeof nested?.language === 'function') language = nested.language();
    grammarCache.set(lang, language);
    return language;
  } catch {
    grammarCache.set(lang, null);
    return null;
  }
}

export async function extractSignatures(content: string, lang: string, file: string): Promise<string> {
  if (lang === 'plain') {
    return summarizeRegex(content, SYMBOL_REGEX.typescript, file);
  }
  const language = await loadLanguage(lang);
  if (language) {
    const parser = new Parser();
    parser.setLanguage(language);
    const tree = parser.parse(content);
    const seen = new Set<string>();
    const lines: string[] = [];
    for (const type of SYMBOL_NODE_TYPES[lang] ?? []) {
      for (const node of tree.rootNode.descendantsOfType(type)) {
        const text = node.text.replace(/\s+/g, ' ').trim().slice(0, 120);
        if (!text || text.length < 6 || seen.has(text)) continue;
        seen.add(text);
        lines.push(text);
        if (lines.length >= 80) break;
      }
      if (lines.length >= 80) break;
    }
    if (lines.length > 0) return lines.join('\n').slice(0, 8000);
  }
  return summarizeRegex(content, SYMBOL_REGEX[lang] ?? SYMBOL_REGEX.typescript, file);
}

function summarizeRegex(content: string, regex: RegExp, file: string): string {
  const lines: string[] = [];
  for (const line of content.split('\n')) {
    if (regex.test(line)) {
      const clean = line.trim().slice(0, 120);
      if (clean) lines.push(clean);
      if (lines.length >= 80) break;
    }
  }
  if (lines.length === 0) {
    return `${file}: no top-level symbols found (${content.length} bytes)`;
  }
  return lines.join('\n').slice(0, 8000);
}

export function extractDependencies(content: string, lang: string): string[] {
  const regex = DEP_REGEX[lang] ?? DEP_REGEX.typescript;
  const deps = new Set<string>();
  for (const line of content.split('\n')) {
    if (!regex.test(line)) continue;
    const target = line.replace(/^\s*import\s+|^\s*from\s+|^\s*use\s+|^\s*require\s*\(|["';,)]+$/g, '').trim().replace(/\s+/g, ' ');
    if (target.length > 0 && target.length < 120) deps.add(target);
    if (deps.size >= 20) break;
  }
  return [...deps];
}
