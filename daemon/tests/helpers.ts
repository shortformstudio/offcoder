import Database from 'better-sqlite3';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

export function createTestDb(): Database.Database {
  const db = new Database(':memory:');
  db.pragma('journal_mode = WAL');
  db.pragma('foreign_keys = ON');
  const schemaPath = fileURLToPath(new URL('../src/db/schema.sql', import.meta.url));
  db.exec(readFileSync(schemaPath, 'utf8'));
  const queueCols = db.pragma('table_info(task_queue)') as Array<{ name: string }>;
  if (!queueCols.some((c) => c.name === 'scheduled_at')) {
    db.exec('ALTER TABLE task_queue ADD COLUMN scheduled_at INTEGER');
  }
  return db;
}
