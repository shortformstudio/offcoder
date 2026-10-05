//! Phase 4 acceptance, end to end over HTTP:
//! 1. complete session lifecycle through endpoints,
//! 2. SSE streaming resilience across interruptions,
//! 3. safe patch application inside bounded workspaces.
//!
//! Plus node-mesh loopback and thermal unload.

use futures_util::StreamExt;
use offcoder_core::backend::MockBackend;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;

static SEQ: AtomicU64 = AtomicU64::new(0);

async fn spawn() -> (String, String) {
    let n = SEQ.fetch_add(1, Ordering::SeqCst);
    let root = std::env::temp_dir()
        .join(format!("offcoder-e2e-{}-{}", std::process::id(), n))
        .display()
        .to_string();
    let _ = std::fs::remove_dir_all(&root);
    let backend: Arc<dyn offcoder_core::backend::ModelBackend> =
        Arc::new(MockBackend::new(vec!["a".into(), "b".into(), "c".into()]));
    let router = offcoderd::test_router(backend, root.clone());
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn(async move {
        axum::serve(listener, router).await.unwrap();
    });
    (format!("http://{addr}"), root)
}

fn client() -> reqwest::Client {
    reqwest::Client::new()
}

#[tokio::test]
#[serial_test::serial]
async fn session_lifecycle() {
    let (base, root) = spawn().await;
    let c = client();

    // create
    let sess: serde_json::Value =
        c.post(format!("{base}/v1/sessions")).json(&serde_json::json!({})).send().await.unwrap().json().await.unwrap();
    let id = sess["session"]["id"].as_str().unwrap().to_string();
    let ws = format!("session:{id}");
    let sess_dir = std::path::Path::new(&root).join("sessions").join(&id);
    assert!(sess_dir.is_dir());

    // write + read inside the session workspace
    let put: serde_json::Value = c
        .put(format!("{base}/v1/workspace/file"))
        .json(&serde_json::json!({"path": "code.txt", "content": "alpha\nbeta\n", "workspace": ws}))
        .send().await.unwrap().json().await.unwrap();
    assert_eq!(put["written"], "code.txt");
    let get: serde_json::Value = c
        .get(format!("{base}/v1/workspace/file"))
        .query(&[("path", "code.txt"), ("workspace", ws.as_str())])
        .send().await.unwrap().json().await.unwrap();
    assert_eq!(get["content"], "alpha\nbeta\n");

    // bounded shell runs with the session dir as cwd
    let sh: serde_json::Value = c
        .post(format!("{base}/v1/workspace/shell"))
        .json(&serde_json::json!({"command": "pwd", "workspace": ws}))
        .send().await.unwrap().json().await.unwrap();
    assert!(sh["output"].as_str().unwrap().contains(&id));

    // get + delete = explicit teardown
    let g = c.get(format!("{base}/v1/sessions/{id}")).send().await.unwrap();
    assert_eq!(g.status(), 200);
    let d = c.delete(format!("{base}/v1/sessions/{id}")).send().await.unwrap();
    assert_eq!(d.status(), 200);
    assert!(!sess_dir.exists());
    let g2 = c.get(format!("{base}/v1/sessions/{id}")).send().await.unwrap();
    assert_eq!(g2.status(), 404);
    let _ = std::fs::remove_dir_all(&root);
}

#[tokio::test]
#[serial_test::serial]
async fn sse_resilience_across_interruption() {
    let (base, root) = spawn().await;
    let c = client();
    let chat = |c: &reqwest::Client| {
        c.post(format!("{base}/v1/chat/completions")).json(&serde_json::json!({
            "messages": [{"role": "user", "content": "hi"}],
            "effort": "off",
        }))
    };

    // 1. connect, read one frame, abort mid-stream.
    let resp = chat(&c).send().await.unwrap();
    assert_eq!(resp.status(), 200);
    let mut stream = resp.bytes_stream();
    assert!(stream.next().await.is_some());
    drop(stream);

    // 2. server is unharmed: health ok, second stream runs to done.
    let h = c.get(format!("{base}/health")).send().await.unwrap();
    assert_eq!(h.status(), 200);
    let body = chat(&c).send().await.unwrap().text().await.unwrap();
    assert!(body.contains("\"kind\":\"done\""));
    assert!(body.contains("\"kind\":\"token\""));
    let _ = std::fs::remove_dir_all(&root);
}

