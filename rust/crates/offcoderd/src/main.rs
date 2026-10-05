//! offcoderd: headless unified REST daemon for offcoder orchestration.
//!
//! Binds `127.0.0.1` by default with optional bearer auth (`OFFCODER_BEARER`).
//! All token output, diagnostics, and orchestration steps stream as typed
//! Server-Sent Events. Default port 8081 keeps clear of llama-server (8080).

use axum::extract::{Query, State};
use axum::http::{HeaderMap, StatusCode};
use axum::response::sse::{Event, KeepAlive, Sse};
use axum::response::{IntoResponse, Json};
use axum::routing::{get, post};
use axum::Router;
use futures_util::StreamExt;
use offcoder_core::backend::{LlamaCppBackend, ModelBackend, PlatformProfile};
use offcoder_core::events::OrchestratorEvent;
use offcoder_core::prompt::{ChatMessage, PromptBuilder, ReasoningEffort};
use offcoder_core::tools::standard_registry;
use offcoder_core::workspace::{FsProjectEnv, ProjectEnv};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::convert::Infallible;
use std::sync::Arc;
use tokio::sync::{mpsc, Mutex};

#[derive(Clone)]
struct AppState {
    backend: Arc<LlamaCppBackend>,
    bearer: Option<String>,
    workspaces: Arc<Mutex<HashMap<String, Arc<dyn ProjectEnv>>>>,
    default_workspace: String,
}

#[tokio::main]
async fn main() {
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

    let state = AppState {
        backend: Arc::new(LlamaCppBackend::new(upstream.clone(), model.clone(), PlatformProfile::MacosMetal)),
        bearer,
        workspaces: Arc::new(Mutex::new(HashMap::from([(
            "default".to_string(),
            Arc::new(FsProjectEnv::new(workspace_root.clone())) as Arc<dyn ProjectEnv>,
        )]))),
        default_workspace: "default".into(),
    };

    let app = Router::new()
        .route("/health", get(health))
        .route("/v1/models", get(models))
        .route("/v1/chat/completions", post(chat_completions))
        .route("/v1/tools", get(list_tools))
        .route("/v1/tools/execute", post(execute_tool))
        .route("/v1/workspace/list", get(ws_list))
        .route("/v1/workspace/file", get(ws_read).put(ws_write).delete(ws_delete))
        .route("/v1/workspace/shell", post(ws_shell))
        .with_state(state.clone());

    let app = app.layer(axum::middleware::from_fn_with_state(state.clone(), require_bearer));

    let addr = format!("127.0.0.1:{port}");
    println!("[offcoderd] upstream {upstream} model {model} workspace {workspace_root}");
    println!("[offcoderd] listening on {addr}");
    let listener = tokio::net::TcpListener::bind(&addr).await.expect("bind");
    axum::serve(listener, app).await.expect("serve");
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
        "profile": state.backend.profile(),
        "kv_cache_quota_mb": state.backend.profile().kv_cache_quota_mb(),
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

    let stream = tokio_stream::wrappers::UnboundedReceiverStream::new(rx).map(|ev: OrchestratorEvent| {
        Ok::<Event, Infallible>(Event::default().event(ev.sse_kind()).data(
            serde_json::to_string(&ev).unwrap_or_default(),
        ))
    });
    Sse::new(stream).keep_alive(KeepAlive::default())
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
