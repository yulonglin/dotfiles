//! Claude Code status line (Rust primary, for low-latency rendering).
//! Bash fallback: claude/statusline.sh (keep feature-parity when editing either).

use serde::Deserialize;
use std::fmt::Write;
use std::io::Read;

// --- Input JSON structures ---

#[derive(Deserialize)]
struct Input {
    workspace: Option<Workspace>,
    model: Option<Model>,
    cost: Option<Cost>,
    context_window: Option<ContextWindow>,
    effort: Option<Effort>,
}

#[derive(Deserialize)]
struct Model {
    display_name: Option<String>,
}

#[derive(Deserialize)]
struct Workspace {
    current_dir: Option<String>,
}

#[derive(Deserialize)]
struct Cost {
    total_duration_ms: Option<u64>,
}

#[derive(Deserialize)]
struct ContextWindow {
    used_percentage: Option<f64>,
    /// Everything currently in the window, cache reads and writes included.
    total_input_tokens: Option<u64>,
    /// The current model's limit — 200000, or 1000000 on a long-context model.
    context_window_size: Option<u64>,
}

/// Only present when the current model supports reasoning effort, so its
/// absence is normal rather than an error.
#[derive(Deserialize)]
struct Effort {
    level: Option<String>,
}

/// Written by claude/hooks/approval_classifier.py on every classification attempt.
#[derive(Deserialize)]
struct ClassifierHealth {
    backend: Option<String>,
    ts: Option<u64>,
}

/// Past this age the health file is treated as absent. The hook rewrites it on
/// every classification, so an active session refreshes it constantly; a
/// degraded marker left over from this morning is noise, not news.
const CLASSIFIER_HEALTH_MAX_AGE_SECS: u64 = 6 * 3600;

/// Past this age the recorded backend is reported as unknown rather than as
/// fact. write_health() runs ONLY on the classify() path — fast-path allows,
/// denies and question-to-user surfaces never touch it — so a session whose
/// tool calls all hit a fast path leaves the file frozen at whatever the last
/// backend attempt saw. On 2026-08-05 that pinned `dead` for over two hours on
/// the strength of one transient API read timeout, with the statusline
/// insisting the classifier was down long after the outage had passed.
/// A stale entry is not evidence of the current state, and rendering it as if
/// it were is the bug; `auto?` says what is actually known.
const CLASSIFIER_HEALTH_STALE_AFTER_SECS: u64 = 15 * 60;

// --- Main entry point ---

pub fn run() -> Result<(), Box<dyn std::error::Error>> {
    let mut input_str = String::new();
    std::io::stdin().read_to_string(&mut input_str)?;
    let input: Input = serde_json::from_str(&input_str)?;

    let cwd = input
        .workspace
        .as_ref()
        .and_then(|w| w.current_dir.as_deref())
        .unwrap_or(".");

    let mut output = String::with_capacity(256);

    // 1. Machine name (SSH sessions only)
    format_machine_name(&mut output);

    // 2. Context profiles from context.yaml
    format_context_profiles(&mut output, cwd);

    // 3. Directory path (dim cyan)
    format_directory(&mut output, cwd);

    // 4. Git branch + dirty status
    format_git_info(&mut output, cwd);

    // Line 2: session state (collect parts, join with " · ")
    let mut session_parts: Vec<String> = Vec::new();
    if let Some(s) = format_model_str(input.model.as_ref(), input.effort.as_ref()) {
        session_parts.push(s);
    }
    if let Some(s) = format_context_usage_str(input.context_window.as_ref()) {
        session_parts.push(s);
    }
    if let Some(s) = format_duration_str(&input.cost) {
        session_parts.push(s);
    }
    if let Some(s) = format_classifier_str() {
        session_parts.push(s);
    }
    if !session_parts.is_empty() {
        output.push('\n');
        output.push_str(&session_parts.join(" \u{00b7} "));
    }

    // Line 3: API usage (5h + 7d rate limits)
    crate::usage::format_usage(&mut output);

    print!("{}", output);
    Ok(())
}

// --- Section formatters ---

