//! offcoderd: headless unified REST daemon for offcoder orchestration.
//!
//! Binds `127.0.0.1` by default with optional bearer auth (`OFFCODER_BEARER`).
//! All token output, diagnostics, and orchestration steps stream as typed
//! Server-Sent Events. Default port 8081 keeps clear of llama-server (8080).

use axum::extract::{Path, Query, State};
use axum::http::{HeaderMap, StatusCode};
use axum::response::sse::{Event, KeepAlive, Sse};
use axum::response::{IntoResponse, Json};
use axum::routing::{get, post};
use axum::Router;
use futures_util::StreamExt;
use offcoder_core::backend::{LlamaCppBackend, ModelBackend, PlatformProfile};
use offcoder_core::events::OrchestratorEvent;
use offcoder_core::profile::{ActiveProfile, ThermalState};
use offcoder_core::prompt::{ChatMessage, PromptBuilder, ReasoningEffort};
use offcoder_core::tools::standard_registry;
use offcoder_core::workspace::{FsProjectEnv, ProjectEnv};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::convert::Infallible;
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};
use tokio::sync::{mpsc, Mutex};

#[derive(Clone)]
pub struct AppState {
    backend: Arc<dyn ModelBackend>,
    bearer: Option<String>,
    workspaces: Arc<Mutex<HashMap<String, Arc<dyn ProjectEnv>>>>,
    default_workspace: String,
    workspace_root: String,
    profile: ActiveProfile,
    nodes: Arc<Mutex<HashMap<String, NodeInfo>>>,
    sessions: Arc<Mutex<HashMap<String, SessionRec>>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct NodeInfo {
    id: String,
    profile: PlatformProfile,
    models: Vec<String>,
    endpoint: String,
    last_seen_secs: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct SessionRec {
    id: String,
    workspace_key: String,
    created_secs: u64,
}

fn now_secs() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0)
}

/// Production entry: env-configured leader daemon, binds and serves forever.
pub async fn run() {
    let upstream =
        std::env::var("OFFCODER_UPSTREAM").unwrap_or("http://lockfort.local:8080/v1".into());
    let model = std::env::var("OFFCODER_MODEL").unwrap_or("qwythos".into());
    let port: u16 = std::env::var("OFFCODER_PORT")
        .ok()
        .and_then(|p| p.parse().ok())
        .unwrap_or(8081);
    let bearer = std::env::var("OFFCODER_BEARER").ok().filter(|s| !s.is_empty());
    let workspace_root =
        std::env::var("OFFCODER_WORKSPACE").unwrap_or("/tmp/offcoder-workspace".into());

    let profile = ActiveProfile::detect();
    println!(
        "[offcoderd] profile {:?} ctx={} mem={}MB kv={}MB parallel={}",
        profile.platform,
        profile.context_tokens,
        profile.memory_budget_mb,
        profile.kv_cache_quota_mb,
        profile.max_parallel_tools,
    );
    let backend: Arc<dyn ModelBackend> =
        Arc::new(LlamaCppBackend::new(upstream.clone(), model.clone(), profile.platform));
    let state = testable_state(backend, workspace_root.clone(), bearer, profile);

    let addr = format!("127.0.0.1:{port}");
    println!("[offcoderd] upstream {upstream} model {model} workspace {workspace_root}");
    println!("[offcoderd] listening on {addr}");
    let listener = tokio::net::TcpListener::bind(&addr).await.expect("bind");
    axum::serve(listener, build_router(state)).await.expect("serve");
}

fn testable_state(
    backend: Arc<dyn ModelBackend>,
    workspace_root: String,
    bearer: Option<String>,
    profile: ActiveProfile,
) -> AppState {
    AppState {
        backend,
        bearer,
        workspaces: Arc::new(Mutex::new(HashMap::from([(
            "default".to_string(),
            Arc::new(FsProjectEnv::new(workspace_root.clone())) as Arc<dyn ProjectEnv>,
        )]))),
        default_workspace: "default".into(),
        workspace_root,
        profile,
        nodes: Arc::new(Mutex::new(HashMap::new())),
        sessions: Arc::new(Mutex::new(HashMap::new())),
    }
}

