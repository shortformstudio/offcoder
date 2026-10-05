//! Phase 3: hardware profile detection and bounded resource management.
//!
//! Startup picks exactly one [`ActiveProfile`]:
//! - macOS Desktop: 32k–128k context scaled by RAM, parallel tool fan-out,
//!   Metal unified-memory budget capped at 75% of system RAM.
//! - Edge/Mobile: 4k–8k context, strictly sequential execution, aggressive
//!   throttling, backend unload on thermal warnings.

use serde::{Deserialize, Serialize};
use std::sync::Mutex;

use crate::backend::PlatformProfile;

/// Thermal pressure level. macOS reads the kernel thermal level when
/// available; `OFFCODER_THERMAL_LEVEL` overrides for tests and edge hosts.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ThermalState {
    Nominal,
    Fair,
    Serious,
    Critical,
}

impl ThermalState {
    pub fn current() -> Self {
        if let Ok(v) = std::env::var("OFFCODER_THERMAL_LEVEL") {
            return match v.to_lowercase().as_str() {
                "fair" => ThermalState::Fair,
                "serious" => ThermalState::Serious,
                "critical" => ThermalState::Critical,
                _ => ThermalState::Nominal,
            };
        }
        #[cfg(target_os = "macos")]
        {
            // kern.thermal_level is absent on most builds; any readable
            // elevated value counts as serious. Failure = nominal.
            if let Ok(out) = std::process::Command::new("sysctl")
                .arg("-n")
                .arg("kern.thermal_level")
                .output()
            {
                if let Ok(text) = String::from_utf8(out.stdout) {
                    if text.trim().parse::<i64>().unwrap_or(0) > 0 {
                        return ThermalState::Serious;
                    }
                }
            }
        }
        ThermalState::Nominal
    }

    pub fn must_unload(self) -> bool {
        self == ThermalState::Critical
    }
}

/// Forced profile selector: `OFFCODER_PROFILE=edge` pins the edge tier
/// (used by mobile nodes and tests); anything else auto-detects.
fn forced_edge() -> bool {
    std::env::var("OFFCODER_PROFILE")
        .map(|v| v.eq_ignore_ascii_case("edge") || v.eq_ignore_ascii_case("mobile"))
        .unwrap_or(false)
}

#[cfg(target_os = "macos")]
fn system_ram_mb() -> u64 {
    std::process::Command::new("sysctl")
        .arg("-n")
        .arg("hw.memsize")
        .output()
        .ok()
        .and_then(|o| String::from_utf8(o.stdout).ok())
        .and_then(|t| t.trim().parse::<u64>().ok())
        .map(|b| b / (1024 * 1024))
        .unwrap_or(8192)
}

#[cfg(not(target_os = "macos"))]
fn system_ram_mb() -> u64 {
    2048
}

/// The live, detected hardware profile. Exactly one exists per process.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ActiveProfile {
    pub platform: PlatformProfile,
    /// Admitted context window in tokens.
    pub context_tokens: usize,
    /// Unified-memory / RAM budget in MB (macOS: up to 75% of system RAM).
    pub memory_budget_mb: u64,
    /// KV-cache hard cap in MB (subset of the memory budget).
    pub kv_cache_quota_mb: u64,
    /// Max concurrent tool executions (1 = strictly sequential).
    pub max_parallel_tools: usize,
}

impl ActiveProfile {
    pub fn detect() -> Self {
        if forced_edge() || cfg!(target_os = "ios") {
            return Self {
                platform: PlatformProfile::EdgeQuantized,
                context_tokens: 8192,
                memory_budget_mb: 1024,
                kv_cache_quota_mb: PlatformProfile::EdgeQuantized.kv_cache_quota_mb(),
                max_parallel_tools: 1,
            };
        }
        // macOS desktop: scale context 32k–128k with installed RAM.
        let ram = system_ram_mb();
        let context_tokens = match ram {
            0..=8192 => 32768,
            8193..=32768 => 65536,
            _ => 131072,
        };
        Self {
            platform: PlatformProfile::MacosMetal,
            context_tokens,
            memory_budget_mb: ram * 3 / 4,
            kv_cache_quota_mb: PlatformProfile::MacosMetal.kv_cache_quota_mb(),
            max_parallel_tools: 8,
        }
    }

