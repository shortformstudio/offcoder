import test from 'node:test';
import assert from 'node:assert/strict';
import { createTestDb } from './helpers.js';
import { createFreshProject, projectKey } from '../src/db/projects.js';

test('projects: projectKey is deterministic based on name and plan sha256', () => {
  const k1 = projectKey('my-project', 'Build a production web app');
  const k2 = projectKey('my-project', 'Build a production web app');
  const k3 = projectKey('my-project', 'Different plan');

  assert.equal(k1, k2);
  assert.notEqual(k1, k3);
  assert.match(k1, /^FRESH:my-project:[a-f0-9]{12}$/);
});

test('projects: sanitizes invalid project names and rejects directory traversal', () => {
  const db = createTestDb();

  // Traversal attack
  assert.throws(() => {
    createFreshProject(db, '../../evil-path', 'some plan');
  }, /invalid project name/);

  // Illegal characters
  assert.throws(() => {
    createFreshProject(db, 'project with spaces', 'some plan');
  }, /invalid project name/);

  assert.throws(() => {
    createFreshProject(db, 'project/with/slashes', 'some plan');
  }, /invalid project name/);

  assert.throws(() => {
    createFreshProject(db, 'project$evil', 'some plan');
  }, /invalid project name/);

  // Valid project names should succeed
  const validResult = createFreshProject(db, 'valid-project_name.1', 'Plan content');
  assert.ok(validResult.sessionId);
  assert.ok(validResult.planTaskId);
  assert.equal(validResult.reused, false);

  db.close();
});

test('projects: plan chunking at 4,000 characters with diagnostic pointers', () => {
  const db = createTestDb();

  // Create a plan longer than 4,000 characters
  const longParagraph = 'This is a long engineering specification detailing system architecture. '.repeat(80); // ~5,760 chars
  assert.ok(longParagraph.length > 4000);

  const result = createFreshProject(db, 'large-spec-app', longParagraph);
  assert.ok(result.planTaskId);

  // Verify task prompt payload preserves chunk notification and truncation
  const task = db
    .prepare(`SELECT prompt_payload, source_context FROM task_queue WHERE task_id = ?`)
    .get(result.planTaskId) as { prompt_payload: string; source_context: string };

  const parsed = JSON.parse(task.prompt_payload);
  assert.equal(parsed.chunked, true);
  assert.equal(parsed.totalLength, longParagraph.length);
  assert.ok(parsed.masterPlan.includes('[PLAN_CHUNKED: remaining'));
  assert.ok(task.source_context.startsWith('PLAN_REF:sha256:'));

  // Verify full plan preserved in staging_ring diagnostics_log
  const staged = db
    .prepare(`SELECT diagnostics_log FROM staging_ring WHERE task_id = ?`)
    .get(result.planTaskId) as { diagnostics_log: string };
  assert.equal(staged.diagnostics_log, longParagraph);

  db.close();
});

test('projects: deduplication reuses existing project if identical key is submitted', () => {
  const db = createTestDb();

  const plan = 'Unique master plan for idempotency test';
  const first = createFreshProject(db, 'idempotent-app', plan);
  assert.equal(first.reused, false);

  const second = createFreshProject(db, 'idempotent-app', plan);
  assert.equal(second.reused, true);
  assert.equal(second.planTaskId, first.planTaskId);

  db.close();
});
