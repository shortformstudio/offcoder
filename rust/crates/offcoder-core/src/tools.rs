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
