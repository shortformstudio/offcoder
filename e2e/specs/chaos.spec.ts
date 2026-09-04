import { test, expect } from '@playwright/test';
import { spawn, type ChildProcess } from 'node:child_process';
import { existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { wsClient } from '../utils/ws.mjs';
import { launchDaemon, waitFor } from '../utils/logcat.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const cwd = process.cwd();
const faucetBase = existsSync(path.join(cwd, 'fixtures')) ? cwd : path.join(here, '..');
const faucetEntry = path.join(faucetBase, 'fixtures', 'faucet_worker.mjs');

function spawnFaucet(root: string, mode: string): { proc: ChildProcess; waitLine: (kw: string, timeoutMs?: number) => Promise<string> } {
  const proc = spawn(process.execPath, [faucetEntry], {
    env: { PATH: process.env.PATH, ORCH_ROOT: root, MODE: mode },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  const lines: string[] = [];
  proc.stdout?.on('data', (d: Buffer) => lines.push(...String(d).split('\n').filter(Boolean)));
  proc.stderr?.on('data', (d: Buffer) => lines.push(...String(d).split('\n').filter(Boolean)));
  const waitLine = (kw: string, timeoutMs = 20_000) =>
    waitFor(() => lines.find((l) => l.includes(kw)), timeoutMs);
  return { proc, waitLine };
}

test.describe('chaos hardening', () => {
  test('malformed json frame → error reply + structured console', async () => {
    const daemon = await launchDaemon();
    const client = await wsClient(daemon.wsUrl);
    client.sendRaw('{totally broken');
    const err = await client.waitForType('error', 10_000, (m: any) => m.code === 'bad_client_frame');
    expect(err.detail).toBeTruthy();
    await daemon.waitLog('bad_client_frame');
    client.close();
    await daemon.kill();
  });

  test('oversize frame → close 1013', async () => {
    const daemon = await launchDaemon();
    const client = await wsClient(daemon.wsUrl);
    client.sendRaw('{"type":"' + 'x'.repeat(300_000) + '"}');
    expect(await client.closeCode()).toBe(1013);
    await daemon.waitLog('frame_overflow');
    client.close();
    await daemon.kill();
  });

  test('token auth: reject unauthenticated, accept authenticated', async () => {
    const daemon = await launchDaemon({ ORCH_WS_TOKEN: 'sekrit' });

    const rogue = await wsClient(daemon.wsUrl);
    rogue.send({ type: 'org_repos' });
    expect(await rogue.closeCode()).toBe(1008);
    await daemon.waitLog('auth_rejected');

    const good = await wsClient(daemon.wsUrl);
    good.send({ type: 'auth', token: 'sekrit' });
    await good.waitForType('marquee_state');
    await good.waitForType('status');
    good.send({ type: 'org_repos' });
    await good.waitForType('error').catch(() => undefined);
    good.close();
    await daemon.kill();
  });

  test('lease expiry: stalled task reclaimed, marquee alert, task completes', async () => {
    const daemon = await launchDaemon({ ORCH_LEASE_SECONDS: '2' });
    const watcher = await wsClient(daemon.wsUrl);

    const stallFaucet = spawnFaucet(daemon.root, 'stall');
    const client = await wsClient(daemon.wsUrl);
    client.send({ type: 'fresh_project', name: 'stuck-1', masterPlan: 'stall this task' });
    await client.waitForType('plan_queued');

    await stallFaucet.waitLine('stalled');
    stallFaucet.proc.kill('SIGKILL');

    await daemon.waitLog('lease_expired', 45_000);
    const alert = await watcher.waitForType('marquee', 45_000, (m: any) => m.code === 'lease_expired');
    expect(alert.level).toBe('alert');

    const happyFaucet = spawnFaucet(daemon.root, 'happy');
    await happyFaucet.waitLine('staged');
    happyFaucet.proc.kill('SIGKILL');

    client.close();
    watcher.close();
    await daemon.kill();
  });
});