/// Machine name for registered machines + SSH fallback.
/// Shells out to `machine-name` (custom_bins/) which checks the machine registry
/// first, then falls back to SSH config alias lookup.
fn format_machine_name(output: &mut String) {
    let cmd_output = match std::process::Command::new("machine-name")
        .stderr(std::process::Stdio::null())
        .output()
    {
        Ok(o) if o.status.success() => o,
        _ => return,
    };

    let name = String::from_utf8_lossy(&cmd_output.stdout);
    let name = name.trim();
    if name.is_empty() {
        return;
    }

    // Format: "EMOJI NAME" -> "EMOJI \e[35mNAME\e[0m "
    let mut parts = name.splitn(2, ' ');
    if let (Some(icon), Some(host)) = (parts.next(), parts.next()) {
        let _ = write!(output, "{} \x1b[35m{}\x1b[0m ", icon, host);
    }
}

/// Extract context profiles from .claude/context.yaml and display as [profiles].
fn format_context_profiles(output: &mut String, cwd: &str) {
    let context_path = format!("{}/.claude/context.yaml", cwd);
    let content = match std::fs::read_to_string(&context_path) {
        Ok(c) => c,
        Err(_) => return,
    };

    let profiles = extract_profiles_from_yaml(&content);
    if !profiles.is_empty() {
        let _ = write!(output, "[\x1b[36m{}\x1b[0m] ", profiles);
    }
}

/// Parse the profiles list from context.yaml without a full YAML parser.
/// Handles both block style ("- code\n- python") and flow style ("[code, python]").
fn extract_profiles_from_yaml(content: &str) -> String {
    let mut in_profiles = false;
    let mut profiles = Vec::new();

    for line in content.lines() {
        let trimmed = line.trim();
        if trimmed.starts_with("profiles:") {
            // Flow style: profiles: [code, python]
            if let Some(bracket_start) = trimmed.find('[') {
                if let Some(bracket_end) = trimmed.find(']') {
                    return trimmed[bracket_start + 1..bracket_end]
                        .split(',')
                        .map(|s| s.trim())
                        .filter(|s| !s.is_empty())
                        .collect::<Vec<_>>()
                        .join(" ");
                }
            }
            in_profiles = true;
            continue;
        }

        if in_profiles {
            if let Some(value) = trimmed.strip_prefix("- ") {
                profiles.push(value.trim());
            } else if !trimmed.is_empty() {
                break;
            }
        }
    }

    profiles.join(" ")
}

/// Display working directory with HOME replaced by ~.
fn format_directory(output: &mut String, cwd: &str) {
    let home = std::env::var("HOME").unwrap_or_default();
    let dir = if cwd == home {
        "~".to_string()
    } else if !home.is_empty() && cwd.starts_with(&home) {
        format!("~{}", &cwd[home.len()..])
    } else {
        cwd.to_string()
    };

    // Dim cyan for directory
    let _ = write!(output, "\x1b[2m\x1b[36m{}\x1b[0m", dir);
}

/// Git branch name with clean/dirty indicator using libgit2.
fn format_git_info(output: &mut String, cwd: &str) {
    let repo = match git2::Repository::discover(cwd) {
        Ok(r) => r,
        Err(_) => return,
    };

    // Get branch name or short commit hash for detached HEAD
    let branch = match repo.head() {
        Ok(head) => {
            if head.is_branch() {
                head.shorthand().map(|s| s.to_string())
            } else {
                // Detached HEAD — show short hash
                head.target().map(|oid| {
                    let hex = oid.to_string();
                    hex[..7.min(hex.len())].to_string()
                })
            }
        }
        Err(_) => return,
    };

    let branch = match branch {
        Some(b) => b,
        None => return,
    };

    // Check for uncommitted changes (staged or unstaged, excluding untracked)
    let mut opts = git2::StatusOptions::new();
    opts.include_untracked(false).include_ignored(false);

    let has_changes = repo
        .statuses(Some(&mut opts))
        .map(|statuses| !statuses.is_empty())
        .unwrap_or(false);

    if has_changes {
        // Yellow for dirty repo
        let _ = write!(output, " \x1b[33m({}*)\x1b[0m", branch);
    } else {
        // Green for clean repo
        let _ = write!(output, " \x1b[32m({})\x1b[0m", branch);
    }
}

