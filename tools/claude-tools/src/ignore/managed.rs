use std::fs;
use std::path::Path;
use super::patterns::{PatternState, normalize_for_dedup};

const BEGIN_MARKER: &str = "# --- claude-tools ignore begin ---";
const END_MARKER: &str = "# --- claude-tools ignore end ---";
const MANAGED_COMMENT: &str = "# Managed by `claude-tools ignore apply`. Do not edit manually.";

pub fn read_managed_patterns(path: &str) -> Vec<String> {
    let content = match fs::read_to_string(path) {
        Ok(c) => c,
        Err(_) => return Vec::new(),
    };
    extract_managed_patterns(&content)
}

fn extract_managed_patterns(content: &str) -> Vec<String> {
    let mut in_managed = false;
    let mut patterns = Vec::new();
    for line in content.lines() {
        let trimmed = line.trim();
        if trimmed == BEGIN_MARKER { in_managed = true; continue; }
        if trimmed == END_MARKER { break; }
        if in_managed && !trimmed.is_empty() && !trimmed.starts_with('#') {
            patterns.push(trimmed.to_string());
        }
    }
    patterns
}

pub fn count_non_managed_patterns(path: &str) -> usize {
    let content = match fs::read_to_string(path) {
        Ok(c) => c,
        Err(_) => return 0,
    };
    let mut in_managed = false;
    let mut count = 0;
    for line in content.lines() {
        let trimmed = line.trim();
        if trimmed == BEGIN_MARKER { in_managed = true; continue; }
        if trimmed == END_MARKER { in_managed = false; continue; }
        if !in_managed && !trimmed.is_empty() && !trimmed.starts_with('#') {
            count += 1;
        }
    }
    count
}

fn read_user_patterns(content: &str) -> Vec<String> {
    let mut in_managed = false;
    let mut patterns = Vec::new();
    for line in content.lines() {
        let trimmed = line.trim();
        if trimmed == BEGIN_MARKER { in_managed = true; continue; }
        if trimmed == END_MARKER { in_managed = false; continue; }
        if !in_managed && !trimmed.is_empty() && !trimmed.starts_with('#') {
            patterns.push(trimmed.to_string());
        }
    }
    patterns
}

pub fn apply(
    path: &str,
    selections: &[(String, PatternState)],
    is_ignore_file: bool,
) -> Result<Vec<String>, Box<dyn std::error::Error>> {
    let new_patterns: Vec<String> = if is_ignore_file {
        selections.iter()
            .filter(|(_, s)| matches!(s, PatternState::GitignoreSearchable))
            .map(|(g, _)| format!("!{}", g))
            .collect()
    } else {
        selections.iter()
            .filter(|(_, s)| matches!(s, PatternState::Gitignore | PatternState::GitignoreSearchable))
            .map(|(g, _)| g.clone())
            .collect()
    };

    if new_patterns.is_empty() {
        if Path::new(path).exists() {
            remove_managed_section(path)?;
        }
        return Ok(Vec::new());
    }

    let content = fs::read_to_string(path).unwrap_or_default();
    let user_patterns = read_user_patterns(&content);
    let user_normalized: Vec<String> = user_patterns.iter()
        .map(|p| normalize_for_dedup(p))
        .collect();

    let mut warnings = Vec::new();
    let deduped: Vec<String> = new_patterns.into_iter()
        .filter(|p| {
            let norm = normalize_for_dedup(p);
            if user_normalized.contains(&norm) {
                warnings.push(format!("'{}' already in user section, skipping", p));
                false
            } else {
                true
            }
        })
        .collect();

    let before_managed = strip_managed_section(&content);
    let mut output = before_managed.trim_end().to_string();

    if !deduped.is_empty() {
        if !output.is_empty() {
            output.push_str("\n\n");
        }
        output.push_str(BEGIN_MARKER);
        output.push('\n');
        output.push_str(MANAGED_COMMENT);
        output.push('\n');
        for p in &deduped {
            output.push_str(p);
            output.push('\n');
        }
        output.push_str(END_MARKER);
    }
    output.push('\n');

    fs::write(path, output)?;
    Ok(warnings)
}

fn strip_managed_section(content: &str) -> String {
    let mut result = String::new();
    let mut in_managed = false;
    for line in content.lines() {
        let trimmed = line.trim();
        if trimmed == BEGIN_MARKER { in_managed = true; continue; }
        if trimmed == END_MARKER { in_managed = false; continue; }
        if !in_managed {
            result.push_str(line);
            result.push('\n');
        }
    }
    result
}

fn remove_managed_section(path: &str) -> Result<(), Box<dyn std::error::Error>> {
    let content = fs::read_to_string(path)?;
    let cleaned = strip_managed_section(&content);
    let trimmed = cleaned.trim();
    fs::write(path, format!("{}\n", trimmed))?;
    Ok(())
}
