# e2e suite — coverage map

runner: `e2e/` (playwright). asserts on the real daemon process with isolated state (`ORCH_ROOT` temp dir, random ws port, `ORCH_LEASE_SECONDS=2`, `ORCH_CDP_PORT=19222` → no chrome required).

## critical journeys

| journey | spec | sequence |
|---|---|---|
| boot → idle | marquee-contract | spawn → `marquee_state` carries alert `cdp_offline` (chrome absent) → `daemon_ready` console line |
| fresh project | marquee-contract | `fresh_project` → `plan_queued` + `journal PLAN_INIT` + `task_event PENDING` |
| worker run | marquee-contract | `self_fulfill` → marquee `working` (event task_checked_out) → marquee `success` (task_staged) → artifact in `staging_ring` |
| repo failure | marquee-contract | `pull_repo` unknown id → `repo_missing` marquee alert + error reply |
| idempotency | marquee-contract | duplicate `fresh_project` → same `task_id` returned, `reused:true` |
| malformed frame | chaos | garbage json → `error bad_client_frame` + `domain:daemon` console log |
| frame overflow | chaos | 300KB frame → close 1013 + `frame_overflow` log |
| auth | chaos | no/bad token → close 1008 + `auth_rejected` log; auth success → snapshot replay |
| lease deadlock | chaos | stalled faucet (expired lease, killed) → daemon reclaims → marquee alert `lease_expired` → second faucet completes task (`staged`) |
| visual | marquee-visual | idempotent/working/alert — golden screenshots of the marquee harness |

## failure-state console assertions

asserted directly against captured daemon stdout/stderr JSON lines (`utils/logcat.mjs`): `daemon_ready`, `cdp_offline`, `bad_client_frame`, `frame_overflow`, `auth_rejected`, `lease_expired` — the same `structLog` contract the cockpit FaultRegistry mirrors (`[cockpit] {"domain":"cockpit",...}`).

## marquee color/text validation

ws-level: levels asserted `working` (yellow), `success` (green), `alert` (red) with exact `text` from `marqueeMapping`. visual level: `marquee.html` harness with PAUSED scroll → pixel-stable goldens.

## regenerate snapshots

```sh
cd e2e && npm run snapshots
```
