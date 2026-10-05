use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;

use crate::workspace::ProjectEnv;

/// One tool in OpenAI function-calling schema shape, serialized identically
/// on macOS and edge endpoints.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ToolDef {
    pub name: String,
    pub description: String,
    pub parameters: serde_json::Value,
}

impl ToolDef {
    pub fn schema(&self) -> serde_json::Value {
        serde_json::json!({
            "type": "function",
            "function": {
                "name": self.name,
                "description": self.description,
                "parameters": self.parameters,
            }
        })
    }
}

pub type ToolFn =
    Arc<dyn Fn(serde_json::Value, Arc<dyn ProjectEnv>) -> ToolOutcome + Send + Sync>;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ToolOutcome {
    pub output: String,
    pub is_error: bool,
}

impl ToolOutcome {
    pub fn ok(output: impl Into<String>) -> Self {
        Self { output: output.into(), is_error: false }
    }
    pub fn err(output: impl Into<String>) -> Self {
        Self { output: output.into(), is_error: true }
    }
}

/// Standardized tool-calling protocol. Registration and dispatch are pure
/// core; only [`ProjectEnv`] differs per platform.
#[derive(Clone, Default)]
pub struct ToolRegistry {
    defs: HashMap<String, (ToolDef, ToolFn)>,
}

impl ToolRegistry {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn register(&mut self, def: ToolDef, f: ToolFn) {
        self.defs.insert(def.name.clone(), (def, f));
    }

    pub fn schemas(&self) -> Vec<serde_json::Value> {
        self.defs.values().map(|(d, _)| d.schema()).collect()
    }

    pub fn dispatch(
        &self,
        name: &str,
        args: serde_json::Value,
        env: Arc<dyn ProjectEnv>,
    ) -> ToolOutcome {
        match self.defs.get(name) {
            Some((_, f)) => f(args, env),
            None => ToolOutcome::err(format!("unknown tool: {name}")),
        }
    }

    /// Sequential fan-out for the edge tier: one thread, deterministic order.
    pub fn dispatch_seq(
        &self,
        calls: &[(String, serde_json::Value)],
        env: Arc<dyn ProjectEnv>,
    ) -> Vec<ToolOutcome> {
        calls.iter().map(|(n, a)| self.dispatch(n, a.clone(), env.clone())).collect()
    }

    /// Parallel fan-out for the desktop tier: each call runs on the blocking
    /// pool (tool fns are synchronous), results reordered to call order.
    pub async fn dispatch_parallel(
        &self,
        calls: Vec<(String, serde_json::Value)>,
        env: Arc<dyn ProjectEnv>,
    ) -> Vec<ToolOutcome> {
        let mut handles = vec![];
        for (name, args) in calls {
            let f = self.defs.get(&name).map(|(_, f)| f.clone());
            let env = env.clone();
            handles.push(tokio::task::spawn_blocking(move || match f {
                Some(f) => f(args, env),
                None => ToolOutcome::err(format!("unknown tool: {name}")),
            }));
        }
        let mut out = vec![];
        for h in handles {
            out.push(h.await.unwrap_or_else(|e| ToolOutcome::err(format!("join: {e}"))));
        }
        out
    }
}

fn arg_str(args: &serde_json::Value, key: &str) -> String {
    args.get(key).and_then(|v| v.as_str()).unwrap_or("").to_string()
}

