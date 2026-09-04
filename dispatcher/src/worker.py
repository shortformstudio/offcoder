from __future__ import annotations

import json
import os
import sqlite3
import sys
import time
import uuid
from typing import Any

from .config import settings
from .model_backend import chat_completion
from .vision import normalize_messages

LEASE_SECONDS = int(os.environ.get("ORCH_LEASE_SECONDS", "180"))
MAX_RETRIES = 3


def jlog(level: str, code: str, msg: str, **extra: Any) -> None:
    payload = {"domain": "dispatcher", "level": level, "code": code, "msg": msg, **extra}
    line = json.dumps(payload)
    if level in ("error", "critical"):
        print(line, file=sys.stderr, flush=True)
    else:
        print(line, flush=True)


def open_conn() -> sqlite3.Connection:
    conn = sqlite3.connect(settings.orch_root / "state.db", timeout=5.0)
    conn.execute("PRAGMA busy_timeout = 5000")
    conn.execute("PRAGMA foreign_keys = ON")
    return conn


def check_schema(conn: sqlite3.Connection) -> bool:
    try:
        conn.execute("SELECT COUNT(*) FROM task_queue")
        return True
    except sqlite3.OperationalError:
        return False


def checkout(conn: sqlite3.Connection) -> sqlite3.Row | None:
    for attempt in range(5):
        try:
            conn.execute("BEGIN IMMEDIATE")
            now = int(time.time())
            conn.execute(
                "UPDATE task_queue SET status = 'PENDING', lease_owner = NULL, lease_expires_at = NULL "
                "WHERE status = 'IN_FLIGHT' AND lease_expires_at < ?",
                (now,),
            )
            row = conn.execute(
                "UPDATE task_queue SET status = 'IN_FLIGHT', lease_owner = ?, "
                "lease_expires_at = ?, updated_at = ? "
                "WHERE task_id = (SELECT task_id FROM task_queue "
                "WHERE status = 'PENDING' AND target_worker = 'LOCAL_VERIFIER' "
                "AND (scheduled_at IS NULL OR scheduled_at <= ?) "
                "ORDER BY created_at ASC LIMIT 1) RETURNING *",
                (settings.worker_id, now + LEASE_SECONDS, now, now),
            ).fetchone()
            conn.commit()
            return row
        except sqlite3.OperationalError as error:
            conn.rollback()
            if "locked" not in str(error) and "busy" not in str(error):
                raise
            jlog("warning", "db_busy", f"checkout wait {attempt + 1}: {error}")
            time.sleep(0.25 * (attempt + 1))
    raise RuntimeError("checkout gave up after contention")


def failure(conn: sqlite3.Connection, task_id: str) -> str:
    row = conn.execute(
        "SELECT retry_count FROM task_queue WHERE task_id = ? AND lease_owner = ?",
        (task_id, settings.worker_id),
    ).fetchone()
    if row is None:
        return "FAILED"
    will_retry = row[0] < MAX_RETRIES
    next_status = "PENDING" if will_retry else "FAILED"
    backoff = (2 ** min(row[0] + 1, 6)) * 5
    conn.execute(
        "UPDATE task_queue SET status = ?, retry_count = retry_count + 1, "
        "lease_owner = NULL, lease_expires_at = NULL, scheduled_at = ?, updated_at = ? "
        "WHERE task_id = ? AND lease_owner = ?",
        (next_status, int(time.time()) + backoff, int(time.time()), task_id, settings.worker_id),
    )
    conn.commit()
    return next_status


import asyncio


def stage_artifact(conn: sqlite3.Connection, task_id: str, code: str, screenshot: str | None, valid: bool) -> None:
    conn.execute(
        "INSERT INTO staging_ring (artifact_id, task_id, worker_origin, raw_code_payload, screenshot_path, syntax_valid, created_at) "
        "VALUES (?, ?, ?, ?, ?, ?, ?) "
        "ON CONFLICT(task_id) DO UPDATE SET "
        "raw_code_payload = excluded.raw_code_payload, "
        "screenshot_path = excluded.screenshot_path, "
        "syntax_valid = excluded.syntax_valid",
        (
            str(uuid.uuid4()),
            task_id,
            settings.worker_id,
            code,
            screenshot,
            1 if valid else 0,
            int(time.time()),
        ),
    )
    conn.commit()


def run_forever() -> None:
    conn = open_conn()
    jlog("info", "worker_boot", f"polling task_queue as {settings.worker_id} → {settings.model}")
    consecutive_failures = 0
    schema_verified = False
    while True:
        try:
            if not schema_verified:
                if not check_schema(conn):
                    conn.close()
                    jlog("warning", "schema_missing", "state.db has no task_queue yet — waiting for daemon")
                    time.sleep(5)
                    conn = open_conn()
                    continue
                schema_verified = True
            task = checkout(conn)
        except Exception as error:
            jlog("critical", "checkout_crash", str(error))
            schema_verified = False
            time.sleep(5)
            try:
                conn = open_conn()
            except Exception:
                continue
            continue
        if task is None:
            consecutive_failures = 0
            time.sleep(2.0)
            continue
        task_id = task[0]
        jlog("info", "task_taken", "taken", task_id=task_id, mode=task[3], target=task[4])
        try:
            payload = json.loads(task[5] or "{}")
            messages = normalize_messages([{"role": "user", "content": json.dumps(payload, indent=2)}])
            result = asyncio.run(chat_completion(messages))
            content = result.get("text") or result.get("choices", [{}])[0].get("message", {}).get("content", "")
            stage_artifact(conn, task_id, str(content), None, len(content.strip()) > 0)
            conn.execute(
                "UPDATE task_queue SET status = 'STAGED', lease_owner = NULL, lease_expires_at = NULL, updated_at = ? "
                "WHERE task_id = ? AND lease_owner = ?",
                (int(time.time()), task_id, settings.worker_id),
            )
            conn.commit()
            consecutive_failures = 0
            jlog("info", "task_staged", "staged", task_id=task_id)
        except Exception as error:
            jlog("error", "task_failed", str(error), task_id=task_id)
            conn.rollback()
            failure(conn, task_id)
            consecutive_failures += 1
            if consecutive_failures >= 5:
                jlog("warning", "worker_cooldown", "5 consecutive failures — cooling down 60s")
                time.sleep(60)
                consecutive_failures = 0


if __name__ == "__main__":
    run_forever()
