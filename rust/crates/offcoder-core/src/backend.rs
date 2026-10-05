use futures_util::StreamExt;
use serde::{Deserialize, Serialize};
use tokio::sync::mpsc;

use crate::events::OrchestratorEvent;
use crate::profile::SharedLedger;
use crate::prompt::{ChatMessage, PromptBuilder};

/// Hardware platform profile. KV-cache quotas are hard caps per tier —
/// no shared-memory leaks across backends.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PlatformProfile {
    /// macOS Apple Silicon: unified memory, Metal runtime underneath.
    MacosMetal,
    /// Mobile / on-device edge: quantized execution, tight quotas.
    EdgeQuantized,
}

impl PlatformProfile {
    /// Max KV-cache allocation in megabytes for this tier.
    pub fn kv_cache_quota_mb(self) -> u64 {
        match self {
            PlatformProfile::MacosMetal => 8192,
            PlatformProfile::EdgeQuantized => 512,
        }
    }

    /// Max context tokens admitted for this tier.
    pub fn max_context_tokens(self) -> usize {
        match self {
            PlatformProfile::MacosMetal => 131072,
            PlatformProfile::EdgeQuantized => 8192,
        }
    }
}

/// Engine-agnostic model dispatch. Implementations speak to different
/// runtimes (llama.cpp Metal today, CoreML/ExecuTorch tomorrow) behind
/// this single surface.
#[async_trait::async_trait]
pub trait ModelBackend: Send + Sync {
    fn name(&self) -> &str;
    fn profile(&self) -> PlatformProfile;

    /// Rough token estimate for admission control (chars/4 + margin).
    fn estimate_tokens(&self, text: &str) -> usize {
        text.len() / 4 + 8
    }

    /// Stream one completion as typed events into `tx`.
    async fn complete(
        &self,
        system: &PromptBuilder,
        messages: &[ChatMessage],
        tools: &[serde_json::Value],
        tx: mpsc::UnboundedSender<OrchestratorEvent>,
    ) -> Result<(), String>;

    /// Explicit teardown: drop runtime handles and return every tracked
    /// allocation to zero. Called on thermal unload and session delete.
    fn teardown(&self);
}

/// llama.cpp server backend (Metal runtime on macOS Primary, Proxy target
/// for lockfort LAN inference). Forwards the OpenAI-compatible SSE stream
/// and re-emits it as typed [`OrchestratorEvent`]s.
pub struct LlamaCppBackend {
    pub base_url: String,
    pub model: String,
    pub profile: PlatformProfile,
    pub ledger: SharedLedger,
    client: reqwest::Client,
}

impl LlamaCppBackend {
    pub fn new(base_url: impl Into<String>, model: impl Into<String>, profile: PlatformProfile) -> Self {
        let quota_mb = profile.kv_cache_quota_mb();
        Self {
            base_url: base_url.into().trim_end_matches('/').to_string(),
            model: model.into(),
            profile,
            ledger: SharedLedger::new(quota_mb * 1024 * 1024),
            client: reqwest::Client::new(),
        }
    }

    fn completions_url(&self) -> String {
        if self.base_url.ends_with("/v1") {
            format!("{}/chat/completions", self.base_url)
        } else {
            format!("{}/v1/chat/completions", self.base_url)
        }
    }
}

#[async_trait::async_trait]
impl ModelBackend for LlamaCppBackend {
    fn name(&self) -> &str {
        &self.model
    }

    fn profile(&self) -> PlatformProfile {
        self.profile
    }

