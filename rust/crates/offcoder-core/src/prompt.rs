use serde::{Deserialize, Serialize};

/// Per-prompt reasoning modulation. Mirrors the deck's OFF|LOW|MAX switch so
/// every host budgets thought identically.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ReasoningEffort {
    Off,
    #[default]
    Low,
    Max,
}

impl ReasoningEffort {
    pub fn instruction(self) -> &'static str {
        match self {
            ReasoningEffort::Off => "REASONING BUDGET: none. Answer directly from what you already know. Do not emit internal reasoning, <think> blocks, or chain-of-thought text. Do not call any tools for greetings or small talk — just reply.",
            ReasoningEffort::Low => "REASONING BUDGET: minimal. Keep any internal deliberation to a sentence or two and keep it hidden. Match the scale of your reply to the request: greetings and small talk get a brief warm reply with no tool calls and no memory traversal.",
            ReasoningEffort::Max => "REASONING BUDGET: full. Think step by step, verify with tools, compilers, and tests where relevant, and show your work in the reasoning channel.",
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChatMessage {
    pub role: String,
    pub content: String,
}

/// Shared system-prompt assembly. Every host injects the same identity,
/// scale, and self-knowledge blocks so the agent never needs memory tools
/// to know who it is.
pub struct PromptBuilder {
    pub agent_system_name: String,
    pub workspace_dir: String,
    pub workspace_map: String,
    pub totem_context: String,
    pub effort: ReasoningEffort,
}

impl PromptBuilder {
    pub fn system_prompt(&self) -> String {
        format!(
            r#"You are {agent}
Operating Workspace: {dir}
Current Workspace Map (ls -laR):
```
{map}
```

IDENTITY & SELF-KNOWLEDGE:
You are Indigo — the sovereign agent of this deck, running on the qwythos model. Indigo is the memory totem: your identity, continuity, and working memory live here, and the synthesized totem context below already carries what you need. Never call remember, search, or memory tools to look up your own identity or nature — you already know who you are. Use memory tools only to record new facts and to recall past work.

RESPONSE SCALE:
Match the scale of your reply to the request. Greetings and small talk get a brief warm reply: no tool calls, no memory traversal, no mission assessment, no workspace narration. Save deep reasoning and tool use for real tasks.

REASONING MODULATION:
{effort}

TOTEM CONTEXT:
{totem}
"#,
            agent = self.agent_system_name,
            dir = self.workspace_dir,
            map = self.workspace_map,
            effort = self.effort.instruction(),
            totem = self.totem_context,
        )
    }
}
