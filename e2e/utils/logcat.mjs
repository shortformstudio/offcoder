import { spawn } from 'node:child_process';
import { existsSync, mkdtempSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const cwd = process.cwd();
const projectRoot = existsSync(path.join(cwd, 'daemon'))
  ? cwd
  : existsSync(path.join(here, '..', 'daemon'))
    ? path.join(here, '..')
    : path.join(here, '..', '..');
export const daemonEntry = path.join(projectRoot, 'daemon', 'src', 'index.ts');
export const daemonDir = path.join(projectRoot, 'daemon');

let counter = 0;

export function tmpRoot() {
  return mkdtempSync(path.join(os.tmpdir(), `orch-e2e-${counter++}-`));
}

export function waitFor(probe, timeoutMs = 15_000, interval = 100) {
  return new Promise((resolve, reject) => {
    const start = Date.now();
    const tick = async () => {
      try {
        const value = await probe();
        if (value) return resolve(value);
      } catch {
        /* loop */
      }
      if (Date.now() - start > timeoutMs) return reject(new Error(`waitFor timed out after ${timeoutMs}ms`));
      setTimeout(tick, interval);
    };
    tick();
  });
}

export async function launchDaemon(extraEnv = {}) {
  const root = extraEnv.ORCH_ROOT ?? tmpRoot();
  const port = Number(extraEnv.ORCH_WS_PORT ?? (17_100 + Math.floor(Math.random() * 500)));
  const proc = spawn(process.execPath, ['--import', 'tsx', daemonEntry], {
    cwd: daemonDir,
    env: {
      PATH: process.env.PATH,
      HOME: process.env.HOME,
      ORCH_ROOT: root,
      ORCH_WS_PORT: String(port),
      ORCH_CDP_PORT: '19222',
      ORCH_LEASE_SECONDS: '2',
      ORCH_MAX_RETRIES: '2',
      ...extraEnv,
    },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  const lines = [];
  proc.stdout?.on('data', (d) => lines.push(...String(d).split('\n').filter(Boolean)));
  proc.stderr?.on('data', (d) => lines.push(...String(d).split('\n').filter(Boolean)));

  await waitFor(() => lines.some((l) => l.includes('"code":"daemon_ready"')), 20_000);

  const waitLog = (code, timeoutMs = 15_000) => waitFor(() => lines.find((l) => l.includes(`"code":"${code}"`)), timeoutMs);

  const kill = async () => {
    proc.kill('SIGTERM');
    await waitFor(() => proc.exitCode !== null, 5_000).catch(() => proc.kill('SIGKILL'));
  };

  return { proc, root, port, wsUrl: `ws://127.0.0.1:${port}`, lines, waitLog, kill };
}
