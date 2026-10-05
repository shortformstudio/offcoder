use std::collections::HashMap;
use std::path::{Component, PathBuf};
use std::sync::RwLock;

/// Isolated workspace abstraction. macOS runs [`FsProjectEnv`] (native
/// process execution sandboxed to the root); edge nodes run [`VfsProjectEnv`]
/// (in-process virtual FS, delegate-evaluated commands only).
pub trait ProjectEnv: Send + Sync {
    fn root_label(&self) -> String;
    fn read_file(&self, path: &str) -> Result<String, String>;
    fn write_file(&self, path: &str, content: &str) -> Result<(), String>;
    fn list_dir(&self, path: &str) -> Result<Vec<String>, String>;
    fn grep(&self, pattern: &str, path: &str) -> Vec<String>;
    fn run_command(&self, command: &str) -> Result<String, String>;
}

/// Reject escapes: the resolved path must stay inside the root.
fn join_root(root: &std::path::Path, rel: &str) -> Result<PathBuf, String> {
    if rel.starts_with('/') {
        return Err("absolute paths are outside the workspace".into());
    }
    let rel = rel.trim_start_matches('/');
    let mut out = root.to_path_buf();
    for comp in std::path::Path::new(rel).components() {
        match comp {
            Component::Normal(seg) => out.push(seg),
            Component::CurDir => {}
            Component::ParentDir | Component::RootDir | Component::Prefix(_) => {
                return Err("path escapes workspace root".into())
            }
        }
    }
    Ok(out)
}

/// Native macOS environment: real FS CRUD plus `sh -c` execution with the
/// workspace root as cwd. Every op is root-sandboxed by [`join_root`].
pub struct FsProjectEnv {
    pub root: PathBuf,
}

impl FsProjectEnv {
    pub fn new(root: impl Into<PathBuf>) -> Self {
        Self { root: root.into() }
    }
}

impl ProjectEnv for FsProjectEnv {
    fn root_label(&self) -> String {
        self.root.display().to_string()
    }

    fn read_file(&self, path: &str) -> Result<String, String> {
        let full = join_root(&self.root, path)?;
        std::fs::read_to_string(&full).map_err(|e| format!("read {}: {e}", full.display()))
    }

    fn write_file(&self, path: &str, content: &str) -> Result<(), String> {
        let full = join_root(&self.root, path)?;
        if let Some(parent) = full.parent() {
            std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
        }
        std::fs::write(&full, content).map_err(|e| format!("write {}: {e}", full.display()))
    }

    fn list_dir(&self, path: &str) -> Result<Vec<String>, String> {
        let full = join_root(&self.root, path)?;
        let mut out = vec![];
        let rd = std::fs::read_dir(&full).map_err(|e| format!("list {}: {e}", full.display()))?;
        for entry in rd.flatten() {
            out.push(entry.file_name().to_string_lossy().into_owned());
        }
        out.sort();
        Ok(out)
    }

    fn grep(&self, pattern: &str, path: &str) -> Vec<String> {
        let mut hits = vec![];
        let Ok(entries) = self.list_dir(path) else { return hits };
        for name in entries {
            let rel = if path.is_empty() { name.clone() } else { format!("{path}/{name}") };
            if let Ok(text) = self.read_file(&rel) {
                for (i, line) in text.lines().enumerate() {
                    if line.contains(pattern) {
                        hits.push(format!("{rel}:{}: {}", i + 1, line.trim()));
                        if hits.len() >= 200 {
                            return hits;
                        }
                    }
                }
            }
        }
        hits
    }

    fn run_command(&self, command: &str) -> Result<String, String> {
        let out = std::process::Command::new("sh")
            .arg("-c")
            .arg(command)
            .current_dir(&self.root)
            .output()
            .map_err(|e| format!("spawn: {e}"))?;
        let mut text = String::from_utf8_lossy(&out.stdout).into_owned();
        let err = String::from_utf8_lossy(&out.stderr);
        if !err.is_empty() {
            text.push_str(&err);
        }
        if out.status.success() {
            Ok(text)
        } else {
            Err(format!("exit {}: {text}", out.status))
        }
    }
}

