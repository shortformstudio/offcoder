//! Acceptance: byte-for-byte serialization compatibility between macOS and
//! mobile payload schemas. These fixtures are the contract — any schema
//! change must update the fixtures deliberately, never silently.

use offcoder_core::events::OrchestratorEvent;
use offcoder_core::prompt::{ChatMessage, PromptBuilder, ReasoningEffort};
use offcoder_core::tools::standard_registry;

fn fixture(name: &str) -> String {
    let path = format!("{}/tests/fixtures/{name}", env!("CARGO_MANIFEST_DIR"));
    std::fs::read_to_string(path).unwrap().trim_end().to_string()
}

#[test]
fn event_token_bytes_stable() {
    let ev = OrchestratorEvent::Token { delta: "hi".into() };
    assert_eq!(serde_json::to_string(&ev).unwrap(), fixture("event_token.json"));
}

#[test]
fn event_round_trips() {
    for ev in [
        OrchestratorEvent::Reasoning { delta: "t".into() },
        OrchestratorEvent::ToolCall {
            id: "1".into(),
            name: "read_file".into(),
            arguments: "{}".into(),
        },
        OrchestratorEvent::ToolResult { id: "1".into(), output: "o".into() },
        OrchestratorEvent::Process { state: "S".into(), detail: "d".into() },
        OrchestratorEvent::Done { completion_tokens: 3 },
        OrchestratorEvent::Error { code: "c".into(), message: "m".into() },
    ] {
        let s = serde_json::to_string(&ev).unwrap();
        let back: OrchestratorEvent = serde_json::from_str(&s).unwrap();
        assert_eq!(serde_json::to_string(&back).unwrap(), s);
    }
}

#[test]
fn tool_schema_bytes_stable() {
    let reg = standard_registry();
    let schema = reg
        .schemas()
        .into_iter()
        .find(|s| s["function"]["name"] == "read_file")
        .expect("read_file schema");
    assert_eq!(serde_json::to_string(&schema).unwrap(), fixture("tool_read_file.json"));
}

#[test]
fn system_prompt_deterministic() {
    let mk = || PromptBuilder {
        agent_system_name: "Indigo".into(),
        workspace_dir: "/w".into(),
        workspace_map: "[a.txt]".into(),
        totem_context: "(t)".into(),
        effort: ReasoningEffort::Low,
    };
    assert_eq!(mk().system_prompt(), mk().system_prompt());
    let text = mk().system_prompt();
    assert!(text.contains("You are Indigo"));
    assert!(text.contains("REASONING BUDGET: minimal"));
    assert!(text.contains("Never call remember"));
}

#[test]
fn chat_message_bytes_stable() {
    let m = ChatMessage { role: "user".into(), content: "hey".into() };
    assert_eq!(
        serde_json::to_string(&m).unwrap(),
        r#"{"role":"user","content":"hey"}"#
    );
}
