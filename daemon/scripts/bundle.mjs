import * as esbuild from 'esbuild';
import { existsSync, mkdirSync, copyFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(__dirname, '..');
const outDir = path.join(root, 'dist');

if (!existsSync(outDir)) {
  mkdirSync(outDir, { recursive: true });
}

console.log('📦 Bundling Orchestrator Daemon with esbuild...');

try {
  await esbuild.build({
    entryPoints: [path.join(root, 'src', 'index.ts')],
    bundle: true,
    platform: 'node',
    target: 'node20',
    format: 'esm',
    outfile: path.join(outDir, 'index.mjs'),
    sourcemap: true,
    minify: false,
    external: [
      'better-sqlite3',
      'tree-sitter',
      'tree-sitter-go',
      'tree-sitter-python',
      'tree-sitter-rust',
      'tree-sitter-typescript',
      'puppeteer-core',
      'ws',
    ],
  });

  // Copy schema.sql into dist alongside index.mjs
  copyFileSync(path.join(root, 'src', 'db', 'schema.sql'), path.join(outDir, 'schema.sql'));

  console.log('✅ Build successful: dist/index.mjs and dist/schema.sql generated.');
} catch (error) {
  console.error('❌ Build failed:', error);
  process.exit(1);
}