fn build_router(state: AppState) -> Router {
    let app = Router::new()
        .route("/health", get(health))
        .route("/v1/models", get(models))
        .route("/v1/chat/completions", post(chat_completions))
        .route("/v1/tools", get(list_tools))
        .route("/v1/tools/execute", post(execute_tool))
        .route("/v1/tools/execute_batch", post(execute_batch))
        .route("/v1/workspace/list", get(ws_list))
        .route("/v1/workspace/file", get(ws_read).put(ws_write).delete(ws_delete))
        .route("/v1/workspace/shell", post(ws_shell))
        .route("/v1/nodes/register", post(node_register))
        .route("/v1/nodes", get(node_list))
        .route("/v1/nodes/dispatch", post(node_dispatch))
        .route("/v1/sessions", post(session_create))
        .route("/v1/sessions/:id", get(session_get).delete(session_delete))
        .with_state(state.clone());

    let app = app.layer(axum::middleware::from_fn_with_state(state, require_bearer));
    app.layer(axum::middleware::from_fn(log_access))
}

async fn log_access(
    req: axum::extract::Request,
    next: axum::middleware::Next,
) -> impl IntoResponse {
    let method = req.method().clone();
    let path = req.uri().path().to_string();
    let resp = next.run(req).await;
    eprintln!("[offcoderd] {method} {path} -> {}", resp.status());
    resp
}

/// Test/E2E entry: same router, injected backend, no bearer, edge profile.
pub fn test_router(backend: Arc<dyn ModelBackend>, workspace_root: String) -> Router {
    let profile = ActiveProfile {
        platform: PlatformProfile::EdgeQuantized,
        context_tokens: 8192,
        memory_budget_mb: 1024,
        kv_cache_quota_mb: PlatformProfile::EdgeQuantized.kv_cache_quota_mb(),
        max_parallel_tools: 1,
    };
    build_router(testable_state(backend, workspace_root, None, profile))
}

async fn require_bearer(
    State(state): State<AppState>,
    headers: HeaderMap,
    req: axum::extract::Request,
    next: axum::middleware::Next,
) -> impl IntoResponse {
    if state.bearer.is_none() {
        return next.run(req).await;
    }
    let ok = headers
        .get("authorization")
        .and_then(|v| v.to_str().ok())
        .map(|v| Some(v.to_string()) == state.bearer.clone().map(|b| format!("Bearer {b}")))
        .unwrap_or(false);
    if ok {
        next.run(req).await
    } else {
        (StatusCode::UNAUTHORIZED, Json(serde_json::json!({"error": "bad bearer"}))).into_response()
    }
}

// MARK: - Introspection

async fn health(State(state): State<AppState>) -> Json<serde_json::Value> {
    Json(serde_json::json!({
        "status": "ok",
        "model": state.backend.name(),
        "profile": state.profile,
        "thermal": format!("{:?}", ThermalState::current()).to_lowercase(),
        "upstream": "configured",
    }))
}

async fn models(State(state): State<AppState>) -> Json<serde_json::Value> {
    Json(serde_json::json!({
        "object": "list",
        "data": [{ "id": state.backend.name(), "object": "model", "owned_by": "offcoder" }],
    }))
}

async fn list_tools() -> Json<serde_json::Value> {
    Json(serde_json::json!({ "tools": standard_registry().schemas() }))
}

// MARK: - Chat completions (SSE, typed events)

#[derive(Debug, Deserialize)]
struct ChatRequest {
    messages: Vec<ChatMessage>,
    #[serde(default)]
    effort: Option<ReasoningEffortOpt>,
    #[serde(default)]
    workspace: Option<String>,
    #[serde(default = "default_true")]
    stream: bool,
    /// llama-style clients (the Swift deck) send `stream_options`; that
    /// presence switches the stream to OpenAI chunk frames. Native Rust
    /// clients omit it and receive typed events.
    #[serde(default)]
    stream_options: Option<serde_json::Value>,
}

fn default_true() -> bool {
    true
}

