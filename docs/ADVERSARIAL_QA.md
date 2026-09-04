# adversarial qa — 20 unconventional paths & their guardrails

audience: speedrunners, malicious actors, distracted users, elderly users. every path below is reproducible against the current scaffold (`daemon/src/*`, `cockpit/Sources/*`, `dispatcher/src/*`).

## a. datapath / browser

**1. stale-scrape rewind** — `browser_broker.executeTask` scrapes `els[els.length - 1]` of `.message-content`/`.ds-message-body`. a reused page still shows the previous turn: the worker stages yesterday's answer as today's artifact.
guardrail: stamp the prompt into the input but also write a turn-marker (e.g. append `\n\n§TURN \`<taskId>\``) and scrape forward from the marker; assert `scraped.length > 0` and `!scraped.includes(prompt)` else `failTask`.

**2. enter key double-fire** — `page.keyboard.press('Enter')` fires even when the input already contains the prompt from a stalled prior attempt; the model receives the task twice and the stop-indicator wait resolves early.
guardrail: before dispatch, `page.evaluate` the input value; require `el.value.includes(marker)`; if a duplicate prompt exists, clear `el.value = ''` and focus first. this makes executeTask idempotent.

**3. selector aliasing** — `waitForSelector('textarea, #chat-input')` finds the *first* textarea — on a logged-out wall that is the email field.
guardrail: probe candidates and require the focused-zone check `document.activeElement === el` after focus; bail with `failTask(reason='auth_gate')` and broadcast a `status{key:'browser', state:'MANUAL'}` event so the cockpit surfaces "sign in, then resume".

**4. cloudflare / recaptcha gate = silent 3-minute CPU burn** — `waitForFunction` polling every 500ms for 180s while a challenge page sits.
guardrail: cap 45s; on timeout check `if (page.mainFrame().url()` / body text contains `challenge|captcha|access denied`) → `detachScreencast()` (restart signal) + fail with `AUTH_GATE`, never 180s. lease expiry stays the backstop, not the primary detector.

**5. tab-spawn storm** — `resolvePage` creates a new tab for every missing page; add a no-tab-cap. a crashed auth flow spawns gemini tabs on each task.
guardrail: singleton map `pageByWorker` — never create while a `connected` orb exists; cap daemon-opened tabs to 2; reuse.

**6. browser-flag fingerprint ignore** — `puppeteer.connect` to whatever chrome answers on 9222, arguably the *user's own* profile: focus theft + task text visible.
guardrail: on connect, read `/json/version` `userDataDir` and reject connection unless it equals `~/.chrome_automation_profile` (config constant) → broadcast `status CDP MISMATCH`.

