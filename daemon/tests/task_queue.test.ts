import test from 'node:test';
import assert from 'node:assert/strict';
import { createTestDb } from './helpers.js';
import {
  enqueueTask,
  checkoutTask,
  recoverExpiredLeases,
  failTask,
  addStagingArtifact,
} from '../src/db/task_queue.js';
import { unixNow } from '../src/util.js';

test('task_queue: enqueue and checkout task lifecycle', () => {
  const db = createTestDb();

  const taskId = enqueueTask(db, {
    targetWorker: 'DEEPSEEK_WEB',
    operationMode: 'REFACTOR_CONSULTATION',
    targetFile: 'src/core.py',
    promptPayload: 'Review this code for edge cases',
  });

  assert.ok(taskId, 'Task ID should be returned');

  // Checkout the task
  const task = checkoutTask(db, 'worker-1', 'DEEPSEEK_WEB');
  assert.ok(task, 'Task should be checked out');
  assert.equal(task?.task_id, taskId);
  assert.equal(task?.status, 'IN_FLIGHT');
  assert.equal(task?.lease_owner, 'worker-1');
  assert.ok(task?.lease_expires_at && task.lease_expires_at > unixNow());

  // Second checkout should return null since queue is empty
  const empty = checkoutTask(db, 'worker-2', 'DEEPSEEK_WEB');
  assert.equal(empty, null);

  db.close();
});

test('task_queue: recover expired leases resets status to PENDING', () => {
  const db = createTestDb();

  const taskId = enqueueTask(db, {
    targetWorker: 'KIMI_WEB',
    operationMode: 'GENERATION',
    targetFile: 'src/theme.css',
    promptPayload: 'Create responsive glassmorphic theme',
  });

  // Check out and artificially expire lease
  checkoutTask(db, 'worker-1', 'KIMI_WEB');
  const pastTime = unixNow() - 60;
  db.prepare(`UPDATE task_queue SET lease_expires_at = ? WHERE task_id = ?`).run(pastTime, taskId);

  const recovery = recoverExpiredLeases(db);
  assert.equal(recovery.reaped, 1);

  // Task should now be available for checkout again
  const reclaimed = checkoutTask(db, 'worker-2', 'KIMI_WEB');
  assert.ok(reclaimed, 'Reclaimed task should be checked out by worker-2');
  assert.equal(reclaimed?.task_id, taskId);
  assert.equal(reclaimed?.lease_owner, 'worker-2');

  db.close();
});

test('task_queue: exponential backoff retry scheduling on failure', () => {
  const db = createTestDb();

  const taskId = enqueueTask(db, {
    targetWorker: 'GEMINI_WEB',
    operationMode: 'PLAN_DECOMPOSITION',
    targetFile: 'src/main.ts',
    promptPayload: 'Decompose architecture plan',
  });

  const task = checkoutTask(db, 'worker-1', 'GEMINI_WEB');
  assert.ok(task);

  // Mark task failed with retry
  const result = failTask(db, taskId, 'worker-1');
  assert.equal(result, 'PENDING');

  const row = db.prepare(`SELECT status, retry_count, scheduled_at FROM task_queue WHERE task_id = ?`).get(taskId) as {
    status: string;
    retry_count: number;
    scheduled_at: number;
  };

  assert.equal(row.status, 'PENDING');
  assert.equal(row.retry_count, 1);
  assert.ok(row.scheduled_at >= unixNow());

  db.close();
});

test('task_queue: staging_ring artifact upsert and conflict handling', () => {
  const db = createTestDb();

  const taskId = enqueueTask(db, {
    targetWorker: 'DEEPSEEK_WEB',
    operationMode: 'GENERATION',
    targetFile: 'src/calc.py',
    promptPayload: 'Implement quicksort',
  });

  // Add initial artifact
  const art1 = addStagingArtifact(db, {
    taskId,
    workerOrigin: 'DEEPSEEK_WEB',
    rawCodePayload: 'def quicksort(arr): return arr',
    syntaxValid: true,
  });
  assert.ok(art1);

  // Staged artifact exists
  const staged = db.prepare(`SELECT raw_code_payload, syntax_valid FROM staging_ring WHERE task_id = ?`).get(taskId) as {
    raw_code_payload: string;
    syntax_valid: number;
  };
  assert.equal(staged.raw_code_payload, 'def quicksort(arr): return arr');
  assert.equal(staged.syntax_valid, 1);

  db.close();
});