#[derive(Debug, Clone, Copy, Deserialize)]
#[serde(rename_all = "lowercase")]
enum ReasoningEffortOpt {
    Off,
    Low,
    Max,
}

async fn chat_completions(
    State(state): State<AppState>,
    Json(req): Json<ChatRequest>,
) -> impl IntoResponse {
    let effort = match req.effort {
        Some(ReasoningEffortOpt::Off) => ReasoningEffort::Off,
        Some(ReasoningEffortOpt::Max) => ReasoningEffort::Max,
        _ => ReasoningEffort::Low,
    };
    let ws_key = req.workspace.unwrap_or(state.default_workspace.clone());
    let env = {
        let map = state.workspaces.lock().await;
        map.get(&ws_key).cloned()
    };
    let (ws_dir, ws_map) = match env {
        Some(e) => {
            let entries = e.list_dir("").unwrap_or_default().join(", ");
            (e.root_label(), format!("[{entries}]"))
        }
        None => ("unknown".into(), "unknown workspace".into()),
    };
    let system = PromptBuilder {
        agent_system_name: "Indigo — the sovereign agent of this deck, running on the qwythos model.".into(),
        workspace_dir: ws_dir,
        workspace_map: ws_map,
        totem_context: "(daemon-managed totem context: mission ledger empty)".into(),
        effort,
    };
    // Thermal gate: critical pressure unloads the backend before any work.
    if ThermalState::current().must_unload() {
        state.backend.teardown();
        let body = OrchestratorEvent::Error {
            code: "thermal_unload".into(),
            message: "critical thermal pressure: backend unloaded".into(),
        };
        let sse = format!("event: error\ndata: {}\n\n", serde_json::to_string(&body).unwrap());
        return axum::response::Response::builder()
            .status(StatusCode::SERVICE_UNAVAILABLE)
            .header("content-type", "text/event-stream")
            .body(axum::body::Body::from(sse))
            .unwrap()
            .into_response();
    }

    let tools = standard_registry().schemas();
    let (tx, rx) = mpsc::unbounded_channel::<OrchestratorEvent>();
    let backend = state.backend.clone();
    let user_messages = req.messages;
    tokio::spawn(async move {
        let _ = tx.send(OrchestratorEvent::Process {
            state: "INGESTING_PROMPT".into(),
            detail: "preparing turn".into(),
        });
        if let Err(e) = backend.complete(&system, &user_messages, &tools, tx.clone()).await {
            let _ = tx.send(OrchestratorEvent::Error { code: "backend_failed".into(), message: e });
        }
    });

    if !req.stream {
        // Non-streaming collectors (edge dispatch): gather to one message.
        let mut text = String::new();
        let mut thought = String::new();
        let mut completion_tokens = 0u32;
        let mut rx = rx;
        while let Some(ev) = rx.recv().await {
            match ev {
                OrchestratorEvent::Token { delta } => text.push_str(&delta),
                OrchestratorEvent::Reasoning { delta } => thought.push_str(&delta),
                OrchestratorEvent::Done { completion_tokens: n } => {
                    completion_tokens = n;
                    break;
                }
                OrchestratorEvent::Error { code, message } => {
                    return (
                        StatusCode::BAD_GATEWAY,
                        Json(serde_json::json!({ "error": code, "message": message })),
                    )
                        .into_response();
                }
                _ => {}
            }
        }
        if req.stream_options.is_some() {
            return Json(serde_json::json!({
                "id": "chatcmpl-offcoder",
                "object": "chat.completion",
                "created": now_secs(),
                "model": state.backend.name(),
                "choices": [{
                    "index": 0,
                    "message": { "role": "assistant", "content": text },
                    "finish_reason": "stop",
                }],
                "usage": { "completion_tokens": completion_tokens },
            }))
            .into_response();
        }
        return Json(serde_json::json!({
            "message": { "role": "assistant", "content": text, "thought": thought },
        }))
        .into_response();
    }

    if req.stream_options.is_some() {
        // Deck dialect: OpenAI chunk frames translated from typed events.
        let model = state.backend.name().to_string();
        let stream = tokio_stream::wrappers::UnboundedReceiverStream::new(rx)
            .filter_map(move |ev: OrchestratorEvent| {
                let model = model.clone();
                async move {
                    translate_openai(&ev, &model)
                        .map(|data| Ok::<Event, Infallible>(Event::default().data(data)))
                }
            });
        return axum::response::Sse::new(stream)
            .keep_alive(KeepAlive::default())
            .into_response();
    }

    let stream = tokio_stream::wrappers::UnboundedReceiverStream::new(rx).map(|ev: OrchestratorEvent| {
        Ok::<Event, Infallible>(Event::default().event(ev.sse_kind()).data(
            serde_json::to_string(&ev).unwrap_or_default(),
        ))
    });
    Sse::new(stream).keep_alive(KeepAlive::default()).into_response()
}

