# e2e — chaos & marquee contract suite

playwright runner against the real daemon (spawned per test with isolated `ORCH_ROOT` + ports + 2s lease override). no chrome needed: cdp is simulated absent, which exercises the alert path.

## run

```sh
cd e2e
npm install
npx playwright install chromium   # needed only for visual regression tests
npm test
```

## suite map

| spec | covers |
|---|---|
| `specs/marquee-contract.spec.ts` | boot snapshot (alert `cdp_offline`), `fresh_project` → `plan_queued` + `journal`, `self_fulfill` (selftest hook) → marquee `working` → `success`, bad repo → alert `repo_missing`, structured console codes, idempotent double submit |
| `specs/chaos.spec.ts` | malformed json frame → error reply + `bad_client_frame` log; oversize frame → close **1013**; ws token auth → **1008** reject / accept; lease expiry recovery: stalled faucet worker reclaimed, marquee alert `lease_expired`, task completes via second faucet |
| `specs/marquee-visual.spec.ts` | deterministic golden snapshots of the three marquee states (idle/working/alert) — run `npm run snapshots` to (re)generate goldens |

## chaos modes injected

- frame overflow: 300KB client frame
- malformed payloads: raw `{totally broken`
- permission/disk: faucet workers write via better-sqlite3 against the same db as the daemon (real WAL contention on `BEGIN IMMEDIATE`)
- stalled worker: faucet leases a task with an expired lease (`ORCH_LEASE_SECONDS=2`) and dies — daemon sweep + checkout recover it

console log assertions check the daemon `domain:daemon` JSON lines (see `utils/logcat.mjs`), mirroring the structured `structLog` contract from `daemon/src/errors.ts`.

## selftest hook

`ORCH_SELFTEST=1` unlocks the `self_fulfill` ws command: it performs a real `checkoutTask → addStagingArtifact → finalizeTask` round-trip against the sqlite ring, which fires the same `task_event`/`marquee` broadcasts as a live worker — that is what makes the `working`→`success` marquee assertion browser-free.
