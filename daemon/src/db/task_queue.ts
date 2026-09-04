import { randomUUID } from 'node:crypto';
import type { Database } from 'better-sqlite3';
import { LEASE_SECONDS, MAX_RETRIES } from '../config.js';
import { unixNow } from '../util.js';
import { taskEvents } from '../task_events.js';

export type WorkerName = 'GEMINI_WEB' | 'DEEPSEEK_WEB' | 'KIMI_WEB' | 'LOCAL_VERIFIER';
export type OperationMode = 'GENERATION' | 'REFACTOR_CONSULTATION' | 'ADVERSARIAL_CRITIQUE' | 'PLAN_DECOMPOSITION';
export type TaskStatus = 'PENDING' | 'IN_FLIGHT' | 'STAGED' | 'VERIFIED' | 'FAILED';

export interface Task {
  task_id: string;
  parent_task_id: string | null;
  target_worker: WorkerName;
  operation_mode: OperationMode;
  target_file: string;
  prompt_payload: string;
  source_context: string | null;
  status: TaskStatus;
  retry_count: number;
  lease_owner: string | null;
  lease_expires_at: number | null;
  scheduled_at: number | null;
  created_at: number;
  updated_at: number;
}

export interface EnqueueInput {
  targetWorker: WorkerName;
  operationMode: OperationMode;
  targetFile: string;
  promptPayload: string;
  sourceContext?: string | null;
  parentTaskId?: string | null;
  retryCount?: number;
  key?: string;
}

function emit(db: Database, taskId: string, status: string): void {
  const row = db
    .prepare(`SELECT task_id, target_worker, operation_mode, target_file FROM task_queue WHERE task_id = ?`)
    .get(taskId) as Task | undefined;
  if (!row) return;
  taskEvents.emit('task', {
    taskId,
    status,
    targetWorker: row.target_worker,
    operationMode: row.operation_mode,
    targetFile: row.target_file,
    at: unixNow(),
  });
}

export function enqueueTask(db: Database, input: EnqueueInput): string {
  const taskId = randomUUID();
  if (input.key) {
    const existing = db
      .prepare(
        `SELECT task_id FROM task_queue WHERE operation_mode = ? AND target_worker = ? AND prompt_payload LIKE ? LIMIT 1`
      )
      .get(input.operationMode, input.targetWorker, `%${input.key}%`) as { task_id: string } | undefined;
    if (existing) return existing.task_id;
  }
  db.prepare(
    `INSERT INTO task_queue (task_id, parent_task_id, target_worker, operation_mode, target_file, prompt_payload, source_context, status, retry_count, created_at, updated_at)
     VALUES (@task_id, @parent_task_id, @target_worker, @operation_mode, @target_file, @prompt_payload, @source_context, 'PENDING', @retry_count, @created_at, @updated_at)`
  ).run({
    task_id: taskId,
    parent_task_id: input.parentTaskId ?? null,
    target_worker: input.targetWorker,
    operation_mode: input.operationMode,
    target_file: input.targetFile,
    prompt_payload: input.promptPayload,
    source_context: input.sourceContext ?? null,
    retry_count: input.retryCount ?? 0,
    created_at: unixNow(),
    updated_at: unixNow(),
  });
  emit(db, taskId, 'PENDING');
  return taskId;
}

export function recoverExpiredLeases(db: Database): AlertResult {
  const stale = db
    .prepare(
      `SELECT task_id, target_worker, operation_mode, target_file FROM task_queue
       WHERE status = 'IN_FLIGHT' AND lease_expires_at < ?`
    )
    .all(unixNow()) as Task[];
  const reaped = db
    .prepare(
      `UPDATE task_queue
       SET status = 'PENDING', lease_owner = NULL, lease_expires_at = NULL, scheduled_at = unixepoch(), updated_at = ?
       WHERE status = 'IN_FLIGHT' AND lease_expires_at < ?`
    )
    .run(unixNow(), unixNow()).changes;
  for (const row of stale) {
    taskEvents.emit('task', {
      taskId: row.task_id,
      status: 'PENDING_RECOVERED',
      targetWorker: row.target_worker,
      operationMode: row.operation_mode,
      targetFile: row.target_file,
      at: unixNow(),
    });
  }
  return { reaped };
}

export interface AlertResult {
  reaped: number;
}

export function checkoutTask(db: Database, workerId: string, targetWorker: WorkerName): Task | null {
  const tx = db.transaction((): Task | null => {
    recoverExpiredLeases(db);
    const row = db
      .prepare(
        `UPDATE task_queue
         SET status = 'IN_FLIGHT', lease_owner = @worker_id, lease_expires_at = @expires, scheduled_at = NULL, updated_at = @now
         WHERE task_id = (
           SELECT task_id FROM task_queue
           WHERE status = 'PENDING' AND target_worker = @target_worker
             AND (scheduled_at IS NULL OR scheduled_at <= @now)
           ORDER BY retry_count ASC, created_at ASC LIMIT 1
         )
         RETURNING *`
      )
      .get({
        worker_id: workerId,
        expires: unixNow() + LEASE_SECONDS,
        now: unixNow(),
        target_worker: targetWorker,
      }) as Task | undefined;
    return row ?? null;
  });
  const task = tx();
  if (task) emit(db, task.task_id, 'IN_FLIGHT');
  return task;
}