/// Model display name in brackets, with the reasoning effort folded in when the
/// model reports one: "[Opus 5 (high)]". Effort keeps its own colour inside the
/// blue bracket, so the bracket colour is re-opened after the suffix.
/// Effort has no segment of its own — a payload with an effort but no model
/// display name renders neither, which Claude Code never sends.
fn format_model_str(model: Option<&Model>, effort: Option<&Effort>) -> Option<String> {
    let name = model.and_then(|m| m.display_name.as_deref()).filter(|n| !n.is_empty())?;
    match format_effort_suffix(effort) {
        Some(suffix) => Some(format!("\x1b[34m[{} {}\x1b[34m]\x1b[0m", name, suffix)),
        None => Some(format!("\x1b[34m[{}]\x1b[0m", name)),
    }
}

/// Compact token count: "845" under a thousand, "123k", "1.0M".
/// The `k` branch stops below 999_500 so a value that would round to "1000k"
/// renders as "1.0M" instead.
/// Parity: claude/statusline.sh::format_tokens
pub fn format_tokens(n: u64) -> String {
    if n < 1_000 {
        n.to_string()
    } else if n < 999_500 {
        format!("{}k", ((n as f64) / 1_000.0).round() as u64)
    } else {
        format!("{:.1}M", (n as f64) / 1_000_000.0)
    }
}

/// Context usage from `context_window` (pre-computed by Claude Code): absolute
/// tokens against the model's window, plus the percentage that drives the colour.
/// Renders "ctx:123k/200k (62%)", degrading to "ctx:123k (62%)" without a window
/// size and to "ctx:62%" without a token count — the percentage only takes
/// parentheses when it is qualifying a token count in front of it.
fn format_context_usage_str(context_window: Option<&ContextWindow>) -> Option<String> {
    let cw = context_window?;
    let pct = cw.used_percentage?.round() as u64;
    if pct == 0 {
        return None;
    }
    let color = if pct >= 90 {
        "\x1b[31m" // Red
    } else if pct >= 70 {
        "\x1b[33m" // Yellow
    } else {
        "\x1b[32m" // Green
    };

    let body = match cw.total_input_tokens.filter(|t| *t > 0) {
        Some(tokens) => match cw.context_window_size.filter(|s| *s > 0) {
            Some(size) => format!("{}/{} ({}%)", format_tokens(tokens), format_tokens(size), pct),
            None => format!("{} ({}%)", format_tokens(tokens), pct),
        },
        None => format!("{}%", pct),
    };
    Some(format!("{}ctx:{}\x1b[0m", color, body))
}

/// Live reasoning effort from `effort.level`, as the parenthesised suffix that
/// goes inside the model bracket. Dim for the everyday levels; yellow for
/// xhigh/max, which cost enough to be worth noticing. Deliberately leaves the
/// colour open — format_model_str re-opens blue for the closing bracket.
/// Parity: claude/statusline.sh (REASONING EFFORT section)
fn format_effort_suffix(effort: Option<&Effort>) -> Option<String> {
    let level = effort
        .and_then(|e| e.level.as_deref())
        .map(str::trim)
        .filter(|l| !l.is_empty())?;
    let color = match level {
        "xhigh" | "max" => "\x1b[33m", // Yellow
        _ => "\x1b[2m",                // Dim
    };
    Some(format!("{}({})", color, level))
}

/// The dotfiles checkout root, for reading config/secrets-global.conf.
/// `~/.claude` is a symlink into the checkout, so it doubles as a locator when
/// DOT_DIR is not exported (Claude Code spawns the statusline, not a shell).
fn dotfiles_root() -> Option<std::path::PathBuf> {
    if let Ok(dir) = std::env::var("DOT_DIR") {
        if !dir.is_empty() {
            return Some(std::path::PathBuf::from(dir));
        }
    }
    let home = std::env::var("HOME").ok()?;
    let target = std::fs::read_link(std::path::PathBuf::from(home).join(".claude")).ok()?;
    target.parent().map(|p| p.to_path_buf())
}

