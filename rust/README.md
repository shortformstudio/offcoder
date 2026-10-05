# offcoder rust core (`rust` branch)

Headless unified REST daemon architecture per the cross-platform refactor:
engine-agnostic core shared by macOS (Metal tier) and future mobile/edge nodes.

## Layout

- `crates/offcoder-core` — shared primitives
  - `backend.rs` — `ModelBackend` trait, `PlatformProfile` (KV quotas per tier),
    `LlamaCppBackend` (Metal runtime / lockfort proxy, SSE re-emit as typed events)
  - `prompt.rs` — identical prompt assembly everywhere (identity, scale,
    OFF|LOW|MAX reasoning budget)
  - `events.rs` — typed SSE JSON events (token, reasoning, tool_call,
    tool_result, process, done, error)
  - `tools.rs` — `ToolRegistry` (OpenAI-schema tools, identical serialization)
  - `workspace.rs` — `ProjectEnv`: `FsProjectEnv` (root-sandboxed CRUD +
    `sh -c` on macOS) and `VfsProjectEnv` (in-memory, deny-by-default shell
    for edge)
- `crates/offcoderd` — the daemon binary

## Run

```sh
cargo build --release -p offcoderd
OFFCODER_UPSTREAM=http://lockfort.local:8080/v1 OFFCODER_PORT=8081 ./target/release/offcoderd
```

Env: `OFFCODER_UPSTREAM` (default lockfort), `OFFCODER_MODEL` (default qwythos),
`OFFCODER_PORT` (default 8081), `OFFCODER_WORKSPACE`, `OFFCODER_BEARER`
(optional bearer token; unset = open LAN with a warning posture).

## Endpoints

- `GET /health` — status, profile, KV quota
- `GET /v1/models` — serving model
- `POST /v1/chat/completions` — SSE typed events; body `{messages, effort, workspace}`
- `GET /v1/tools` — tool schemas
- `POST /v1/tools/execute` — `{name, arguments, workspace}`
- `GET /v1/workspace/list?path=&workspace=`
- `GET /v1/workspace/file?path=` · `PUT /v1/workspace/file` · `DELETE` (confirm-gated refusal)
- `POST /v1/workspace/shell` — `{command, workspace}`

## Honest deltas vs the master prompt

- UDS socket + mTLS: not yet — TCP 127.0.0.1 + bearer token ships now.
- HTTP/2 + OpenAPI 3.1 doc: HTTP/1.1 + SSE ships; doc pending.
- CoreML / ExecuTorch backends: trait seam ready, only `LlamaCppBackend` implemented.
- Delete-gate and edge delegate evaluator: stubbed refusals, correct shape.
