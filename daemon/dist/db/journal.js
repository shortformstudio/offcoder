import { unixNow } from '../util.js';
export function addJournal(db, sessionId, entryType, targetModule, summary) {
    const capped = summary.trim().split(/\s+/).slice(0, 30).join(' ');
    const res = db
        .prepare(`INSERT INTO session_journal (session_id, entry_type, target_module, summary, created_at)
       VALUES (?, ?, ?, ?, ?)`)
        .run(sessionId, entryType, targetModule, capped, unixNow());
    return Number(res.lastInsertRowid);
}
export function listJournal(db, sessionId, limit = 100) {
    return db
        .prepare(`SELECT journal_id, entry_type AS entryType, target_module AS targetModule, summary, created_at
       FROM session_journal WHERE session_id = ?
       ORDER BY created_at DESC LIMIT ?`)
        .all(sessionId, limit);
}
