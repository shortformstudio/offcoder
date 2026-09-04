# chaos engineering protocol — resilience matrix

the runnable protocol for the "inject like an attacker, harden like an operator" pass over the three domains. every simulation mode below is implemented in the repo.

## 1. thread starvation & memory exhaustion

- **simulation:** faucet workers hammering the sqlite ring in parallel while a giant fresh-plan lands; screencast frames at 60fps with no client.
- **hardened:** `faucet_worker.mjs` holds `BEGIN IMMEDIATE`; daemon checkout is transaction-al (spins up to `busy_timeout`), dispatcher `worker.py` retries with 0.25s/attempt backoff, logs `db_busy`, never crashes; frame path drops >512KB broadcasts; cockpit coalesces + decodes off-main (one frame in flight); queue ring indexes expire.
- **verification:** `chaos.spec.ts` lease test drives inter-process WAL contention.

## 2. dropped payloads & malformed JSON

- **simulation:** upstream model emits `{not json` / hangs; client sends garbage over ws.
- **hardened:** dispatcher `main.py` guards `request.json()`, validates `messages` list, returns 400/502, structured-logs `malformed_body`/`upstream_malformed`; daemon `ipc.ts` rejects bad frames with `bad_client_frame` and closes on >256KB (`frame_overflow`, close 1013); scraper waits are bounded (60s + 15s settle) and run under per-worker mutex.
- **verification:** `chaos.spec.ts` malformed + oversize cases; console assertion via `waitLog('bad_client_frame')`.

## 3. concurrent disk read/write locks

- **simulation:** repo sync (10k files) while workers write journal + staging simultaneously.
- **hardened:** `github_sync.syncIndex` reads/checksums **outside** the transaction and commits in 200-file chunks (starvation window shrinks from minutes to milliseconds); WAL + busy_timeout 5000 both sides; python worker re-opens connection after contention crashes.
- **verification:** concurrent faucet + sync exercised in salt tests; contention counters via `db_busy` logs.

## 4. sudden permission revocations

- **simulation:** `rm -rf` read access on `~/.local_orchestrator`, disk full, or chmod 000 on the workspace mid-run.
- **hardened:** all fs access in daemon paths fails to structured log (`permission_denied` mapping → alert marquee) without process exit; `registerRepo`/`syncIndex` guard `existsSync` before reads; worker cooldown (60s) after 5 consecutive failures; screenshots pruned to 200 files + weekly, never unbounded growth; process-level `uncaughtException`/`unhandledRejection` log `critical` and exit cleanly.

## 5. the marquee, always

every failure category maps through `daemon/src/errors.ts marqueeMapping` → `MarqueeDirector` → ws `marquee` event → cockpit bottom-left strip: green idle/success, yellow working, red alert. the strip is click-through except the alert expansion, opens the detail panel with the exact fault stack, and offers one-click `Recover State` (reconnect + un-bail bays + refetch).

## run the protocol

```sh
cd e2e && npm install && npx playwright install chromium && npm test
```

see `docs/E2E.md` + `e2e/README.md` for the per-case mapping.
