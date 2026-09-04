from __future__ import annotations

import sqlite3
import time
import uuid
import pytest
from unittest.mock import AsyncMock, patch

from src.worker import checkout, failure, stage_artifact
from src.config import settings


@pytest.fixture
def test_db():
    conn = sqlite3.connect(":memory:")
    conn.execute("PRAGMA foreign_keys = ON")
    conn.execute(
        """
        CREATE TABLE task_queue (
            task_id TEXT PRIMARY KEY,
            parent_task_id TEXT,
            target_worker TEXT NOT NULL,
            operation_mode TEXT NOT NULL,
            target_file TEXT NOT NULL,
            prompt_payload TEXT NOT NULL,
            source_context TEXT,
            status TEXT DEFAULT 'PENDING' NOT NULL,
            retry_count INTEGER DEFAULT 0,
            lease_owner TEXT DEFAULT NULL,
            lease_expires_at INTEGER DEFAULT NULL,
            scheduled_at INTEGER DEFAULT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
        )
        """
    )
    conn.execute(
        """
        CREATE TABLE staging_ring (
            artifact_id TEXT PRIMARY KEY,
            task_id TEXT UNIQUE NOT NULL,
            worker_origin TEXT NOT NULL,
            raw_code_payload TEXT NOT NULL,
            screenshot_path TEXT,
            syntax_valid INTEGER DEFAULT 0,
            diagnostics_log TEXT,
            created_at INTEGER NOT NULL,
            FOREIGN KEY(task_id) REFERENCES task_queue(task_id) ON DELETE CASCADE
        )
        """
    )
    conn.commit()
    yield conn
    conn.close()


def test_stage_artifact_upsert_on_conflict(test_db):
    task_id = "task-123"
    now = int(time.time())
    test_db.execute(
        "INSERT INTO task_queue (task_id, target_worker, operation_mode, target_file, prompt_payload, created_at, updated_at) "
        "VALUES (?, 'LOCAL_VERIFIER', 'GENERATION', 'test.py', '{}', ?, ?)",
        (task_id, now, now),
    )
    test_db.commit()

    # First staging
    stage_artifact(test_db, task_id, "def foo(): pass", None, True)
    row = test_db.execute(
        "SELECT raw_code_payload, syntax_valid FROM staging_ring WHERE task_id = ?", (task_id,)
    ).fetchone()
    assert row[0] == "def foo(): pass"
    assert row[1] == 1

    # Second staging (simulating task retry or update) - should NOT fail with UNIQUE constraint error
    stage_artifact(test_db, task_id, "def foo(): return 42", "/path/to/shot.png", True)
    row2 = test_db.execute(
        "SELECT raw_code_payload, screenshot_path FROM staging_ring WHERE task_id = ?", (task_id,)
    ).fetchone()
    assert row2[0] == "def foo(): return 42"
    assert row2[1] == "/path/to/shot.png"


def test_failure_exponential_backoff_and_exhaustion(test_db):
    task_id = "task-fail-test"
    now = int(time.time())
    test_db.execute(
        "INSERT INTO task_queue (task_id, target_worker, operation_mode, target_file, prompt_payload, status, retry_count, lease_owner, created_at, updated_at) "
        "VALUES (?, 'LOCAL_VERIFIER', 'GENERATION', 'fail.py', '{}', 'IN_FLIGHT', 0, ?, ?, ?)",
        (task_id, settings.worker_id, now, now),
    )
    test_db.commit()

    # Failure 1 -> PENDING with retry_count = 1
    next_st = failure(test_db, task_id)
    assert next_st == "PENDING"
    row = test_db.execute(
        "SELECT status, retry_count, scheduled_at FROM task_queue WHERE task_id = ?", (task_id,)
    ).fetchone()
    assert row[0] == "PENDING"
    assert row[1] == 1
    assert row[2] >= now

    # Simulate retries reaching MAX_RETRIES (3)
    test_db.execute(
        "UPDATE task_queue SET retry_count = 3, status = 'IN_FLIGHT', lease_owner = ? WHERE task_id = ?",
        (settings.worker_id, task_id),
    )
    test_db.commit()

    # Failure at max retries -> FAILED
    next_st2 = failure(test_db, task_id)
    assert next_st2 == "FAILED"
    row2 = test_db.execute("SELECT status FROM task_queue WHERE task_id = ?", (task_id,)).fetchone()
    assert row2[0] == "FAILED"


def test_checkout_leases_pending_task(test_db):
    task_id = "task-checkout"
    now = int(time.time())
    test_db.execute(
        "INSERT INTO task_queue (task_id, target_worker, operation_mode, target_file, prompt_payload, status, created_at, updated_at) "
        "VALUES (?, 'LOCAL_VERIFIER', 'GENERATION', 'test.py', '{}', 'PENDING', ?, ?)",
        (task_id, now, now),
    )
    test_db.commit()

    row = checkout(test_db)
    assert row is not None
    assert row[0] == task_id
    assert row[7] == "IN_FLIGHT"
    assert row[9] == settings.worker_id