#[tokio::test]
#[serial_test::serial]
async fn patch_application_stays_bounded() {
    let (base, root) = spawn().await;
    let c = client();
    let exec = |name: &str, args: serde_json::Value| {
        c.post(format!("{base}/v1/tools/execute")).json(&serde_json::json!({
            "name": name, "arguments": args,
        }))
    };

    exec("write_file", serde_json::json!({"path": "f.txt", "content": "a\nb\nc\n"}))
        .send().await.unwrap();

    let ok: serde_json::Value = exec(
        "apply_patch",
        serde_json::json!({
            "path": "f.txt",
            "patch": "--- a/f\n+++ b/f\n@@ -1,3 +1,3 @@\n a\n-b\n+B\n c\n",
        }),
    )
    .send().await.unwrap().json().await.unwrap();
    assert!(!ok["is_error"].as_bool().unwrap(), "{}", ok["output"]);

    let evil: serde_json::Value = exec(
        "apply_patch",
        serde_json::json!({"path": "../evil.txt", "patch": "--- a\n+++ b\n@@ -0,0 +1 @@\n+x\n"}),
    )
    .send().await.unwrap().json().await.unwrap();
    assert!(evil["is_error"].as_bool().unwrap());
    assert!(!std::env::temp_dir().join("evil.txt").exists());

    let miss: serde_json::Value = exec(
        "apply_patch",
        serde_json::json!({
            "path": "f.txt",
            "patch": "--- a/f\n+++ b/f\n@@ -1 +1 @@\n-nope\n+yes\n",
        }),
    )
    .send().await.unwrap().json().await.unwrap();
    assert!(miss["is_error"].as_bool().unwrap());
    let _ = std::fs::remove_dir_all(&root);
}

#[tokio::test]
#[serial_test::serial]
async fn node_mesh_loopback_uses_identical_schema() {
    let (base, root) = spawn().await;
    let c = client();
    c.put(format!("{base}/v1/workspace/file"))
        .json(&serde_json::json!({"path": "notes.txt", "content": "indigo keeps the lantern\n"}))
        .send().await.unwrap();

    // register self as a worker: same payloads cross the same HTTP boundary.
    let reg: serde_json::Value = c
        .post(format!("{base}/v1/nodes/register"))
        .json(&serde_json::json!({
            "id": "loop", "profile": "edge_quantized",
            "models": ["mock"], "endpoint": base,
        }))
        .send().await.unwrap().json().await.unwrap();
    assert_eq!(reg["registered"]["id"], "loop");

    let nodes: serde_json::Value =
        c.get(format!("{base}/v1/nodes")).send().await.unwrap().json().await.unwrap();
    assert_eq!(nodes["nodes"].as_array().unwrap().len(), 1);

    let out: serde_json::Value = c
        .post(format!("{base}/v1/nodes/dispatch"))
        .json(&serde_json::json!({
            "kind": "analysis", "node_id": "loop",
            "arguments": {"pattern": "lantern", "path": ""},
        }))
        .send().await.unwrap().json().await.unwrap();
    assert!(out["result"]["output"].as_str().unwrap().contains("lantern"));

    let missing = c
        .post(format!("{base}/v1/nodes/dispatch"))
        .json(&serde_json::json!({"kind": "lint", "node_id": "ghost", "arguments": {}}))
        .send().await.unwrap();
    assert_eq!(missing.status(), 404);

    // register an unreachable node and confirm a typed 502, not a hang.
    c.post(format!("{base}/v1/nodes/register"))
        .json(&serde_json::json!({
            "id": "dead", "profile": "edge_quantized",
            "models": [], "endpoint": "http://127.0.0.1:1",
        }))
        .send().await.unwrap();
    let bad = c
        .post(format!("{base}/v1/nodes/dispatch"))
        .json(&serde_json::json!({"kind": "lint", "node_id": "dead", "arguments": {"command": "true"}}))
        .send().await.unwrap();
    assert_eq!(bad.status(), 502);
    let _ = std::fs::remove_dir_all(&root);
}

#[tokio::test]
#[serial_test::serial]
#[serial_test::serial]
async fn thermal_critical_unloads() {
    std::env::set_var("OFFCODER_THERMAL_LEVEL", "critical");
    let (base, root) = spawn().await;
    let c = client();
    let resp = c
        .post(format!("{base}/v1/chat/completions"))
        .json(&serde_json::json!({"messages": [{"role": "user", "content": "hi"}]}))
        .send().await.unwrap();
    assert_eq!(resp.status(), 503);
    let body = resp.text().await.unwrap();
    assert!(body.contains("thermal_unload"));
    std::env::remove_var("OFFCODER_THERMAL_LEVEL");
    let _ = std::fs::remove_dir_all(&root);
}