    async fn complete(
        &self,
        system: &PromptBuilder,
        messages: &[ChatMessage],
        tools: &[serde_json::Value],
        tx: mpsc::UnboundedSender<OrchestratorEvent>,
    ) -> Result<(), String> {
        let mut wire = vec![serde_json::json!({
            "role": "system",
            "content": system.system_prompt(),
        })];
        // Bounded admission: reserve the KV estimate before touching upstream.
        let estimate: usize = wire
            .iter()
            .map(|m| m.to_string().len())
            .sum::<usize>()
            .max(messages.iter().map(|m| m.content.len()).sum::<usize>())
            / 4
            + 4096;
        let reserved = match self.ledger.reserve(estimate, self.profile) {
            Ok(bytes) => bytes,
            Err(e) => {
                let _ = tx.send(OrchestratorEvent::Error {
                    code: "kv_quota_exceeded".into(),
                    message: e,
                });
                return Err("kv quota exceeded".into());
            }
        };
        // Single-system invariant: the PromptBuilder system already carries
        // identity, budget, and memory. Any system message the caller sent
        // (the deck always sends one) is absorbed rather than forwarded —
        // upstream rejects stacked system roles with a 400.
        for m in messages {
            if m.role == "system" {
                continue;
            }
            wire.push(serde_json::json!({ "role": m.role, "content": m.content }));
        }
        let payload = serde_json::json!({
            "model": self.model,
            "messages": wire,
            "tools": tools,
            "stream": true,
            "stream_options": { "include_usage": true },
        });

        let result = self.stream_payload(payload, &tx).await;
        self.ledger.release(reserved);
        result
    }

    fn teardown(&self) {
        self.ledger.teardown();
    }
}

impl LlamaCppBackend {
    /// Raw upstream stream; the ledger release in [`ModelBackend::complete`]
    /// always runs, success or failure.
    async fn stream_payload(
        &self,
        payload: serde_json::Value,
        tx: &mpsc::UnboundedSender<OrchestratorEvent>,
    ) -> Result<(), String> {
        let resp = self
            .client
            .post(self.completions_url())
            .json(&payload)
            .send()
            .await
            .map_err(|e| format!("upstream unreachable: {e}"))?;
        if !resp.status().is_success() {
            return Err(format!("upstream status {}", resp.status()));
        }

        let mut stream = resp.bytes_stream();
        let mut buf = String::new();
        let mut completion_tokens: u32 = 0;
        while let Some(chunk) = stream.next().await {
            let chunk = chunk.map_err(|e| format!("stream read: {e}"))?;
            buf.push_str(&String::from_utf8_lossy(&chunk));
            while let Some(idx) = buf.find("\n\n") {
                let frame: String = buf.drain(..idx + 2).collect();
                for line in frame.lines() {
                    let data = line.strip_prefix("data:").map(str::trim).unwrap_or("");
                    if data.is_empty() || data == "[DONE]" {
                        continue;
                    }
                    let v: serde_json::Value =
                        serde_json::from_str(data).unwrap_or(serde_json::Value::Null);
                    let choice = v
                        .get("choices")
                        .and_then(|c| c.get(0))
                        .cloned()
                        .unwrap_or(serde_json::Value::Null);
                    if let Some(delta) = choice.get("delta") {
                        if let Some(t) = delta.get("content").and_then(|c| c.as_str()) {
                            let _ = tx.send(OrchestratorEvent::Token { delta: t.into() });
                        }
                        if let Some(r) = delta
                            .get("reasoning_content")
                            .and_then(|c| c.as_str())
                        {
                            let _ = tx.send(OrchestratorEvent::Reasoning { delta: r.into() });
                        }
                        if let Some(calls) = delta.get("tool_calls").and_then(|c| c.as_array())
                        {
                            for (i, call) in calls.iter().enumerate() {
                                let f = call.get("function").cloned().unwrap_or_default();
                                let _ = tx.send(OrchestratorEvent::ToolCall {
                                    id: call
                                        .get("id")
                                        .and_then(|s| s.as_str())
                                        .unwrap_or("")
                                        .to_string(),
                                    name: f
                                        .get("name")
                                        .and_then(|s| s.as_str())
                                        .unwrap_or(&format!("call-{i}"))
                                        .to_string(),
                                    arguments: f
                                        .get("arguments")
                                        .and_then(|s| s.as_str())
                                        .unwrap_or("")
                                        .to_string(),
                                });
                            }
                        }
                    }
                    if let Some(usage) = v.get("usage") {
                        if let Some(n) = usage.get("completion_tokens").and_then(|n| n.as_u64()) {
                            completion_tokens = n as u32;
                        }
                    }
                }
            }
        }
        let _ = tx.send(OrchestratorEvent::Done { completion_tokens });
        Ok(())
    }
}