/// Translate one typed event into an OpenAI chunk JSON payload.
/// Shapes mirror llama.cpp chunk frames; axum adds the `data:` framing.
/// Process/tool_result are deck-side concerns (the deck drives those) and
/// map to nothing.
fn translate_openai(ev: &OrchestratorEvent, model: &str) -> Option<String> {
    let chunk = |delta: serde_json::Value| {
        serde_json::json!({
            "id": "chatcmpl-offcoder",
            "object": "chat.completion.chunk",
            "created": now_secs(),
            "model": model,
            "choices": [{ "index": 0, "delta": delta, "finish_reason": null }],
        })
        .to_string()
    };
    match ev {
        OrchestratorEvent::Token { delta } => {
            Some(chunk(serde_json::json!({ "content": delta })))
        }
        OrchestratorEvent::Reasoning { delta } => {
            Some(chunk(serde_json::json!({ "reasoning_content": delta })))
        }
        OrchestratorEvent::ToolCall { id, name, arguments } => {
            Some(chunk(serde_json::json!({ "tool_calls": [{
                "id": id, "type": "function",
                "function": { "name": name, "arguments": arguments },
            }] })))
        }
        OrchestratorEvent::Done { completion_tokens } => {
            Some(
                serde_json::json!({
                    "id": "chatcmpl-offcoder",
                    "object": "chat.completion.chunk",
                    "created": now_secs(),
                    "model": model,
                    "choices": [{ "index": 0, "delta": {}, "finish_reason": "stop" }],
                    "usage": { "completion_tokens": completion_tokens },
                })
                .to_string(),
            )
        }
        OrchestratorEvent::Error { code, message } => {
            Some(serde_json::json!({ "error": { "code": code, "message": message } }).to_string())
        }
        _ => None,
    }
}

// MARK: - Tool execution

#[derive(Debug, Deserialize)]
struct ToolExecRequest {
    name: String,
    #[serde(default)]
    arguments: serde_json::Value,
    #[serde(default)]
    workspace: Option<String>,
}

#[derive(Debug, Serialize)]
struct ToolExecResponse {
    output: String,
    is_error: bool,
}

async fn execute_tool(
    State(state): State<AppState>,
    Json(req): Json<ToolExecRequest>,
) -> Json<ToolExecResponse> {
    let ws_key = req.workspace.unwrap_or(state.default_workspace.clone());
    let env = {
        let map = state.workspaces.lock().await;
        map.get(&ws_key).cloned()
    };
    let Some(env) = env else {
        return Json(ToolExecResponse { output: "unknown workspace".into(), is_error: true });
    };
    let out = standard_registry().dispatch(&req.name, req.arguments, env);
    Json(ToolExecResponse { output: out.output, is_error: out.is_error })
}

// MARK: - Workspace CRUD + shell

#[derive(Debug, Deserialize)]
struct WsPath {
    path: String,
    #[serde(default)]
    workspace: Option<String>,
}

async fn ws_env(state: &AppState, ws: Option<String>) -> Option<Arc<dyn ProjectEnv>> {
    let key = ws.unwrap_or(state.default_workspace.clone());
    state.workspaces.lock().await.get(&key).cloned()
}

