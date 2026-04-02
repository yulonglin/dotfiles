/// Expand `~/` prefix to the user's home directory.
pub fn expand_home(path: &str) -> String {
    if let Some(rest) = path.strip_prefix("~/") {
        if let Ok(home) = std::env::var("HOME") {
            return format!("{}/{}", home, rest);
        }
    }
    path.to_string()
}

/// Extract short plugin name from qualified ID (e.g., "foo@github.com/org" -> "foo").
pub fn plugin_short_name(qid: &str) -> &str {
    qid.split('@').next().unwrap_or(qid)
}

/// Write JSON value to a file atomically (temp file + rename).
pub fn atomic_write_json(path: &str, value: &serde_json::Value) -> Result<(), Box<dyn std::error::Error>> {
    let dir = std::path::Path::new(path).parent().unwrap_or(std::path::Path::new("."));
    std::fs::create_dir_all(dir)?;
    let tmp_path = format!("{}.tmp", path);
    let content = serde_json::to_string_pretty(value)?;
    std::fs::write(&tmp_path, format!("{}\n", content))?;
    std::fs::rename(&tmp_path, path)?;
    Ok(())
}

// ANSI terminal colors
pub const GREEN: &str = "\x1b[0;32m";
pub const YELLOW: &str = "\x1b[0;33m";
pub const RED: &str = "\x1b[0;31m";
pub const BLUE: &str = "\x1b[0;34m";
pub const BOLD: &str = "\x1b[1m";
pub const RESET: &str = "\x1b[0m";