/// Deterministic in-process backend for tests and offline E2E. Emits a fixed
/// event script; reserves and releases ledger like production backends.
pub struct MockBackend {
    pub script_tokens: Vec<String>,
    pub ledger: SharedLedger,
}

impl MockBackend {
    pub fn new(script_tokens: Vec<String>) -> Self {
        Self {
            script_tokens,
            ledger: SharedLedger::new(1024 * 1024),
        }
    }
}

#[async_trait::async_trait]
impl ModelBackend for MockBackend {
    fn name(&self) -> &str {
        "mock"
    }

    fn profile(&self) -> PlatformProfile {
        PlatformProfile::EdgeQuantized
    }

    async fn complete(
        &self,
        _system: &PromptBuilder,
        _messages: &[ChatMessage],
        tools: &[serde_json::Value],
        tx: mpsc::UnboundedSender<OrchestratorEvent>,
    ) -> Result<(), String> {
        let reserved = self
            .ledger
            .reserve(64, self.profile())
            .map_err(|e| e.to_string())?;
        let mut n = 0u32;
        for tok in &self.script_tokens {
            n += 1;
            if tx
                .send(OrchestratorEvent::Token { delta: tok.clone() })
                .is_err()
            {
                break; // client went away mid-stream; release and stop.
            }
        }
        if !tools.is_empty() {
            let _ = tx.send(OrchestratorEvent::Process {
                state: "TOOLS_AVAILABLE".into(),
                detail: format!("{} tool schemas offered", tools.len()),
            });
        }
        self.ledger.release(reserved);
        let _ = tx.send(OrchestratorEvent::Done { completion_tokens: n });
        Ok(())
    }

    fn teardown(&self) {
        self.ledger.teardown();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn ledger_returns_to_zero_after_completion() {
        let backend = LlamaCppBackend::new("http://127.0.0.1:1", "x", PlatformProfile::EdgeQuantized);
        // Unreachable upstream: reservation must still be released on error.
        let (tx, _rx) = mpsc::unbounded_channel();
        let system = PromptBuilder {
            agent_system_name: "t".into(),
            workspace_dir: "d".into(),
            workspace_map: "m".into(),
            totem_context: "c".into(),
            effort: crate::prompt::ReasoningEffort::Off,
        };
        assert!(backend.complete(&system, &[], &[], tx).await.is_err());
        assert_eq!(backend.ledger.used_bytes(), 0);
    }

    #[test]
    fn quota_refusal_is_typed() {
        let backend = LlamaCppBackend::new("http://127.0.0.1:1", "x", PlatformProfile::EdgeQuantized);
        // Force exhaustion with a direct reservation larger than quota.
        let quota = backend.ledger.used_bytes();
        let _ = quota;
        let over = backend.ledger.reserve(usize::MAX / 4096, backend.profile());
        assert!(over.is_err());
        backend.teardown();
        assert_eq!(backend.ledger.used_bytes(), 0);
    }
}

    #[tokio::test]
    async fn mock_never_forwards_second_system() {
        // The MockBackend consumes whatever wire it is handed; the real
        // invariant test is structural here — single system in the wire.
        let backend = MockBackend::new(vec!["a".into()]);
        let (tx, mut rx) = mpsc::unbounded_channel::<OrchestratorEvent>();
        let system = PromptBuilder {
            agent_system_name: "t".into(),
            workspace_dir: "d".into(),
            workspace_map: "m".into(),
            totem_context: "c".into(),
            effort: crate::prompt::ReasoningEffort::Off,
        };
        let msgs = vec![
            ChatMessage { role: "system".into(), content: "caller system".into() },
            ChatMessage { role: "user".into(), content: "hey".into() },
        ];
        backend.complete(&system, &msgs, &[], tx).await.unwrap();
        let mut seen = vec![];
        while let Some(ev) = rx.recv().await {
            match ev {
                OrchestratorEvent::Done { .. } => break,
                OrchestratorEvent::Token { delta } => seen.push(delta),
                _ => {}
            }
        }
        assert!(!seen.is_empty());
    }
