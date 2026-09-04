import type { Database } from 'better-sqlite3';
import { unixNow } from '../util.js';

export type EntryType = 'ARCH_DECISION' | 'LINT_FAILURE' | 'PATCH_SUCCESS' | 'CONSULTATION_NOTE' | 'PLAN_INIT';

export function addJournal(db: Database, sessionId: string, entryType: EntryType, targetModule: string, summary: string): number {
  const capped = summary.trim().split(/\s+/).slice(0, 30).join(' ');
  const res = db
    .prepare(
      `INSERT INTO session_journal (session_id, entry_type, target_module, summary, created_at)
       VALUES (?, ?, ?, ?, ?)`
    )
    .run(sessionId, entryType, targetModule, capped, unixNow());
  return Number(res.lastInsertRowid);
}

export function listJournal(db: Database, sessionId: string, limit = 100): Array<Record<string, unknown>> {
  return db
    .prepare(
      `SELECT journal_id, entry_type AS entryType, target_module AS targetModule, summary, created_at
       FROM session_journal WHERE session_id = ?
       ORDER BY created_at DESC LIMIT ?`
    )
    .all(sessionId, limit) as Array<Record<string, unknown>>;
}