async fn ws_list(
    State(state): State<AppState>,
    Query(q): Query<HashMap<String, String>>,
) -> Json<serde_json::Value> {
    let env = ws_env(&state, q.get("workspace").cloned()).await;
    match env {
        Some(e) => Json(serde_json::json!({
            "root": e.root_label(),
            "entries": e.list_dir(q.get("path").cloned().unwrap_or_default().as_str()).unwrap_or_default(),
        })),
        None => Json(serde_json::json!({ "error": "unknown workspace" })),
    }
}

async fn ws_read(
    State(state): State<AppState>,
    Query(q): Query<WsPath>,
) -> impl IntoResponse {
    match ws_env(&state, q.workspace).await {
        Some(e) => match e.read_file(&q.path) {
            Ok(text) => (StatusCode::OK, Json(serde_json::json!({ "path": q.path, "content": text }))).into_response(),
            Err(err) => (StatusCode::NOT_FOUND, Json(serde_json::json!({ "error": err }))).into_response(),
        },
        None => (StatusCode::NOT_FOUND, Json(serde_json::json!({ "error": "unknown workspace" }))).into_response(),
    }
}

#[derive(Debug, Deserialize)]
struct WsWrite {
    path: String,
    content: String,
    #[serde(default)]
    workspace: Option<String>,
}

async fn ws_write(State(state): State<AppState>, Json(req): Json<WsWrite>) -> Json<serde_json::Value> {
    match ws_env(&state, req.workspace).await {
        Some(e) => match e.write_file(&req.path, &req.content) {
            Ok(()) => Json(serde_json::json!({ "written": req.path })),
            Err(err) => Json(serde_json::json!({ "error": err })),
        },
        None => Json(serde_json::json!({ "error": "unknown workspace" })),
    }
}

async fn ws_delete(Query(q): Query<WsPath>) -> Json<serde_json::Value> {
    // Delete = write empty then report; true removal stays behind a confirm gate (future).
    Json(serde_json::json!({ "error": format!("refusing to delete {} without confirm gate", q.path) }))
}

#[derive(Debug, Deserialize)]
struct WsShell {
    command: String,
    #[serde(default)]
    workspace: Option<String>,
}

async fn ws_shell(State(state): State<AppState>, Json(req): Json<WsShell>) -> Json<serde_json::Value> {
    match ws_env(&state, req.workspace).await {
        Some(e) => match e.run_command(&req.command) {
            Ok(out) => Json(serde_json::json!({ "output": out })),
            Err(err) => Json(serde_json::json!({ "error": err })),
        },
        None => Json(serde_json::json!({ "error": "unknown workspace" })),
    }
}

// MARK: - Tool batch fan-out (parallel on desktop, sequential on edge)

#[derive(Debug, Deserialize)]
struct BatchRequest {
    calls: Vec<BatchCall>,
    #[serde(default)]
    workspace: Option<String>,
}

#[derive(Debug, Deserialize)]
struct BatchCall {
    name: String,
    #[serde(default)]
    arguments: serde_json::Value,
}

async fn execute_batch(
    State(state): State<AppState>,
    Json(req): Json<BatchRequest>,
) -> Json<serde_json::Value> {
    let ws_key = req.workspace.unwrap_or(state.default_workspace.clone());
    let env = { state.workspaces.lock().await.get(&ws_key).cloned() };
    let Some(env) = env else {
        return Json(serde_json::json!({ "error": "unknown workspace" }));
    };
    let reg = standard_registry();
    let calls: Vec<(String, serde_json::Value)> =
        req.calls.into_iter().map(|c| (c.name, c.arguments)).collect();
    let outcomes = if state.profile.sequential() {
        reg.dispatch_seq(&calls, env)
    } else {
        reg.dispatch_parallel(calls, env).await
    };
    Json(serde_json::json!({ "results": outcomes }))
}

// MARK: - Edge node mesh (Phase 4: macOS Leader, mobile Workers)

#[derive(Debug, Deserialize)]
struct NodeRegister {
    id: String,
    profile: PlatformProfile,
    #[serde(default)]
    models: Vec<String>,
    endpoint: String,
}

