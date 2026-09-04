import { createRequire } from 'node:module';
import path from 'node:path';

const require = createRequire(new URL('../../daemon/package.json', import.meta.url));
const Database = require('better-sqlite3');

const mode = process.env.MODE ?? 'happy';
const root = process.env.ORCH_ROOT ?? process.env.HOME;

function jlog(level, code, msg, extra = {}) {
  console.log(JSON.stringify({ domain: 'faucet', level, code, msg, ...extra }));
}

const db = new Database(path.join(root, 'state.db'), { timeout: 5000 });
db.pragma('busy_timeout = 5000');

let seat = 0;

async function loop() {
  try {
    const now = Math.floor(Date.now() / 1000);
    db.exec('BEGIN IMMEDIATE');
    db.prepare(
      "UPDATE task_queue SET status='PENDING', lease_owner=NULL, lease_expires_at=NULL, scheduled_at=unixepoch() WHERE status='IN_FLIGHT' AND lease_expires_at < ?"
    ).run(now);
    const row = db
      .prepare(
        `UPDATE task_queue SET status='IN_FLIGHT', lease_owner=@owner, lease_expires_at=@expires, scheduled_at=NULL, updated_at=@now
         WHERE task_id=(SELECT task_id FROM task_queue WHERE status='PENDING' AND target_worker='LOCAL_VERIFIER'
           AND (scheduled_at IS NULL OR scheduled_at <= @now) ORDER BY created_at ASC LIMIT 1)
         RETURNING *`
      )
      .get({ owner: `faucet-${mode}-${seat++}`, expires: now + 120, now });
    db.exec('COMMIT');
    if (!row) {
      setTimeout(() => void loop(), 300);
      return;
    }
    jlog('info', 'taken', row.target_file, { taskId: row.task_id });
    if (mode === 'stall') {
      db.prepare(
        "UPDATE task_queue SET lease_expires_at = ? WHERE task_id = ? AND status = 'IN_FLIGHT'"
      ).run(now - 10, row.task_id);
      jlog('info', 'stalled', row.task_id, { taskId: row.task_id });
    } else {
      await new Promise((r) => setTimeout(r, 250));
      db.prepare(
        'INSERT INTO staging_ring (artifact_id, task_id, worker_origin, raw_code_payload, syntax_valid, created_at) VALUES (?,?,?,?,?,?)'
      ).run(String(Math.random()), row.task_id, 'faucet', '// faucet artifact', 1, now);
      db.prepare(
        "UPDATE task_queue SET status='STAGED', lease_owner=NULL, lease_expires_at=NULL, updated_at=? WHERE task_id=? AND lease_owner=?"
      ).run(now, row.task_id, row.lease_owner);
      jlog('info', 'staged', row.target_file, { taskId: row.task_id });
    }
    setTimeout(() => void loop(), 300);
  } catch (error) {
    jlog('error', 'faucet_crash', String(error));
    try {
      db.exec('ROLLBACK');
    } catch {
      /* noop */
    }
    setTimeout(() => void loop(), 1000);
  }
}

if (mode === 'stall') {
  void loop();
} else {
  void loop();
}
setInterval(() => {}, 1 << 30);
