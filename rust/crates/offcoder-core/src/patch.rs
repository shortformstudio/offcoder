//! Bounded unified-diff patch application. Every hunk targets a path that
//! must resolve inside the workspace root; anything else is refused before
//! a single byte is written.

/// One parsed hunk: exact context/removal lines that must match, plus
/// the lines to put in their place.
#[derive(Debug, PartialEq)]
struct Hunk {
    removals: Vec<String>,
    additions: Vec<String>,
}

/// Apply a minimal unified diff (`---`/`+++` headers, `@@` hunks, ` `/`-`/`+`
/// lines, `\ No newline` markers tolerated) to `original`. Returns the
/// patched text or a refusal. Fuzzy matching is deliberately absent: hunks
/// apply at the first exact anchor or not at all.
pub fn apply_unified_patch(original: &str, patch: &str) -> Result<String, String> {
    let mut target: Option<String> = None;
    let mut hunks: Vec<Hunk> = vec![];
    let mut current: Option<Hunk> = None;

    for raw in patch.lines() {
        if raw.starts_with("--- ") {
            continue;
        }
        if let Some(path) = raw.strip_prefix("+++ ") {
            let path = path.trim().trim_start_matches("b/").to_string();
            if path.contains("..") || path.starts_with('/') {
                return Err(format!("patch escapes workspace: {path}"));
            }
            target = Some(path);
            continue;
        }
        if raw.starts_with("@@") {
            if let Some(h) = current.take() {
                hunks.push(h);
            }
            current = Some(Hunk { removals: vec![], additions: vec![] });
            continue;
        }
        if raw.starts_with("\\ ") {
            continue;
        }
        let Some(h) = current.as_mut() else {
            if raw.trim().is_empty() {
                continue;
            }
            return Err("patch content outside a hunk".into());
        };
        match raw.chars().next() {
            Some(' ') => {
                let line = raw[1..].to_string();
                h.removals.push(line.clone());
                h.additions.push(line);
            }
            Some('-') => h.removals.push(raw[1..].to_string()),
            Some('+') => h.additions.push(raw[1..].to_string()),
            _ => return Err(format!("bad hunk line: {raw}")),
        }
    }
    if let Some(h) = current.take() {
        hunks.push(h);
    }
    if target.is_none() {
        return Err("patch has no target file".into());
    }
    if hunks.is_empty() {
        return Err("patch has no hunks".into());
    }

    let mut lines: Vec<String> = original.lines().map(|l| l.to_string()).collect();
    // Anchor each hunk sequentially at its first exact match.
    let mut cursor = 0;
    for hunk in &hunks {
        if hunk.removals.is_empty() {
            // Pure insertion at cursor.
            lines.splice(cursor..cursor, hunk.additions.clone());
            cursor += hunk.additions.len();
            continue;
        }
        let span = hunk.removals.len();
        let mut found = None;
        let mut i = cursor;
        while i + span <= lines.len() {
            if lines[i..i + span] == hunk.removals[..] {
                found = Some(i);
                break;
            }
            i += 1;
        }
        let at = found.ok_or_else(|| "hunk anchor not found; refusing partial patch".to_string())?;
        lines.splice(at..at + span, hunk.additions.clone());
        cursor = at + hunk.additions.len();
    }

    let mut out = lines.join("\n");
    if original.ends_with('\n') {
        out.push('\n');
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    const ORIG: &str = "alpha\nbeta\ngamma\n";

    #[test]
    fn replaces_exact_anchor() {
        let patch = "--- a/f\n+++ b/f\n@@ -1,3 +1,3 @@\n alpha\n-beta\n+delta\n gamma\n";
        assert_eq!(apply_unified_patch(ORIG, patch).unwrap(), "alpha\ndelta\ngamma\n");
    }

    #[test]
    fn rejects_escape_target() {
        let patch = "--- a/f\n+++ b/../../evil\n@@ -1 +1 @@\n-x\n+y\n";
        assert!(apply_unified_patch("x\n", patch).is_err());
    }

    #[test]
    fn rejects_anchor_miss_without_partial_write() {
        let patch = "--- a/f\n+++ b/f\n@@ -1 +1 @@\n-missing\n+hit\n";
        assert!(apply_unified_patch(ORIG, patch).is_err());
    }

    #[test]
    fn rejects_content_outside_hunks() {
        assert!(apply_unified_patch(ORIG, "stray line\n").is_err());
    }

    #[test]
    fn pure_insertion_hunk() {
        let patch = "--- a/f\n+++ b/f\n@@ -0,0 +1 @@\n+first\n";
        assert_eq!(apply_unified_patch("", patch).unwrap(), "first");
    }
}