async fn node_register(
    State(state): State<AppState>,
    Json(req): Json<NodeRegister>,
) -> Json<serde_json::Value> {
    let info = NodeInfo {
        id: req.id.clone(),
        profile: req.profile,
        models: req.models,
        endpoint: req.endpoint.trim_end_matches('/').to_string(),
        last_seen_secs: now_secs(),
    };
    state.nodes.lock().await.insert(req.id.clone(), info.clone());
    Json(serde_json::json!({ "registered": info }))
}

async fn node_list(State(state): State<AppState>) -> Json<serde_json::Value> {
    let nodes: Vec<NodeInfo> = state.nodes.lock().await.values().cloned().collect();
    Json(serde_json::json!({ "leader": "self", "nodes": nodes }))
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "lowercase")]
enum SubTaskKind {
    Analysis,
    Lint,
    Subquery,
}

#[derive(Debug, Deserialize)]
struct NodeDispatch {
    kind: SubTaskKind,
    #[serde(default)]
    node_id: Option<String>,
    #[serde(default)]
    arguments: serde_json::Value,
    #[serde(default)]
    workspace: Option<String>,
}

async fn node_dispatch(
    State(state): State<AppState>,
    Json(req): Json<NodeDispatch>,
) -> impl IntoResponse {
    // No node_id = Leader executes locally with the same tool path.
    let endpoint = match &req.node_id {
        Some(id) => match state.nodes.lock().await.get(id) {
            Some(n) => n.endpoint.clone(),
            None => {
                return (
                    StatusCode::NOT_FOUND,
                    Json(serde_json::json!({ "error": format!("unknown node {id}") })),
                )
                    .into_response()
            }
        },
        None => return dispatch_local(&state, req).await.into_response(),
    };
    let client = reqwest::Client::new();
    let (path, body) = match req.kind {
        SubTaskKind::Analysis => (
            "/v1/tools/execute",
            serde_json::json!({
                "name": "grep_search",
                "arguments": req.arguments,
                "workspace": req.workspace,
            }),
        ),
        SubTaskKind::Lint => (
            "/v1/tools/execute",
            serde_json::json!({
                "name": "run_command",
                "arguments": req.arguments,
                "workspace": req.workspace,
            }),
        ),
        SubTaskKind::Subquery => (
            "/v1/chat/completions",
            serde_json::json!({
                "messages": req.arguments.get("messages").cloned().unwrap_or_default(),
                "effort": "low",
                "stream": false,
            }),
        ),
    };
    match client.post(format!("{endpoint}{path}")).json(&body).send().await {
        Ok(resp) => {
            let status = resp.status();
            let text = resp.text().await.unwrap_or_default();
            let payload: serde_json::Value = serde_json::from_str(&text).unwrap_or(serde_json::json!({ "raw": text }));
            (status, Json(serde_json::json!({ "node": req.node_id, "result": payload }))).into_response()
        }
        Err(e) => (
            StatusCode::BAD_GATEWAY,
            Json(serde_json::json!({ "error": format!("node unreachable: {e}") })),
        )
            .into_response(),
    }
}

async fn dispatch_local(state: &AppState, req: NodeDispatch) -> Json<serde_json::Value> {
    let ws_key = req.workspace.unwrap_or(state.default_workspace.clone());
    let env = { state.workspaces.lock().await.get(&ws_key).cloned() };
    let Some(env) = env else {
        return Json(serde_json::json!({ "error": "unknown workspace" }));
    };
    let reg = standard_registry();
    let (name, args) = match req.kind {
        SubTaskKind::Analysis => ("grep_search", req.arguments),
        SubTaskKind::Lint => ("run_command", req.arguments),
        SubTaskKind::Subquery => {
            return Json(serde_json::json!({
                "error": "subquery without a node_id needs a chat turn; use /v1/chat/completions"
            }))
        }
    };
    let out = reg.dispatch(name, args, env);
    Json(serde_json::json!({ "node": "leader-local", "output": out.output, "is_error": out.is_error }))
}

// MARK: - Session lifecycle (bounded workspaces with explicit teardown)

#[derive(Debug, Deserialize)]
struct SessionCreate {
    #[serde(default)]
    label: Option<String>,
}

