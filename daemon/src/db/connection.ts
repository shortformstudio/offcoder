import Database from 'better-sqlite3';
import { mkdirSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { ORCH_ROOT, WORKSPACE_ROOT, SCREENSHOT_ROOT } from '../config.js';

let instance: Database.Database | null = null;

export function getDb(): Database.Database {
  if (instance) return instance;
  mkdirSync(ORCH_ROOT, { recursive: true });
  mkdirSync(WORKSPACE_ROOT, { recursive: true });
  mkdirSync(SCREENSHOT_ROOT, { recursive: true });
  instance = new Database(`${ORCH_ROOT}/state.db`);
  instance.pragma('journal_mode = WAL');
  instance.pragma('busy_timeout = 5000');
  instance.pragma('foreign_keys = ON');
  const schemaPath = fileURLToPath(new URL('./schema.sql', import.meta.url));
  instance.exec(readFileSync(schemaPath, 'utf8'));
  const queueCols = instance.pragma('table_info(task_queue)') as Array<{ name: string }>;
  if (!queueCols.some((c) => c.name === 'scheduled_at')) {
    instance.exec('ALTER TABLE task_queue ADD COLUMN scheduled_at INTEGER');
  }
  return instance;
}
