import { getDb } from './db/connection.js';
import { listJournal } from './db/journal.js';
import { createFreshProject } from './db/projects.js';
import { IPCChannel } from './ipc.js';
import { CDPBroker } from './browser_broker.js';
import { listOrgRepos, registerRepo } from './github_sync.js';
import { queueCounts, recoverExpiredLeases, checkoutTask, finalizeTask, addStagingArtifact } from './db/task_queue.js';
import { CDP_PORT, DAEMON_WS_PORT, LEASE_SECONDS, MAX_RETRIES, ORG_NAME, SCREENSHOT_ROOT, WS_TOKEN } from './config.js';
import { taskEvents } from './task_events.js';
import { MarqueeDirector } from './marquee.js';
import { structLog, marqueeMapping } from './errors.js';
import { computeTelemetry } from './telemetry.js';
import { readdirSync, rmSync, statSync } from 'node:fs';
import path from 'node:path';
import { exit } from 'node:process';
const db = getDb();
const marquee = new MarqueeDirector();
let channel = null;
let cdpConnected = false;
let lastTelemetry = null;
function marqueeify(code) {
    const mapping = marqueeMapping(code);
    if (!mapping)
        return;
    const state = marquee.post(mapping.level, mapping.text, code);
    channel?.broadcast({ type: 'marquee', level: state.level, text: state.text, code: state.code, ts: state.ts });
}
async function main() {
    channel = new IPCChannel(DAEMON_WS_PORT, async (command, reply) => {
        switch (command.type) {
            case 'org_repos': {
                reply({ type: 'org_repos', repos: await listOrgRepos(ORG_NAME) });
                break;
            }
            case 'pull_repo': {
                if (!command.repoId)
                    return;
                const descriptor = (await listOrgRepos(ORG_NAME)).find((r) => r.repo_id === command.repoId);
                if (!descriptor) {
                    marqueeify('repo_missing');
                    reply({ type: 'error', code: 'repo_missing', detail: `repo not found: ${command.repoId}` });
                    return;
                }
                const result = await registerRepo(db, descriptor);
                ch.broadcast({ type: 'repo_registered', repoId: descriptor.repo_id, files: result.files });
                marqueeify('repo_indexed');
                reply({ type: 'repo_registered', repoId: descriptor.repo_id, files: result.files });
                break;
            }
            case 'fresh_project': {
                if (!command.name || !command.masterPlan) {
                    reply({ type: 'error', code: 'bad_command', detail: 'name and masterPlan are required' });
                    return;
                }
                const { sessionId, planTaskId, reused } = createFreshProject(db, command.name, command.masterPlan);
                ch.broadcast({
                    type: 'journal',
                    sessionId,
                    entryType: 'PLAN_INIT',
                    target: command.name,
                    summary: reused ? 'decomposition already queued (idempotent)' : 'bootstrap decomposition queued',
                });
                reply({ type: 'plan_queued', sessionId, taskId: planTaskId, reused });
                break;
            }
            case 'journal_query': {
                reply({ type: 'journal_entries', entries: listJournal(db, command.sessionId ?? '*') });
                break;
            }
            case 'screencast_subscribe': {
                reply({ type: 'screencast_subscribed' });
                break;
            }
            case 'self_fulfill': {
                if (process.env.ORCH_SELFTEST !== '1')
                    break;
                const task = checkoutTask(db, 'self-fulfiller', 'LOCAL_VERIFIER');
                if (task) {
                    addStagingArtifact(db, {
                        taskId: task.task_id,
                        workerOrigin: 'self-fulfiller',
                        rawCodePayload: '// selftest artifact',
                        screenshotPath: null,
                        syntaxValid: true,
                    });
                    finalizeTask(db, task.task_id, 'self-fulfiller', 'STAGED');
                    reply({ type: 'self_fulfilled', taskId: task.task_id });
                }
                else {
                    reply({ type: 'self_fulfilled', taskId: null });
                }
                break;
            }
            default:
                reply({ type: 'error', code: 'bad_command', detail: `unknown command: ${command.type}` });
        }
    }, {
        token: WS_TOKEN,
        snapshot: () => [
            { type: 'marquee_state', states: marquee.snapshot() },
            {
                type: 'status',
                key: 'cdp',
                state: cdpConnected ? 'CONNECTED' : 'IDLE',
                detail: cdpConnected ? `127.0.0.1:${CDP_PORT}` : 'run scripts/chrome_launch.sh',
            },
            ...(lastTelemetry ? [{ type: 'telemetry', ...lastTelemetry }] : []),
        ],
        metricsHandler: () => {
            const detailedCounts = db.prepare(`
          SELECT status, count(*) as c FROM task_queue GROUP BY status
        `).all();
            const statusMap = {
                PENDING: 0,
                IN_FLIGHT: 0,
                STAGED: 0,
                VERIFIED: 0,
                FAILED: 0,
            };
            for (const row of detailedCounts) {
                statusMap[row.status] = row.c;
            }
            const lines = [
                '# HELP orchestrator_daemon_connected_clients Current number of connected WebSocket clients',
                '# TYPE orchestrator_daemon_connected_clients gauge',
                `orchestrator_daemon_connected_clients ${channel?.clientCount ?? 0}`,
                '# HELP orchestrator_daemon_queue_tasks Number of tasks in queue partitioned by status',
                '# TYPE orchestrator_daemon_queue_tasks gauge',
                `orchestrator_daemon_queue_tasks{status="pending"} ${statusMap.PENDING}`,
                `orchestrator_daemon_queue_tasks{status="inflight"} ${statusMap.IN_FLIGHT}`,
                `orchestrator_daemon_queue_tasks{status="staged"} ${statusMap.STAGED}`,
                `orchestrator_daemon_queue_tasks{status="verified"} ${statusMap.VERIFIED}`,
                `orchestrator_daemon_queue_tasks{status="failed"} ${statusMap.FAILED}`,
                '# HELP orchestrator_daemon_cdp_connected Whether Chrome CDP is connected (1) or offline (0)',
                '# TYPE orchestrator_daemon_cdp_connected gauge',
                `orchestrator_daemon_cdp_connected ${cdpConnected ? 1 : 0}`,
                '# HELP orchestrator_daemon_battery_percent System battery percentage if available',
                '# TYPE orchestrator_daemon_battery_percent gauge',
                `orchestrator_daemon_battery_percent ${lastTelemetry?.batteryPercent ?? -1}`,
                '# HELP orchestrator_daemon_uptime_seconds Seconds since daemon process started',
                '# TYPE orchestrator_daemon_uptime_seconds counter',
                `orchestrator_daemon_uptime_seconds ${Math.floor(process.uptime())}`,
            ];
            return lines.join('\n') + '\n';
        },
    });
    const ch = channel;
    const broker = new CDPBroker(CDP_PORT);
    cdpConnected = await broker.checkConnection();
    if (cdpConnected) {
        await broker.connect();
        structLog({ level: 'info', code: 'cdp_connected', msg: `screencast attached to ${CDP_PORT}` });
        marqueeify('cdp_connected');
        broker
            .attachScreencast('GEMINI_WEB', (frame) => {
            if (frame.length > 512 * 1024)
                return;
            channel?.broadcast({ type: 'screencast_frame', data: frame });
        })
            .catch(() => marqueeify('cdp_offline'));
    }
    else {
        structLog({ level: 'warning', code: 'cdp_offline', msg: 'chrome not attached on 9222' });
        marqueeify('cdp_offline');
    }
    taskEvents.on('task', (event) => {
        channel?.broadcast({ type: 'task_event', ...event });
        if (event.status === 'IN_FLIGHT')
            marqueeify('task_checked_out');
        if (event.status === 'STAGED')
            marqueeify('task_staged');
        if (event.status === 'VERIFIED')
            marqueeify('task_verified');
        if (event.status === 'FAILED')
            marqueeify('task_failed');
        if (event.status === 'PENDING_RECOVERED')
            marqueeify('lease_expired');
    });
    let sweepInProgress = false;
    const sweep = () => {
        if (sweepInProgress)
            return;
        sweepInProgress = true;
        try {
            const { reaped } = recoverExpiredLeases(db);
            if (reaped > 0) {
                structLog({ level: 'warning', code: 'lease_expired', msg: `${reaped} task(s) reclaimed` });
                channel?.broadcast({ type: 'marquee', level: 'alert', text: 'lease expired — task reclaimed', code: 'lease_expired', ts: Date.now() });
            }
        }
        catch (error) {
            structLog({ level: 'error', code: 'sweep_failed', msg: String(error instanceof Error ? error.message : error) });
        }
        finally {
            sweepInProgress = false;
        }
    };
    const telemetryTimer = setInterval(() => {
        const counts = queueCounts(db);
        const t = computeTelemetry(counts.pending, counts.inflight, cdpConnected);
        lastTelemetry = t;
        channel?.broadcast({ type: 'telemetry', ...t });
    }, 5_000);
    sweep();
    const sweepTimer = setInterval(sweep, 30_000);
    const prune = () => {
        try {
            const files = readdirSync(SCREENSHOT_ROOT)
                .filter((f) => f.endsWith('.png'))
                .map((f) => ({ f, t: statSync(path.join(SCREENSHOT_ROOT, f)).mtimeMs }))
                .sort((a, b) => b.t - a.t);
            for (const entry of files.slice(200))
                rmSync(path.join(SCREENSHOT_ROOT, entry.f), { force: true });
        }
        catch (error) {
            structLog({ level: 'debug', code: 'prune', msg: String(error instanceof Error ? error.message : error) });
        }
    };
    prune();
    const pruneTimer = setInterval(prune, 60 * 60 * 1000);
    structLog({
        level: 'info',
        code: 'daemon_ready',
        msg: `ws ${DAEMON_WS_PORT} cdp ${CDP_PORT} org ${ORG_NAME} lease ${LEASE_SECONDS}s retries ${MAX_RETRIES}`,
    });
    const shutdown = () => {
        for (const timer of [telemetryTimer, sweepTimer, pruneTimer])
            clearInterval(timer);
        void broker.dispose();
        channel?.close();
        structLog({ level: 'info', code: 'daemon_stopped', msg: 'shutdown complete' });
    };
    process.on('SIGINT', () => shutdown());
    process.on('SIGTERM', () => shutdown());
}
process.on('uncaughtException', (error) => {
    structLog({ level: 'critical', code: 'uncaught', msg: error.stack ?? String(error) });
    exit(1);
});
process.on('unhandledRejection', (error) => {
    structLog({ level: 'critical', code: 'unhandled_rejection', msg: String(error) });
});
main().catch((error) => {
    structLog({ level: 'critical', code: 'fatal', msg: String(error instanceof Error ? error.stack : error) });
    exit(1);
});