/// Edge environment: in-process virtual FS. Commands are delegate-evaluated
/// (deny-by-default here; hosts inject their evaluator).
pub struct VfsProjectEnv {
    files: RwLock<HashMap<String, String>>,
}

impl VfsProjectEnv {
    pub fn new() -> Self {
        Self { files: RwLock::new(HashMap::new()) }
    }

    fn norm(path: &str) -> Result<String, String> {
        if path.starts_with('/') {
            return Err("absolute paths are outside the workspace".into());
        }
        if path.contains("..") {
            return Err("path escapes workspace root".into());
        }
        Ok(path.to_string())
    }
}

impl Default for VfsProjectEnv {
    fn default() -> Self {
        Self::new()
    }
}

impl ProjectEnv for VfsProjectEnv {
    fn root_label(&self) -> String {
        "vfs://workspace".into()
    }

    fn read_file(&self, path: &str) -> Result<String, String> {
        let key = Self::norm(path)?;
        self.files
            .read()
            .map_err(|e| e.to_string())?
            .get(&key)
            .cloned()
            .ok_or_else(|| format!("no such file: {path}"))
    }

    fn write_file(&self, path: &str, content: &str) -> Result<(), String> {
        let key = Self::norm(path)?;
        self.files
            .write()
            .map_err(|e| e.to_string())?
            .insert(key, content.to_string());
        Ok(())
    }

    fn list_dir(&self, path: &str) -> Result<Vec<String>, String> {
        let prefix = Self::norm(path)?;
        let prefix = if prefix.is_empty() { String::new() } else { format!("{prefix}/") };
        let files = self.files.read().map_err(|e| e.to_string())?;
        let mut out: Vec<String> = files
            .keys()
            .filter_map(|k| {
                k.strip_prefix(&prefix).and_then(|rest| {
                    if rest.contains('/') || rest.is_empty() {
                        None
                    } else {
                        Some(rest.to_string())
                    }
                })
            })
            .collect();
        out.sort();
        Ok(out)
    }

    fn grep(&self, pattern: &str, path: &str) -> Vec<String> {
        let mut hits = vec![];
        if let Ok(entries) = self.list_dir(path) {
            for name in entries {
                let rel = if path.is_empty() { name } else { format!("{path}/{name}") };
                if let Ok(text) = self.read_file(&rel) {
                    for (i, line) in text.lines().enumerate() {
                        if line.contains(pattern) {
                            hits.push(format!("{rel}:{}: {}", i + 1, line.trim()));
                        }
                    }
                }
            }
        }
        hits
    }

    fn run_command(&self, _command: &str) -> Result<String, String> {
        Err("edge VFS denies raw shell; route through the host delegate evaluator".into())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn root_escape_refused() {
        let root = std::path::Path::new("/tmp/ws-root-test");
        assert!(join_root(root, "../../etc/passwd").is_err());
        assert!(join_root(root, "/absolute").is_err());
        assert!(join_root(root, "sub/dir/file.txt").is_ok());
    }

    #[test]
    fn fs_env_cannot_write_outside_root() {
        let dir = std::env::temp_dir().join("offcoder-ws-bound-test");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let env = FsProjectEnv::new(&dir);
        assert!(env.write_file("../escape.txt", "x").is_err());
        assert!(env.read_file("../escape.txt").is_err());
        assert!(env.write_file("ok.txt", "yes").is_ok());
        assert_eq!(env.read_file("ok.txt").unwrap(), "yes");
        let _ = std::fs::remove_dir_all(&dir);
        assert!(!std::env::temp_dir().join("escape.txt").exists());
    }

    #[test]
    fn vfs_denies_shell_and_escapes() {
        let env = VfsProjectEnv::new();
        assert!(env.run_command("ls").is_err());
        assert!(env.write_file("../x", "y").is_err());
        assert!(env.write_file("a.txt", "hi").is_ok());
        assert_eq!(env.list_dir("").unwrap(), vec!["a.txt".to_string()]);
    }
}