export function touchLease(db: Database, taskId: string, workerId: string): boolean {
  const res = db
    .prepare(
      `UPDATE task_queue SET lease_expires_at = @expires, updated_at = @now
       WHERE task_id = @task_id AND lease_owner = @worker_id AND status = 'IN_FLIGHT'`
    )
    .run({ expires: unixNow() + LEASE_SECONDS, now: unixNow(), task_id: taskId, worker_id: workerId });
  return res.changes > 0;
}

export function finalizeTask(db: Database, taskId: string, workerId: string, status: 'STAGED' | 'VERIFIED' | 'FAILED'): boolean {
  const res = db
    .prepare(
      `UPDATE task_queue SET status = @status, lease_owner = NULL, lease_expires_at = NULL, scheduled_at = NULL, updated_at = @now
       WHERE task_id = @task_id AND lease_owner = @worker_id AND status = 'IN_FLIGHT'`
    )
    .run({ status, now: unixNow(), task_id: taskId, worker_id: workerId });
  if (res.changes > 0) emit(db, taskId, status);
  return res.changes > 0;
}

export function failTask(db: Database, taskId: string, workerId: string): 'FAILED' | 'PENDING' {
  const task = db
    .prepare(`SELECT retry_count FROM task_queue WHERE task_id = ? AND lease_owner = ?`)
    .get(taskId, workerId) as { retry_count: number } | undefined;
  if (!task) return 'FAILED';
  const willRetry = task.retry_count < MAX_RETRIES;
  const nextStatus = willRetry ? 'PENDING' : 'FAILED';
  const backoff = Math.pow(2, Math.min(task.retry_count + 1, 6)) * 5;
  db.prepare(
    `UPDATE task_queue
     SET status = ?, retry_count = retry_count + 1, lease_owner = NULL, lease_expires_at = NULL,
         scheduled_at = ?, updated_at = ?
     WHERE task_id = ? AND lease_owner = ?`
  ).run(nextStatus, unixNow() + backoff, unixNow(), taskId, workerId);
  emit(db, taskId, nextStatus);
  return nextStatus;
}

export interface StagingInput {
  taskId: string;
  workerOrigin: string;
  rawCodePayload: string;
  screenshotPath: string | null;
  syntaxValid: boolean;
  diagnosticsLog?: string | null;
}

export function addStagingArtifact(db: Database, artifact: StagingInput): string {
  const artifactId = randomUUID();
  db.prepare(
    `INSERT INTO staging_ring (artifact_id, task_id, worker_origin, raw_code_payload, screenshot_path, syntax_valid, diagnostics_log, created_at)
     VALUES (@artifact_id, @task_id, @worker_origin, @raw_code_payload, @screenshot_path, @syntax_valid, @diagnostics_log, @created_at)
     ON CONFLICT(task_id) DO UPDATE SET raw_code_payload = excluded.raw_code_payload, screenshot_path = excluded.screenshot_path, syntax_valid = excluded.syntax_valid, diagnostics_log = excluded.diagnostics_log`
  ).run({
    artifact_id: artifactId,
    task_id: artifact.taskId,
    worker_origin: artifact.workerOrigin,
    raw_code_payload: artifact.rawCodePayload,
    screenshot_path: artifact.screenshotPath,
    syntax_valid: artifact.syntaxValid ? 1 : 0,
    diagnostics_log: artifact.diagnosticsLog ?? null,
    created_at: unixNow(),
  });
  return artifactId;
}

export function queueCounts(db: Database): { pending: number; inflight: number } {
  const row = db
    .prepare(
      `SELECT
         SUM(CASE WHEN status = 'PENDING' THEN 1 ELSE 0 END) AS pending,
         SUM(CASE WHEN status = 'IN_FLIGHT' THEN 1 ELSE 0 END) AS inflight
       FROM task_queue`
    )
    .get() as { pending: number | null; inflight: number | null };
  return { pending: row.pending ?? 0, inflight: row.inflight ?? 0 };
}

export function listPendingTasks(db: Database, targetWorker?: WorkerName): Task[] {
  if (targetWorker) {
    return db
      .prepare(`SELECT * FROM task_queue WHERE status = 'PENDING' AND target_worker = ? ORDER BY created_at ASC`)
      .all(targetWorker) as Task[];
  }
  return db.prepare(`SELECT * FROM task_queue WHERE status = 'PENDING' ORDER BY created_at ASC`).all() as Task[];
}
