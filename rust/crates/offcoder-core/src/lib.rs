//! offcoder-core: engine-agnostic orchestration primitives shared by every
//! offcoder host (macOS Metal tier today, mobile/edge nodes tomorrow).
//!
//! - [`backend::ModelBackend`]: unified dispatch across hardware backends.
//! - [`prompt`]: identical tokenization-adjacent prompt formatting everywhere.
//! - [`events`]: typed SSE JSON events for tokens, diagnostics, steps.
//! - [`tools::ToolRegistry`]: tool calls serialized identically per endpoint.
//! - [`workspace::ProjectEnv`]: isolated workspace (fs on macOS, VFS on edge).

pub mod backend;
pub mod events;
pub mod prompt;
pub mod tools;
pub mod workspace;
