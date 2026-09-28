# webaudit

DeepSeek Web **3-pass** audit + fix engine. Trigger with **`/webaudit`**.

You provide a codebase or component file to **DeepSeek Web** (stealth browser); the MCP performs a full serious audit and applies **all fixes in one sweep per pass**, then repeats 2 more times for **3 total passes**. Final artifact is ready for agent review.

## Strict versioning

Original code is **never mutated**. A fresh clone is created:

```
~/.config/webaudit/audits/<project>_<timestamp>_<rand>/
  v0_original/          # immutable baseline (original clone)
  v1/                   # after pass 1
  v2/                   # after pass 2
  v3/                   # final artifact — review this
  reports/pass1.md      # findings report per pass
  reports/pass2.md
  reports/pass3.md
  FINAL_ARTIFACT.md     # summary with version map + final code
```

Each pass is verified with `python3 -m py_compile` / `npx tsc --noEmit` / `swiftc -parse` / etc.

## Each loop: report + fix in one turn

Prompt requires DeepSeek to output **both** a findings report (P0-P3 with FILE:LINE) **and** the complete fixed file in a single fenced code block. No placeholders.

## Tools

| tool | spends | what it does |
|---|---|---|
| `webaudit` | 3 consults | 3-pass audit: clone → 3× DeepSeek → verify → final artifact |
| `webaudit_check` | free | Re-poll a `generating` DeepSeek turn (pass `conversation_id`) |
| `webaudit_list` | free | List past audits, audit_root, DeepSeek conversations + budget |
| `webaudit_prompts` | free | Preview the exact audit+fix prompt verbage |

## Trigger

```
/webaudit target_path: src/auth.py audit_focus: security
/webaudit target_path: /absolute/path/to/component project_name: auth-hardening
/webaudit code: "<raw code>" target_file: src/foo.py
```

Args:

- `target_path` (preferred): absolute or repo-relative file or directory — read and cloned
- `code` + `target_file`: raw code alternative
- `project_name`, `audit_focus` (security|performance|correctness|full), `conversation_id` (reuse DeepSeek thread), `max_wait_polls`

Returns JSON with `audit_id`, `audit_dir`, `original_clone`, `final_artifact`, `final_report`, per-pass `reports`/`versions`/`verification`.

## DeepSeek Web only

Uses the same stealth browser as `consult` (`~/.config/consult/profiles/deepseek`). First `webaudit` opens a visible Chrome window if not logged in; sign in once, session persists, retry.

Each pass consumes 1 consult budget (3 total). Check `webaudit_list` for remaining budget. `CONSULT_MAX_CONSULTS` / `CONSULT_MAX_CONVERSATIONS` env still apply.

## Install

```bash
cd ~/Documents/modular/mcp-server/webaudit
npm install
node --check index.js
```

Registered in `~/.config/opencode/opencode.jsonc` as `webaudit` (see `opencode.jsonc`).

Restart opencode after editing config.

## Offload mirror

Same server at `~/Documents/DEVELOPMENT/WILD CARD/inference offload/mcp-server/webaudit/` — keep both in sync when updating prompts or verification.
