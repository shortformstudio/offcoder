use serde::{Deserialize, Serialize};

/// Typed orchestration events. Every streaming endpoint emits these as
/// Server-Sent Events with `event: <kind>` and a JSON `data:` payload.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum OrchestratorEvent {
    Token { delta: String },
    Reasoning { delta: String },
    ToolCall { id: String, name: String, arguments: String },
    ToolResult { id: String, output: String },
    Process { state: String, detail: String },
    Done { completion_tokens: u32 },
    Error { code: String, message: String },
}

impl OrchestratorEvent {
    pub fn sse_kind(&self) -> &'static str {
        match self {
            OrchestratorEvent::Token { .. } => "token",
            OrchestratorEvent::Reasoning { .. } => "reasoning",
            OrchestratorEvent::ToolCall { .. } => "tool_call",
            OrchestratorEvent::ToolResult { .. } => "tool_result",
            OrchestratorEvent::Process { .. } => "process",
            OrchestratorEvent::Done { .. } => "done",
            OrchestratorEvent::Error { .. } => "error",
        }
    }

    pub fn to_sse(&self) -> String {
        let data = serde_json::to_string(self).unwrap_or_else(|_| "{\"kind\":\"error\"}".into());
        format!("event: {}\ndata: {}\n\n", self.sse_kind(), data)
    }
}