    pub fn sequential(&self) -> bool {
        self.max_parallel_tools <= 1
    }
}

/// Bounded KV-cache ledger. Every completion reserves its estimate up front
/// and releases on done/error, so usage never exceeds quota and explicit
/// teardown returns the ledger to exactly zero.
#[derive(Debug)]
pub struct ResourceLedger {
    quota_bytes: u64,
    used_bytes: u64,
}

impl ResourceLedger {
    pub fn new(quota_bytes: u64) -> Self {
        Self { quota_bytes, used_bytes: 0 }
    }

    /// Bytes per token under the active profile (conservative fp16 KV math).
    pub fn bytes_per_token(platform: PlatformProfile) -> u64 {
        match platform {
            PlatformProfile::MacosMetal => 2048,
            PlatformProfile::EdgeQuantized => 1024,
        }
    }

    pub fn reserve(&mut self, tokens: usize, platform: PlatformProfile) -> Result<u64, String> {
        let need = tokens as u64 * Self::bytes_per_token(platform);
        if self.used_bytes + need > self.quota_bytes {
            return Err(format!(
                "kv quota exceeded: need {need}B, {}B of {}B free",
                self.quota_bytes.saturating_sub(self.used_bytes),
                self.quota_bytes,
            ));
        }
        self.used_bytes += need;
        Ok(need)
    }

    pub fn release(&mut self, bytes: u64) {
        self.used_bytes = self.used_bytes.saturating_sub(bytes);
    }

    pub fn teardown(&mut self) {
        self.used_bytes = 0;
    }

    pub fn used_bytes(&self) -> u64 {
        self.used_bytes
    }

    pub fn quota_bytes(&self) -> u64 {
        self.quota_bytes
    }
}

/// Thread-safe ledger wrapper owned by backends.
#[derive(Debug)]
pub struct SharedLedger(Mutex<ResourceLedger>);

impl SharedLedger {
    pub fn new(quota_bytes: u64) -> Self {
        Self(Mutex::new(ResourceLedger::new(quota_bytes)))
    }

    pub fn reserve(&self, tokens: usize, platform: PlatformProfile) -> Result<u64, String> {
        self.0.lock().map_err(|e| e.to_string())?.reserve(tokens, platform)
    }

    pub fn release(&self, bytes: u64) {
        if let Ok(mut ledger) = self.0.lock() {
            ledger.release(bytes);
        }
    }

    pub fn teardown(&self) {
        if let Ok(mut ledger) = self.0.lock() {
            ledger.teardown();
        }
    }

    pub fn used_bytes(&self) -> u64 {
        self.0.lock().map(|l| l.used_bytes()).unwrap_or(u64::MAX)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn desktop_profile_scales_with_ram() {
        let p = ActiveProfile::detect();
        if !forced_edge() && cfg!(target_os = "macos") {
            assert!(p.context_tokens >= 32768);
            assert!(p.memory_budget_mb >= 6144);
            assert!(!p.sequential());
        }
    }

    #[test]
    fn edge_profile_is_constrained() {
        std::env::set_var("OFFCODER_PROFILE", "edge");
        let p = ActiveProfile::detect();
        std::env::remove_var("OFFCODER_PROFILE");
        assert_eq!(p.platform, PlatformProfile::EdgeQuantized);
        assert!(p.context_tokens <= 8192);
        assert!(p.sequential());
    }

    #[test]
    fn ledger_enforces_quota_and_teardown_zeroes() {
        let ledger = SharedLedger::new(4096);
        assert!(ledger.reserve(1, PlatformProfile::EdgeQuantized).is_ok());
        assert_eq!(ledger.used_bytes(), 1024);
        assert!(ledger.reserve(4, PlatformProfile::EdgeQuantized).is_err());
        ledger.teardown();
        assert_eq!(ledger.used_bytes(), 0);
    }

    #[test]
    fn thermal_critical_forces_unload() {
        std::env::set_var("OFFCODER_THERMAL_LEVEL", "critical");
        let t = ThermalState::current();
        std::env::remove_var("OFFCODER_THERMAL_LEVEL");
        assert!(t.must_unload());
    }
}
