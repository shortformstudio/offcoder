#!/usr/bin/env python3
"""
Offcoder Preload Context Builder.
Assembles mission (state.db), totem memory (local records), and indexing data
into a single compact markdown file that every agent turn can pre-append.

Usage:
  build_preload_context.py [--totem-port 9090] [--state-db PATH] [--out PATH]
"""

import argparse
import json
import os
import socket
import sqlite3
import time
from datetime import datetime, timezone
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent

DEFAULT_STATE_DB = Path.home() / ".local_orchestrator" / "state.db"
DEFAULT_OUT = Path.home() / ".offcoder" / "preload" / "context.md"
DEFAULT_WORKSPACES = Path.home() / "code" / "qwythos-agent"

MAX_QUEUE_ROWS = 20
MAX_JOURNAL_ROWS = 15
MAX_FACTS_ROWS = 25
MAX_MEMORY_CHARS = 6000


def iso(ts) -> str:
    try:
        return datetime.fromtimestamp(float(ts), tz=timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    except Exception:
        return "unknown"


def read_totem_memory(totem_port: int) -> str:
    records_dir = PROJECT_ROOT / f"local records - {totem_port}"
    memory_md = records_dir / "MEMORY.md"
    if memory_md.exists():
        text = memory_md.read_text(encoding="utf-8", errors="ignore").strip()
        return text[:MAX_MEMORY_CHARS]
    return ""


def totem_counts(totem_port: int) -> dict:
    bio = PROJECT_ROOT / f"local records - {totem_port}" / "biodynamic"
    counts = {}
    facts_path = bio / "facts.jsonl"
    if facts_path.exists():
        counts["facts"] = sum(1 for line in facts_path.read_text(encoding="utf-8", errors="ignore").splitlines() if line.strip())
    for name in ("working_knowledge", "wisdom", "legacy"):
        path = bio / f"{name}.json"
        try:
            counts[name] = len(json.loads(path.read_text(encoding="utf-8")))
        except Exception:
            counts[name] = 0
    return counts


def recent_facts(totem_port: int, limit: int = MAX_FACTS_ROWS) -> list:
    facts_path = PROJECT_ROOT / f"local records - {totem_port}" / "biodynamic" / "facts.jsonl"
    if not facts_path.exists():
        return []
    lines = [l for l in facts_path.read_text(encoding="utf-8", errors="ignore").splitlines() if l.strip()]
    facts = []
    for line in lines[-limit:]:
        try:
            facts.append(json.loads(line))
        except Exception:
            continue
    return facts


def build_state_sections(state_db: Path) -> list:
    sections = []
    if not state_db.exists():
        sections.append("## 1. MISSION STATE\nstate.db not found at " + str(state_db))
        return sections

    conn = sqlite3.connect(f"file:{state_db}?mode=ro", uri=True)
    conn.row_factory = sqlite3.Row
    try:
        cur = conn.cursor()

        # Mission queue
        rows = cur.execute(
            "SELECT task_id, target_worker, operation_mode, target_file, status, prompt_payload, created_at "
            "FROM task_queue ORDER BY created_at DESC LIMIT ?", (MAX_QUEUE_ROWS,)
        ).fetchall()
        queue_lines = []
        for r in rows:
            project = ""
            try:
                payload = json.loads(r["prompt_payload"] or "{}")
                project = payload.get("projectName", "")
            except Exception:
                pass
            label = f"{project} → {r['target_file']}" if project else r["target_file"]
            queue_lines.append(f"- [{r['status']}] {r['operation_mode']} · {r['target_worker']} · {label} (created {iso(r['created_at'])})")
        sections.append("## 1. MISSION QUEUE (task_queue)\n" + ("\n".join(queue_lines) if queue_lines else "- empty"))

        # Session journal
        rows = cur.execute(
            "SELECT entry_type, target_module, summary, created_at FROM session_journal "
            "ORDER BY journal_id DESC LIMIT ?", (MAX_JOURNAL_ROWS,)
        ).fetchall()
        journal_lines = [f"- {iso(r['created_at'])} [{r['entry_type']}] {r['target_module']}: {r['summary']}" for r in rows]
        sections.append("## 2. SESSION JOURNAL (recent)\n" + ("\n".join(journal_lines) if journal_lines else "- empty"))

        # Repo registry + index
        repos = cur.execute("SELECT repo_id, local_path, default_branch, indexed_tree, last_synced FROM repo_registry").fetchall()
        repo_lines = []
        for r in repos:
            indexed_files = cur.execute("SELECT COUNT(*) FROM context_nodes WHERE repo_id = ?", (r["repo_id"],)).fetchone()[0]
            tree_files = 0
            try:
                tree_files = len(json.loads(r["indexed_tree"] or "[]"))
            except Exception:
                pass
            repo_lines.append(
                f"- {r['repo_id']} @ {r['local_path']} (branch {r['default_branch']}) · indexed nodes: {indexed_files} · tree entries: {tree_files} · last synced {iso(r['last_synced'])}"
            )
        context_total = cur.execute("SELECT COUNT(*) FROM context_nodes").fetchone()[0]
        sections.append(
            "## 3. REPOSITORY INDEX (cache)\n"
            + ("\n".join(repo_lines) if repo_lines else "- no repositories indexed yet")
            + f"\n- total indexed context nodes: {context_total}"
        )
    finally:
        conn.close()
    return sections


def build_workspace_section(workspaces: Path) -> str:
    projects_dir = workspaces / "projects"
    lines = []
    if projects_dir.exists():
        for entry in sorted(projects_dir.iterdir()):
            if entry.is_dir():
                try:
                    file_count = sum(1 for _ in entry.rglob("*") if _.is_file())
                except Exception:
                    file_count = 0
                lines.append(f"- {entry.name} ({file_count} files) → {entry}")
    if not lines and workspaces.exists():
        lines.append(f"- workspace root: {workspaces}")
    return "## 4. WORKSPACES ON DISK\n" + ("\n".join(lines) if lines else "- none found")


def build_preload(totem_port: int, state_db: Path, workspaces: Path) -> str:
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    header = (
        "# OFFCODER PRELOADED CONTEXT — mission, memory, index\n"
        f"Generated: {now} | Host: {socket.gethostname()} | Totem: totem-{totem_port}\n"
        f"State DB: {state_db}\n"
        f"Totem records: {PROJECT_ROOT / f'local records - {totem_port}'}"
    )

    sections = [header]
    sections.extend(build_state_sections(state_db))
    sections.append(build_workspace_section(workspaces))

    memory = read_totem_memory(totem_port)
    counts = totem_counts(totem_port)
    count_line = " | ".join(f"{k}: {v}" for k, v in counts.items()) if counts else "no biodynamic ledger yet"
    sections.append("## 5. TOTEM MEMORY LEDGER (port {})\n{}\n\nLedger counts: {}".format(totem_port, memory or "(empty)", count_line))

    facts = recent_facts(totem_port)
    if facts:
        fact_lines = [f"- [{f.get('domain', '?')}] {f.get('content', '')[:180]}" for f in facts]
        sections.append("## 6. RECENT VERIFIED FACTS\n" + "\n".join(fact_lines))

    return "\n\n".join(sections) + "\n"


def main():
    parser = argparse.ArgumentParser(description="Build the Offcoder preload context file")
    parser.add_argument("--totem-port", type=int, default=9090)
    parser.add_argument("--state-db", type=str, default=str(DEFAULT_STATE_DB))
    parser.add_argument("--workspaces", type=str, default=str(DEFAULT_WORKSPACES))
    parser.add_argument("--out", type=str, default=str(DEFAULT_OUT))
    args = parser.parse_args()

    context = build_preload(args.totem_port, Path(args.state_db), Path(args.workspaces))
    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(context, encoding="utf-8")
    print(f"[preload] wrote {len(context)} chars -> {out_path}")


if __name__ == "__main__":
    main()
