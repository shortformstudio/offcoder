import { randomUUID } from 'node:crypto';
import { LEASE_SECONDS, MAX_RETRIES } from '../config.js';
import { unixNow } from '../util.js';
import { taskEvents } from '../task_events.js';
function emit(db, taskId, status) {
    const row = db
        .prepare(`SELECT task_id, target_worker, operation_mode, target_file FROM task_queue WHERE task_id = ?`)
        .get(taskId);
    if (!row)
        return;
    taskEvents.emit('task', {
        taskId,
        status,
        targetWorker: row.target_worker,
        operationMode: row.operation_mode,
        targetFile: row.target_file,
        at: unixNow(),
    });
}
export function enqueueTask(db, input) {
    const taskId = randomUUID();
    if (input.key) {
        const existing = db
            .prepare(`SELECT task_id FROM task_queue WHERE operation_mode = ? AND target_worker = ? AND prompt_payload LIKE ? LIMIT 1`)
            .get(input.operationMode, input.targetWorker, `%${input.key}%`);
        if (existing)
            return existing.task_id;
    }
    db.prepare(`INSERT INTO task_queue (task_id, parent_task_id, target_worker, operation_mode, target_file, prompt_payload, source_context, status, retry_count, created_at, updated_at)
     VALUES (@task_id, @parent_task_id, @target_worker, @operation_mode, @target_file, @prompt_payload, @source_context, 'PENDING', @retry_count, @created_at, @updated_at)`).run({
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
export function recoverExpiredLeases(db) {
    const stale = db
        .prepare(`SELECT task_id, target_worker, operation_mode, target_file FROM task_queue
       WHERE status = 'IN_FLIGHT' AND lease_expires_at < ?`)
        .all(unixNow());
    const reaped = db
        .prepare(`UPDATE task_queue
       SET status = 'PENDING', lease_owner = NULL, lease_expires_at = NULL, scheduled_at = unixepoch(), updated_at = ?
       WHERE status = 'IN_FLIGHT' AND lease_expires_at < ?`)
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
export function checkoutTask(db, workerId, targetWorker) {
    const tx = db.transaction(() => {
        recoverExpiredLeases(db);
        const row = db
            .prepare(`UPDATE task_queue
         SET status = 'IN_FLIGHT', lease_owner = @worker_id, lease_expires_at = @expires, scheduled_at = NULL, updated_at = @now
         WHERE task_id = (
           SELECT task_id FROM task_queue
           WHERE status = 'PENDING' AND target_worker = @target_worker
             AND (scheduled_at IS NULL OR scheduled_at <= @now)
           ORDER BY retry_count ASC, created_at ASC LIMIT 1
         )
         RETURNING *`)
            .get({
            worker_id: workerId,
            expires: unixNow() + LEASE_SECONDS,
            now: unixNow(),
            target_worker: targetWorker,
        });
        return row ?? null;
    });
    const task = tx();
    if (task)
        emit(db, task.task_id, 'IN_FLIGHT');
    return task;
}
export function touchLease(db, taskId, workerId) {
    const res = db
        .prepare(`UPDATE task_queue SET lease_expires_at = @expires, updated_at = @now
       WHERE task_id = @task_id AND lease_owner = @worker_id AND status = 'IN_FLIGHT'`)
        .run({ expires: unixNow() + LEASE_SECONDS, now: unixNow(), task_id: taskId, worker_id: workerId });
    return res.changes > 0;
}
export function finalizeTask(db, taskId, workerId, status) {
    const res = db
        .prepare(`UPDATE task_queue SET status = @status, lease_owner = NULL, lease_expires_at = NULL, scheduled_at = NULL, updated_at = @now
       WHERE task_id = @task_id AND lease_owner = @worker_id AND status = 'IN_FLIGHT'`)
        .run({ status, now: unixNow(), task_id: taskId, worker_id: workerId });
    if (res.changes > 0)
        emit(db, taskId, status);
    return res.changes > 0;
}
export function failTask(db, taskId, workerId) {
    const task = db
        .prepare(`SELECT retry_count FROM task_queue WHERE task_id = ? AND lease_owner = ?`)
        .get(taskId, workerId);
    if (!task)
        return 'FAILED';
    const willRetry = task.retry_count < MAX_RETRIES;
    const nextStatus = willRetry ? 'PENDING' : 'FAILED';
    const backoff = Math.pow(2, Math.min(task.retry_count + 1, 6)) * 5;
    db.prepare(`UPDATE task_queue
     SET status = ?, retry_count = retry_count + 1, lease_owner = NULL, lease_expires_at = NULL,
         scheduled_at = ?, updated_at = ?
     WHERE task_id = ? AND lease_owner = ?`).run(nextStatus, unixNow() + backoff, unixNow(), taskId, workerId);
    emit(db, taskId, nextStatus);
    return nextStatus;
}
export function addStagingArtifact(db, artifact) {
    const artifactId = randomUUID();
    db.prepare(`INSERT INTO staging_ring (artifact_id, task_id, worker_origin, raw_code_payload, screenshot_path, syntax_valid, diagnostics_log, created_at)
     VALUES (@artifact_id, @task_id, @worker_origin, @raw_code_payload, @screenshot_path, @syntax_valid, @diagnostics_log, @created_at)
     ON CONFLICT(task_id) DO UPDATE SET raw_code_payload = excluded.raw_code_payload, screenshot_path = excluded.screenshot_path, syntax_valid = excluded.syntax_valid, diagnostics_log = excluded.diagnostics_log`).run({
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
export function queueCounts(db) {
    const row = db
        .prepare(`SELECT
         SUM(CASE WHEN status = 'PENDING' THEN 1 ELSE 0 END) AS pending,
         SUM(CASE WHEN status = 'IN_FLIGHT' THEN 1 ELSE 0 END) AS inflight
       FROM task_queue`)
        .get();
    return { pending: row.pending ?? 0, inflight: row.inflight ?? 0 };
}
export function listPendingTasks(db, targetWorker) {
    if (targetWorker) {
        return db
            .prepare(`SELECT * FROM task_queue WHERE status = 'PENDING' AND target_worker = ? ORDER BY created_at ASC`)
            .all(targetWorker);
    }
    return db.prepare(`SELECT * FROM task_queue WHERE status = 'PENDING' ORDER BY created_at ASC`).all();
}