async fn session_create(
    State(state): State<AppState>,
    Json(req): Json<SessionCreate>,
) -> Json<serde_json::Value> {
    let id = format!("sess-{}", now_secs());
    let dir = std::path::Path::new(&state.workspace_root).join("sessions").join(&id);
    if let Err(e) = std::fs::create_dir_all(&dir) {
        return Json(serde_json::json!({ "error": e.to_string() }));
    }
    let key = format!("session:{id}");
    state.workspaces.lock().await.insert(
        key.clone(),
        Arc::new(FsProjectEnv::new(&dir)) as Arc<dyn ProjectEnv>,
    );
    let rec = SessionRec { id: id.clone(), workspace_key: key, created_secs: now_secs() };
    state.sessions.lock().await.insert(id.clone(), rec.clone());
    Json(serde_json::json!({
        "session": rec,
        "label": req.label.unwrap_or_default(),
        "workspace": dir.display().to_string(),
    }))
}

async fn session_get(State(state): State<AppState>, Path(id): Path<String>) -> impl IntoResponse {
    match state.sessions.lock().await.get(&id) {
        Some(rec) => (StatusCode::OK, Json(serde_json::json!({ "session": rec }))).into_response(),
        None => (StatusCode::NOT_FOUND, Json(serde_json::json!({ "error": "unknown session" }))).into_response(),
    }
}

async fn session_delete(State(state): State<AppState>, Path(id): Path<String>) -> impl IntoResponse {
    let rec = state.sessions.lock().await.remove(&id);
    let Some(rec) = rec else {
        return (StatusCode::NOT_FOUND, Json(serde_json::json!({ "error": "unknown session" }))).into_response();
    };
    state.workspaces.lock().await.remove(&rec.workspace_key);
    // Explicit teardown: backend ledger to zero, session dir removed.
    state.backend.teardown();
    let dir = std::path::Path::new(&state.workspace_root).join("sessions").join(&id);
    let removed = std::fs::remove_dir_all(&dir).is_ok();
    (
        StatusCode::OK,
        Json(serde_json::json!({ "deleted": id, "dir_removed": removed })),
    )
        .into_response()
}

#[cfg(test)]
mod tests {
    use super::*;
    use offcoder_core::events::OrchestratorEvent;

    /// Deck wire contract: the Swift parser reads choices[0].delta.content,
    /// reasoning_content, tool_calls, and usage.completion_tokens.
    #[test]
    fn openai_chunks_match_deck_parser_expectations() {
        let tok = translate_openai(
            &OrchestratorEvent::Token { delta: "hi".into() },
            "qwythos",
        )
        .unwrap();
        let v: serde_json::Value = serde_json::from_str(&tok).unwrap();
        assert_eq!(v["choices"][0]["delta"]["content"], "hi");

        let th = translate_openai(
            &OrchestratorEvent::Reasoning { delta: "hmm".into() },
            "qwythos",
        )
        .unwrap();
        let v: serde_json::Value = serde_json::from_str(&th).unwrap();
        assert_eq!(v["choices"][0]["delta"]["reasoning_content"], "hmm");

        let tc = translate_openai(
            &OrchestratorEvent::ToolCall {
                id: "1".into(),
                name: "read_file".into(),
                arguments: "{\"path\":\"a\"}".into(),
            },
            "qwythos",
        )
        .unwrap();
        let v: serde_json::Value = serde_json::from_str(&tc).unwrap();
        assert_eq!(v["choices"][0]["delta"]["tool_calls"][0]["function"]["name"], "read_file");

        let done = translate_openai(
            &OrchestratorEvent::Done { completion_tokens: 7 },
            "qwythos",
        )
        .unwrap();
        let v: serde_json::Value = serde_json::from_str(&done).unwrap();
        assert_eq!(v["choices"][0]["finish_reason"], "stop");
        assert_eq!(v["usage"]["completion_tokens"], 7);

        assert!(translate_openai(
            &OrchestratorEvent::Process { state: "X".into(), detail: "y".into() },
            "qwythos",
        )
        .is_none());
    }
}