/// Built-in harness tools, identical on every host.
pub fn standard_registry() -> ToolRegistry {
    let mut reg = ToolRegistry::new();
    let obj = |props: serde_json::Value, required: &[&str]| {
        serde_json::json!({ "type": "object", "properties": props, "required": required })
    };

    reg.register(
        ToolDef {
            name: "read_file".into(),
            description: "Read a workspace-relative file as text.".into(),
            parameters: obj(
                serde_json::json!({ "path": { "type": "string" } }),
                &["path"],
            ),
        },
        Arc::new(|args, env| match env.read_file(&arg_str(&args, "path")) {
            Ok(text) => ToolOutcome::ok(text),
            Err(e) => ToolOutcome::err(e),
        }),
    );

    reg.register(
        ToolDef {
            name: "list_dir".into(),
            description: "List a workspace-relative directory.".into(),
            parameters: obj(
                serde_json::json!({ "path": { "type": "string" } }),
                &["path"],
            ),
        },
        Arc::new(|args, env| match env.list_dir(&arg_str(&args, "path")) {
            Ok(entries) => ToolOutcome::ok(entries.join("\n")),
            Err(e) => ToolOutcome::err(e),
        }),
    );

    reg.register(
        ToolDef {
            name: "grep_search".into(),
            description: "Substring search across workspace files.".into(),
            parameters: obj(
                serde_json::json!({
                    "pattern": { "type": "string" },
                    "path": { "type": "string" },
                }),
                &["pattern"],
            ),
        },
        Arc::new(|args, env| {
            let hits = env.grep(&arg_str(&args, "pattern"), &arg_str(&args, "path"));
            ToolOutcome::ok(hits.join("\n"))
        }),
    );

    reg.register(
        ToolDef {
            name: "write_file".into(),
            description: "Create or overwrite a workspace-relative file.".into(),
            parameters: obj(
                serde_json::json!({
                    "path": { "type": "string" },
                    "content": { "type": "string" },
                }),
                &["path", "content"],
            ),
        },
        Arc::new(|args, env| match env.write_file(&arg_str(&args, "path"), &arg_str(&args, "content")) {
            Ok(()) => ToolOutcome::ok("written"),
            Err(e) => ToolOutcome::err(e),
        }),
    );

    reg.register(
        ToolDef {
            name: "apply_patch".into(),
            description: "Apply a minimal unified diff to a workspace file; refuses escapes and anchor misses.".into(),
            parameters: obj(
                serde_json::json!({
                    "path": { "type": "string" },
                    "patch": { "type": "string" },
                }),
                &["path", "patch"],
            ),
        },
        Arc::new(|args, env| {
            let path = arg_str(&args, "path");
            let patch = arg_str(&args, "patch");
            match env.read_file(&path) {
                Ok(original) => match crate::patch::apply_unified_patch(&original, &patch) {
                    Ok(next) => match env.write_file(&path, &next) {
                        Ok(()) => ToolOutcome::ok(format!("patched {path}")),
                        Err(e) => ToolOutcome::err(e),
                    },
                    Err(e) => ToolOutcome::err(format!("patch refused: {e}")),
                },
                Err(e) => ToolOutcome::err(e),
            }
        }),
    );

    reg.register(
        ToolDef {
            name: "run_command".into(),
            description: "Execute a shell command sandboxed to the workspace root.".into(),
            parameters: obj(
                serde_json::json!({ "command": { "type": "string" } }),
                &["command"],
            ),
        },
        Arc::new(|args, env| match env.run_command(&arg_str(&args, "command")) {
            Ok(out) => ToolOutcome::ok(out),
            Err(e) => ToolOutcome::err(e),
        }),
    );

    reg
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_env() -> Arc<dyn ProjectEnv> {
        Arc::new(crate::workspace::VfsProjectEnv::new())
    }

    #[test]
    fn unknown_tool_is_typed_error() {
        let out = standard_registry().dispatch("nope", serde_json::json!({}), test_env());
        assert!(out.is_error);
    }

    #[tokio::test]
    async fn parallel_and_sequential_agree() {
        let reg = standard_registry();
        let env = test_env();
        env.write_file("n.txt", "1").unwrap();
        let calls = vec![
            ("read_file".to_string(), serde_json::json!({"path": "n.txt"})),
            ("list_dir".to_string(), serde_json::json!({"path": ""})),
        ];
        let seq = reg.dispatch_seq(&calls, env.clone());
        let par = reg.dispatch_parallel(calls, env).await;
        assert_eq!(seq.len(), par.len());
        for (a, b) in seq.iter().zip(par.iter()) {
            assert_eq!(a.output, b.output);
            assert_eq!(a.is_error, b.is_error);
        }
    }

    #[test]
    fn apply_patch_round_trip_and_refusal() {
        let reg = standard_registry();
        let env = test_env();
        env.write_file("f.txt", "a\nb\nc\n").unwrap();
        let ok = reg.dispatch(
            "apply_patch",
            serde_json::json!({
                "path": "f.txt",
                "patch": "--- a/f\n+++ b/f\n@@ -1,3 +1,3 @@\n a\n-b\n+B\n c\n",
            }),
            env.clone(),
        );
        assert!(!ok.is_error, "{}", ok.output);
        assert_eq!(env.read_file("f.txt").unwrap(), "a\nB\nc\n");
        let bad = reg.dispatch(
            "apply_patch",
            serde_json::json!({"path": "../evil", "patch": "x"}),
            env,
        );
        assert!(bad.is_error);
    }
}
