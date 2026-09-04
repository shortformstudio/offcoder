import { randomUUID, createHash } from 'node:crypto';
import path from 'node:path';
import type { Database } from 'better-sqlite3';
import { enqueueTask, addStagingArtifact } from './task_queue.js';
import { addJournal } from './journal.js';
import { WORKSPACE_ROOT } from '../config.js';

export interface FreshProjectResult {
  sessionId: string;
  planTaskId: string;
  reused: boolean;
}

const PROJECT_NAME_REGEX = /^[a-zA-Z0-9._-]{1,64}$/;
const MAX_PLAN_CHARS = 4000;

export function projectKey(name: string, masterPlan: string): string {
  const digest = createHash('sha256').update(masterPlan).digest('hex').slice(0, 12);
  return `FRESH:${name}:${digest}`;
}

export function createFreshProject(db: Database, name: string, masterPlan: string): FreshProjectResult {
  if (!PROJECT_NAME_REGEX.test(name)) {
    throw new Error(`invalid project name "${name}": must match /^[a-zA-Z0-9._-]{1,64}$/`);
  }
  const resolved = path.resolve(WORKSPACE_ROOT, name);
  if (!resolved.startsWith(WORKSPACE_ROOT + path.sep)) {
    throw new Error(`path traversal detected: project path "${resolved}" escapes workspace root`);
  }

  const key = projectKey(name, masterPlan);
  const existing = db
    .prepare(
      `SELECT task_id FROM task_queue
       WHERE operation_mode = 'PLAN_DECOMPOSITION' AND prompt_payload LIKE @key LIMIT 1`
    )
    .get({ key: `%${key}%` }) as { task_id: string } | undefined;
  if (existing) {
    return { sessionId: randomUUID(), planTaskId: existing.task_id, reused: true };
  }
  const sessionId = randomUUID();
  addJournal(db, sessionId, 'PLAN_INIT', name, `master plan received for ${name}`);

  const isChunked = masterPlan.length > MAX_PLAN_CHARS;
  const decompositionPlan = isChunked
    ? `${masterPlan.slice(0, MAX_PLAN_CHARS)}\n\n[PLAN_CHUNKED: remaining ${masterPlan.length - MAX_PLAN_CHARS} chars preserved in diagnostics log]`
    : masterPlan;

  const planTaskId = enqueueTask(db, {
    targetWorker: 'LOCAL_VERIFIER',
    operationMode: 'PLAN_DECOMPOSITION',
    targetFile: name,
    promptPayload: JSON.stringify({
      key,
      projectName: name,
      masterPlan: decompositionPlan,
      chunked: isChunked,
      totalLength: masterPlan.length,
      requested: 'atomic modules with a dependency graph; one task per module, dependencies linked via parent_task_id',
    }),
    sourceContext: isChunked ? `PLAN_REF:sha256:${createHash('sha256').update(masterPlan).digest('hex')}` : null,
  });

  if (isChunked) {
    addStagingArtifact(db, {
      taskId: planTaskId,
      workerOrigin: 'orchestrator_chunker',
      rawCodePayload: '// PLAN_FULL_POINTER',
      screenshotPath: null,
      syntaxValid: true,
      diagnosticsLog: masterPlan,
    });
  }

  return { sessionId, planTaskId, reused: false };
}