**7. unicode / RTL prompt melt** — `dispatchEvent(new Event('input'))` with multi-part prompts (markdown, RTL, emoji) yields incomplete insertion in `contenteditable` (gemini's `.ql-editor`): appended `innerText` replaces trailing void.
guardrail: use `execCommand('insertText', false, prompt)` on contenteditable; fall back to `paste` via cdp `Input.insertText`; verify via `document.querySelector(sel).textContent.includes(marker)`.

**8. worker-race session tear** — two web tasks (gemini + deepseek) interleave on one broker; the second `createCDPSession` detaches the first's screencast frames.
guardrail: serialize via a promise chain per worker key (`this.queues.set(worker, this.queues.get(worker) ?? Promise.resolve())`); executeTask acquires the worker chain; screencast attaches only to the idle chain head.

**9. screenshot pii exfil** — `page.screenshot` captures bars: vault names, passwords-hint text fields, bookmarks.
guardrail: redact by clipping to `.message-content`/`#chat` rect (`clip: {x,y,width,height}` from `captureLayoutMap`); files land 0600; never leave files when task fails (`rm` on fail).

## b. task ring

**10. zombie lease deadlock** — kill the daemon mid `IN_FLIGHT`; recovery only runs *inside* checkout. with no PENDING rows to checkout, recovery never runs: the ring is permanently frozen.
guardrail: `recoverExpiredLeases` becomes an interval (30s) + at daemon boot (`index.ts` main); plus `heartbeat.py`/worker writes `updated_at` touches. sweep index exists (`idx_task_lease`).

**11. retry no-backoff storm** — deterministic failure: `failTask` → PENDING → immediate recheckout by the same worker → infinite hot loop.
guardrail: add `scheduled_at` column (or reuse `updated_at`): workers demand `status='PENDING' AND (scheduled_at IS NULL OR scheduled_at < unixepoch())`; `failTask` sets `scheduled_at = now + backoff(attempt)`, backoff = `2^retry_count * 5s`. bump `retry_count` on checkout.

**12. bootstrap double-fire** — double-click "Bootstrap Decomposition" inserts two identical `PLAN_DECOMPOSITION` trees.
guardrail: idempotency key `project_name + sha256(masterPlan)`; `createFreshProject` inserts keyed task only if no row with that `(operation_mode='PLAN_DECOMPOSITION', prompt_payload LIKE key)`; return existing id to the cockpit.

**13. path-injection project name** — `name="../library"` sails into `createFreshProject(name, …)` → `target_file` wanders outside the workspace and `vision_routing`/worker disk paths follow it.
guardrail: `createFreshProject` validates `/^[a-zA-Z0-9._-]{1,64}$/`; all file reads join against a resolved-prefix check (`path.resolve(p).startsWith(WORKSPACE_ROOT + path.sep)`).

**14. prompt injection via scraped plan** — masterPlan containing "ignore previous instructions" reaches the dispatcher verbatim as the first user message.
guardrail: dispatcher `vision.normalize_messages` wraps external text in explicit delimiters `── TASK INPUT (untrusted) ──` and `vision.py` appends a fixed system preamble `[orchestrator role]`; worker never concatenates raw plan into function-call tools.

**15. giant plan → context burn** — a 30k-word plan becomes a full prompt; the local model truncates silently.
guardrail: `createFreshProject` chunk plan to `max 4000 chars` for the decomposition pass; remainder stored in `staging_ring.diagnostics_log` as `PLAN_FULL`, referenced by pointer.

**16. sqlite writer starvation at syncIndex** — `syncIndex` runs one transaction enclosing reads+checksums of every file: a 20k-file repo holds `BEGIN IMMEDIATE` minutes → all journal/queue writes stall (`busy_timeout` fires).
guardrail: chunk the transaction — commit every 200 files *outside* the tx; upserts are idempotent; move `checksum` computation out of the tx entirely and pass batches to a `db.transaction()` per chunk.

## c. cockpit / humans

**17. on-main-thread frame decode** — every `screencast_frame` does `NSImage(data:)` on the UI thread (queue storm at 60fps → spinner = jank).
guardrail: receive → coalesce (drop frames while last decode in flight) → decode on a serial `DispatchQueue` → hand one `NSImage` to the main actor. also drop frames under low battery (see performance audit).

**18. invisible offline mode** — daemon down: list is stale, pull silently no-ops, cdp chip says IDLE but nothing explains why.
guardrail: `IPC OFFLINE` banner + disabled buttons + `status` event sets `tooltip`; one "Restart daemon" hint command `scripts/dev.sh`.

**19. no undo / no confirm on irreversibles** — pull+pull rebuilds the index; fresh project fires instantly.
guardrail: destructive ones (fresh project, re-index) get a `confirmationDialog` with the resulting task count; soft-delete instead of delete anywhere.

**20. hostile contrast & target size** — 8–10pt mono text, 4pt chips, all-gray-on-dark — unreadable for elderly, low-vision, and distracted users mid-task; also fails VoiceOver (symbols unlabeled).
guardrail: bump to minimum 11pt body / 10pt labels; touch targets ≥ 28pt with contentShape; every `Image(systemName:)` gets `.accessibilityLabel`; bay headers become `accessibilityHeading`; `HIG` contrast ≥ 4.5:1 for body (white.opacity(0.85) on 0.05 bg ≈ ok but chips `.gray` drop to `.white.opacity(0.6)`).

## d. summary — the five structural guardrails (architectural, not tactical)

1. `recoverExpiredLeases` runs as a **timer + boot sweep**, never only from checkout.
2. web work is **serialized per worker**; prompts are **idempotent via turn-markers**.
3. every untrusted string (plan, scraped text, project name) passes a **validator + delimiter** before prompt or disk.
4. frames are **coalesced + decoded off-main**, and screenshots are **redact-clipped + pruned**.
5. all mutating UI has a **confirm step + online-state visibility**.