/// Short label of the ANTHROPIC_API_KEY that config/secrets-global.conf makes
/// active — "ANTHROPIC_API_KEY - mats" renders as "mats". Mirrors the resolver
/// in custom_bins/dotfiles-secrets: first line for the name whose value is not
/// prefixed with `!` (blocked) wins.
fn active_anthropic_key_label() -> Option<String> {
    let conf = dotfiles_root()?.join("config/secrets-global.conf");
    let content = std::fs::read_to_string(conf).ok()?;
    for line in content.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let Some((name, value)) = line.split_once('=') else {
            continue;
        };
        // " [global]" marks the name resolvable outside a repo; it is part of
        // the NAME field, so it must come off before matching.
        let name = name.trim();
        let name = name.strip_suffix("[global]").map_or(name, str::trim_end);
        if name != "ANTHROPIC_API_KEY" {
            continue;
        }
        let value = value.trim();
        if value.is_empty() {
            continue; // marker-only line ("NAME [global] =") declares no key
        }
        if value.starts_with('!') {
            continue; // blocked key — keep looking down the preference list
        }
        return Some(match value.split_once(" - ") {
            Some((_, desc)) => desc.trim().to_string(),
            None => String::new(),
        });
    }
    None
}

/// Which backend last served an auto-approval, and on which key.
/// Healthy renders dim and minimal; anything else is meant to be noticed.
fn format_classifier_str() -> Option<String> {
    let home = std::env::var("HOME").ok()?;
    let path = std::path::PathBuf::from(home)
        .join(".cache/claude/approval-classifier-health.json");
    let health: ClassifierHealth = serde_json::from_str(&std::fs::read_to_string(path).ok()?).ok()?;
    let backend = health.backend.as_deref()?;
    // Validate the backend BEFORE the age tiers, so a corrupt or future-versioned
    // file renders nothing at either age rather than an authoritative-looking
    // "stale" marker for a value we cannot interpret.
    if !matches!(backend, "api" | "subscription" | "dead") {
        return None;
    }

    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .ok()?
        .as_secs();
    let age = now.saturating_sub(health.ts.unwrap_or(0));
    if age > CLASSIFIER_HEALTH_MAX_AGE_SECS {
        return None;
    }
    // Applies to every backend, healthy included: past the window we don't know
    // that the API path still works either, and claiming otherwise is the same
    // error as the sticky `dead` in the opposite direction.
    if age > CLASSIFIER_HEALTH_STALE_AFTER_SECS {
        return Some("\x1b[2mauto?\x1b[0m".to_string());
    }

    let label = active_anthropic_key_label().unwrap_or_default();
    // The suffix after `auto-` names the BACKEND, not the key: `-ant` is the
    // Anthropic API key path, `-sub` the subscription fallback. Keeping the two
    // in the same position means a key that happened to be labelled "sub" can no
    // longer read as the degraded state.
    match backend {
        "api" if label.is_empty() => Some("\x1b[2mauto-ant\x1b[0m".to_string()),
        "api" => Some(format!("\x1b[2mauto-ant:{}\x1b[0m", label)),
        // Deliberately does NOT name a key. `label` is the conf's preferred key,
        // but with-anthropic-key.sh defers to an already-exported ANTHROPIC_API_KEY,
        // so the key that actually failed may be a different one — naming the wrong
        // key as down is worse than naming none. The healthy line still shows it.
        "subscription" => Some("\x1b[33mauto-sub\x1b[0m \x1b[2m(api down)\x1b[0m".to_string()),
        "dead" => Some("\x1b[31m🔴auto\x1b[0m".to_string()),
        _ => None,
    }
}

/// Session duration from `cost.total_duration_ms`.
fn format_duration_str(cost: &Option<Cost>) -> Option<String> {
    let ms = match cost.as_ref().and_then(|c| c.total_duration_ms) {
        Some(ms) if ms > 0 => ms,
        _ => return None,
    };
    let total_mins = ms / 60_000;
    if total_mins == 0 {
        return None;
    }
    let display = if total_mins >= 60 {
        format!("{}h {}m", total_mins / 60, total_mins % 60)
    } else {
        format!("{}m", total_mins)
    };
    Some(format!("\x1b[2m{}\x1b[0m", display))
}

