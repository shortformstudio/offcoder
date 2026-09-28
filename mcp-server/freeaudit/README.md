# freeaudit

Local/free-model **5-pass** audit + fix engine. Trigger with **`/freeaudit`**.

Mirrors `webaudit`'s strict versioning but uses **any free model on opencode** (qwythos / mimo via `http://127.0.0.1:8000/v1/chat/completions`). The receiving agent initiates a **CLI terminal** per pass, constructs the audit directive, and provides the code; the MCP runs 5 loops, verifies each version, and returns the final artifact at `v5`.

## Strict versioning

Original code is **never mutated**. Fresh clone:

```
~/.config/freeaudit/audits/<project>_<timestamp>_<rand>/
  v0_original/          # immutable baseline
  v1/ v2/ v3/ v4/ v5/   # each pass — v5 is final artifact
  reports/pass1.md ... pass5.md
  terminal_pass1.log ... terminal_pass5.log  # CLI terminal transcript per pass
  FINAL_ARTIFACT.md
```

Each pass verified with `python3 -m py_compile` / `npx tsc --noEmit` / `swiftc -parse` / etc. Each loop delivers **both** report and fix in one turn.

## Tools

| tool | what it does |
|---|---|
| `freeaudit` | 5-pass audit: clone → 5× local model → verify → final artifact |
| `freeaudit_list` | List past audits, audit_root |
| `freeaudit_prompts` | Preview the audit+fix prompt verbage |

## Trigger

```
/freeaudit target_path: src/api.ts project_name: api-hardening
/freeaudit target_path: src/auth.py audit_focus: security
/freeaudit code: "<raw code>" target_file: src/foo.py model: mimo-v2.5-pro
```

Args:

- `target_path` (preferred): file or directory — read and cloned
- `code` + `target_file`: raw code alternative
- `project_name`, `audit_focus`, `model` (override, default `qwythos/qwythos`), `model_url` (override dispatcher URL)

Returns JSON with `audit_id`, `audit_dir`, `original_clone`, `final_artifact` (v5), `final_report`, per-pass `reports`/`versions`/`terminal_log`/`verification`.

## CLI terminal per pass

For each of the 5 passes the MCP:
1. Initiates a CLI terminal context (`terminal_passN.log`)
2. Constructs the audit directive (findings + fix together) for the model
3. Provides the current code version
4. Calls the local model via OpenAI-compatible HTTP
5. Extracts the fixed code block, writes `vN`, verifies

This matches the spec: the agent initiates a CLI terminal, constructs the directive, provides the code.

## Local models

Default: `http://127.0.0.1:8000/v1/chat/completions` with `qwythos/qwythos`, fallbacks `mimo-v2.5-pro`, `mimo-v2.5`. Override via `FREEAUDIT_MODEL`, `FREEAUDIT_MODEL_URL`, or per-call `model`/`model_url`.

Ensure dispatcher is running:

```bash
# from inference offload
./scripts/chrome_launch.sh
cd dispatcher && uvicorn src.main:app --port 8000
# or modular's dispatcher
```

## Install

```bash
cd ~/Documents/modular/mcp-server/freeaudit
npm install
node --check index.js
```

Registered in `~/.config/opencode/opencode.jsonc` as `freeaudit`.

Restart opencode after editing config.

## Offload mirror

Same server at `~/Documents/DEVELOPMENT/WILD CARD/inference offload/mcp-server/freeaudit/` — keep both in sync.
