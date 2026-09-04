import { test, expect } from '@playwright/test';
import { wsClient } from '../utils/ws.mjs';
import { launchDaemon } from '../utils/logcat.mjs';

test.describe('marquee status contract', () => {
  test('idle→working→success sequence, journal + console logs', async () => {
    const daemon = await launchDaemon({ ORCH_SELFTEST: '1' });
    const client = await wsClient(daemon.wsUrl);

    const boot = await client.waitForType('marquee_state');
    const bootStates = boot.states ?? [];
    expect(bootStates.some((s: any) => s.code === 'cdp_offline' && s.level === 'alert')).toBeTruthy();

    client.send({ type: 'fresh_project', name: 'mech-1', masterPlan: 'build a mechanism' });
    const plan = await client.waitForType('plan_queued');
    expect(plan.taskId).toBeTruthy();

    const journal = await client.waitForType('journal');
    expect(journal.entryType).toBe('PLAN_INIT');

    client.send({ type: 'self_fulfill' });
    const working = await client.waitForType('marquee', 15_000, (m: any) => m.code === 'task_checked_out');
    expect(working.level).toBe('working');
    const success = await client.waitForType('marquee', 15_000, (m: any) => m.code === 'task_staged');
    expect(success.level).toBe('success');

    client.send({ type: 'pull_repo', repoId: 'shortformstudio/does-not-exist' });
    const fail = await client.waitForType('marquee', 15_000, (m: any) => m.code === 'repo_missing');
    expect(fail.level).toBe('alert');

    await daemon.waitLog('daemon_ready');
    await daemon.waitLog('cdp_offline');

    client.close();
    await daemon.kill();
  });

  test('idempotent bootstrap: double submit returns the same task', async () => {
    const daemon = await launchDaemon();
    const client = await wsClient(daemon.wsUrl);

    client.send({ type: 'fresh_project', name: 'mech-1', masterPlan: 'exact same plan' });
    const first = await client.waitForType('plan_queued');
    client.send({ type: 'fresh_project', name: 'mech-1', masterPlan: 'exact same plan' });
    const second = await client.waitForType('plan_queued', 15_000, (m: any) => m.reused === true);
    expect(second.taskId).toBe(first.taskId);

    client.close();
    await daemon.kill();
  });
});
