# architecture — distributed orchestrator & macos harness (v3)

## topology

```
┌──────────────────┐   ws 7171   ┌────────────────────┐   cdp 9222   ┌────────────────┐
│  cockpit (swift) │◀────────────▶│ daemon (node/ts)   │◀────────────▶│ chrome (gemini │
│  bento deck      │  frames      │ sqlite + brokers   │  screencast  │  / deepseek)   │
└──────┬───────────┘              └─────────┬──────────┘  payloads   └────────────────┘
       │                                   │
       │                             sqlite │ ~/.local_orchestrator/state.db
       │                            + json  │
       ▼                                   ▼
┌──────────────────┐   http 8000    ┌────────────────────┐
│ dispatcher       │◀───────────────▶│ (optional) ollama │
│ python/fastapi   │  openai compat  │ text / vlm weights │
└──────────────────┘                 └────────────────────┘
```

three moving parts, zero shared mutable state beyond the sqlite file and the browser.

## domain 1 — dispatcher (lan node)

pure model gateway. responsibilities:

- serve `/v1/chat/completions` openai-compatible, proxy into `ORCH_LLM_BASE`
- enforce the **dual-mode vision gate**: `vision.py` strips `image_url` parts for text-only models and merges daemon-provided layout maps
- `worker.py` consumes `LOCAL_VERIFIER` tasks: atomic lease checkout (same sqlite file), calls the model, writes `staging_ring` + marks `STAGED`/`FAILED`

## domain 2 — daemon (automation broker)

- `db/connection.ts` — sqlite bootstrap (wal, busy_timeout 5000, foreign keys on), schema at `db/schema.sql`
- `db/task_queue.ts` — atomic checkout under `BEGIN IMMEDIATE`; expired leases reset before checkout; heartbeat renews `lease_expires_at`; `STAGED`/`FAILED` guards; retries cap `MAX_RETRIES`
- `db/journal.ts` — `session_journal` writes (optional entries trivially)
- `db/projects.ts` — fresh project bootstrap: `PLAN_INIT` journal + `PLAN_DECOMPOSITION` seed task
- `github_sync.ts` — org indexer (`gh repo list` with unauthenticated REST fallback), clone/pull into `workspaces/`, sparse `git ls-files` tree (gitignore-respect), sha-256 per file, tree-sitter signature extraction with regex fallback, writes `context_nodes` + `repo_registry.indexed_tree`
- `browser_broker.ts` — cdp driver: page resolution for gemini/deepseek domains, dom prompt dispatch, stop-control polling, screenshots, code scraping, layout map extraction, and `Page.startScreencast` streaming with `screencastFrameAck` + auto re-attach if the stream goes silent
- `vision_routing.ts` — composes the ingest payload for each mode: raw frame base64 for vlms, `scrapedText + renderLayoutMap(blocks)` for text-only
- `ipc.ts` — websocket 7171: server→cockpit events (`screencast_frame`, `journal`, `status`, `repo_registered`), cockpit→daemon commands (`org_repos`, `pull_repo`, `fresh_project`)

## domain 3 — cockpit (native deck)

- spm executable, `swift run`; optional `xcodegen` `project.yml` for a bundled `.app`
- window conventions: `.windowStyle(.hiddenTitleBar)`, `.windowToolbarStyle(.unified)`, `NSApplicationDelegateAdaptor` sets `isMovableByWindowBackground` + `titlebarAppearsTransparent` on all windows at launch and on reactivation — the pinned-titlebar glitch is prevented
- the viewport bay is an `NSImageView` fed by decoded websocket frames — it never opens a `WKWebView` against 9222, so focus and input remain with the live session

## task lifecycle

```
PENDING ──checkout (lease 180s)──▶ IN_FLIGHT ──heartbeat──▶ IN_FLIGHT
   ▲                                  │                        │
   │                                  │ done: code+screenshot   │ stalled > 180s
   └──retry (≤3)── FAILED ◀───────────┴──────▶ STAGED ──vlm/text validate──▶ VERIFIED
```

lease expiry is checked transactionally at every checkout, so a dead web session cannot hold the ring hostage; consumers reattach the browser after expiry.

## event contract (daemon → cockpit, ws 7171)

```json
{"type": "screencast_frame", "data": "<base64 jpeg>"}
{"type": "journal", "entryType": "PLAN_INIT", "target": "mesh-router", "summary": "…"}
{"type": "status", "key": "cdp", "state": "CONNECTED", "detail": "127.0.0.1:9222"}
{"type": "repo_registered", "repoId": "shortformstudio/engine"}
```

## command contract (cockpit → daemon)

```json
{"type": "org_repos"}
{"type": "pull_repo", "repoId": "shortformstudio/engine"}
{"type": "fresh_project", "name": "mesh-router", "masterPlan": "…"}
```
