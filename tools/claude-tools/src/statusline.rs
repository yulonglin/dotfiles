use serde::Deserialize;
use std::fmt::Write;
use std::io::Read;

// --- Input JSON structures ---

#[derive(Deserialize)]
struct Input {
    workspace: Option<Workspace>,
    cost: Option<Cost>,
    context_window: Option<ContextWindow>,
}

#[derive(Deserialize)]
struct Workspace {
    current_dir: Option<String>,
}

#[derive(Deserialize)]
struct Cost {
    total_cost_usd: Option<f64>,
    total_duration_ms: Option<u64>,
}

#[derive(Deserialize)]
struct ContextWindow {
    used_percentage: Option<f64>,
}

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

    // 5. Context usage percentage
    format_context_usage(&mut output, input.context_window.as_ref());

    // 6. Session cost
    format_cost(&mut output, &input.cost);

    // 7. Session duration
    format_duration(&mut output, &input.cost);

    print!("{}", output);
    Ok(())
}

// --- Section formatters ---

/// Machine name shown only in SSH sessions.
/// Shells out to `machine-name` (custom_bins/) which handles SSH config alias
/// lookup, public IP caching, and emoji.
fn format_machine_name(output: &mut String) {
    if std::env::var("SSH_CONNECTION").is_err() {
        return;
    }

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

/// Context usage percentage from `context_window.used_percentage` (pre-computed by Claude Code).
fn format_context_usage(output: &mut String, context_window: Option<&ContextWindow>) {
    let pct = match context_window.and_then(|cw| cw.used_percentage) {
        Some(p) => p.round() as u64,
        None => return,
    };
    if pct == 0 {
        return;
    }
    let color = if pct >= 90 {
        "\x1b[31m" // Red
    } else if pct >= 70 {
        "\x1b[33m" // Yellow
    } else {
        "\x1b[32m" // Green
    };
    let _ = write!(output, " \u{00b7} \u{1f4ca} {}{}%\x1b[0m", color, pct);
}

/// Session duration from `cost.total_duration_ms`.
fn format_duration(output: &mut String, cost: &Option<Cost>) {
    let ms = match cost.as_ref().and_then(|c| c.total_duration_ms) {
        Some(ms) if ms > 0 => ms,
        _ => return,
    };
    let total_mins = ms / 60_000;
    if total_mins == 0 {
        return;
    }
    let display = if total_mins >= 60 {
        format!("{}h {}m", total_mins / 60, total_mins % 60)
    } else {
        format!("{}m", total_mins)
    };
    let _ = write!(output, " \u{00b7} \x1b[2m{}\x1b[0m", display);
}

/// Session cost in USD.
fn format_cost(output: &mut String, cost: &Option<Cost>) {
    let total_cost = match cost {
        Some(c) => c.total_cost_usd.unwrap_or(0.0),
        None => return,
    };

    if total_cost > 0.0 {
        let _ = write!(output, " \u{00b7} \x1b[35m${:.2}\x1b[0m", total_cost);
    }
}
