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

    // Line 2: session state (collect parts, join with " · ")
    let mut session_parts: Vec<String> = Vec::new();
    if let Some(s) = format_model_str(input.model.as_ref()) {
        session_parts.push(s);
    }
    if let Some(s) = format_context_usage_str(input.context_window.as_ref()) {
        session_parts.push(s);
    }
    if let Some(s) = format_duration_str(&input.cost) {
        session_parts.push(s);
    }
    session_parts.push(format_peak_str());
    if !session_parts.is_empty() {
        output.push('\n');
        output.push_str(&session_parts.join(" \u{00b7} "));
    }

    // Line 3: API usage (5h + 7d rate limits)
    crate::usage::format_usage(&mut output);

    // Line 4: Workday remaining (macOS only)
    format_workday(&mut output);

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

/// Model display name in brackets.
fn format_model_str(model: Option<&Model>) -> Option<String> {
    let name = model.and_then(|m| m.display_name.as_deref()).filter(|n| !n.is_empty())?;
    Some(format!("\x1b[34m[{}]\x1b[0m", name))
}

/// Context usage percentage from `context_window.used_percentage` (pre-computed by Claude Code).
fn format_context_usage_str(context_window: Option<&ContextWindow>) -> Option<String> {
    let pct = context_window.and_then(|cw| cw.used_percentage)?.round() as u64;
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
    Some(format!("{}ctx:{}%\x1b[0m", color, pct))
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

/// Format minutes as compact countdown: "2d5h" / "3h20m" / "45m".
fn fmt_countdown(mins: u32) -> String {
    let h = mins / 60;
    let m = mins % 60;
    if h >= 24 {
        format!("{}d{}h", h / 24, h % 24)
    } else if h > 0 {
        format!("{}h{}m", h, m)
    } else {
        format!("{}m", m)
    }
}

/// Minutes remaining in the current day from hour:minute until midnight.
fn mins_until_midnight(hour: u32, minute: u32) -> u32 {
    (23 - hour) * 60 + (60 - minute)
}

/// Peak hours indicator with countdown (weekdays 5am-11am PT = peak 1x, off-peak = 2x bonus).
/// See also: claude/statusline.sh (bash fallback).
fn format_peak_str() -> String {
    let output = match std::process::Command::new("date")
        .env("TZ", "America/Los_Angeles")
        .args(["+%u %-H %-M"])
        .output()
    {
        Ok(o) if o.status.success() => o,
        _ => return "\x1b[32m2x\x1b[0m".to_string(),
    };

    let s = String::from_utf8_lossy(&output.stdout);
    let parts: Vec<&str> = s.trim().split(' ').collect();
    if parts.len() != 3 {
        return "\x1b[32m2x\x1b[0m".to_string();
    }

    let dow: u32 = parts[0].parse().unwrap_or(0);
    let hour: u32 = parts[1].parse().unwrap_or(0);
    let minute: u32 = parts[2].parse().unwrap_or(0);
    let is_weekday = dow >= 1 && dow <= 5;

    if is_weekday && hour >= 5 && hour < 11 {
        // In peak — countdown to 11am PT
        let left = (10 - hour) * 60 + (60 - minute);
        format!("\x1b[33m1x peak \x1b[2m{}\x1b[0m", fmt_countdown(left))
    } else {
        // Off-peak — countdown to next peak (next weekday 5am PT)
        let rest_of_day = mins_until_midnight(hour, minute);
        let to_peak = if !is_weekday {
            let days_to_mon = if dow == 6 { 2 } else { 1 };
            (days_to_mon - 1) * 1440 + rest_of_day + 5 * 60
        } else if hour < 5 {
            (4 - hour) * 60 + (60 - minute)
        } else {
            // After peak; next is tomorrow 5am (or Monday if Friday)
            let skip_days = if dow == 5 { 2 } else { 0 };
            rest_of_day + skip_days * 1440 + 5 * 60
        };
        format!("\x1b[32m2x \x1b[2m{}\x1b[0m", fmt_countdown(to_peak))
    }
}

/// Workday remaining (ends at midnight, bedtime nudges).
/// Respects the home timezone configured via `claude-tools timezone`.
/// Falls back to server local time if no timezone is set.
/// See also: claude/statusline.sh (bash fallback).
fn format_workday(output: &mut String) {
    let home_tz = crate::timezone::read_home_timezone();

    let mut cmd = std::process::Command::new("date");
    if let Some(ref tz) = home_tz {
        cmd.env("TZ", tz);
    }
    // %H %M: 24h, zero-padded — parses cleanly on macOS and Linux
    let date_output = match cmd.args(["+%H %M"]).output() {
        Ok(o) if o.status.success() => o,
        _ => return,
    };

    let s = String::from_utf8_lossy(&date_output.stdout);
    let parts: Vec<&str> = s.trim().split(' ').collect();
    if parts.len() != 2 {
        return;
    }

    let hour: i32 = parts[0].parse().unwrap_or(0);
    let minute: i32 = parts[1].parse().unwrap_or(0);

    if hour < 6 {
        // Past midnight — should be in bed
        let over = if hour == 0 && minute == 0 {
            "midnight".to_string()
        } else if hour == 0 {
            format!("{}m", minute)
        } else {
            format!("{}h {}m", hour, minute)
        };
        let _ = write!(
            output,
            "\n\x1b[31;1m\u{1f6cf}\u{fe0f}  {} past bedtime — stop and go to sleep!\x1b[0m",
            over
        );
    } else {
        let left = (23 - hour) * 60 + (60 - minute);
        let (icon, color, msg) = if left <= 30 {
            ("\u{1f6cf}\u{fe0f} ", "\x1b[31;1m", format!("{}m — wrap up and get to bed!", left % 60))
        } else if left <= 60 {
            ("\u{1f319}", "\x1b[31m", format!(" {}m left — start wrapping up", left))
        } else if left <= 120 {
            ("\u{1f319}", "\x1b[33m", format!(" {}h {}m left", left / 60, left % 60))
        } else {
            ("\u{1f319}", "\x1b[2m", format!(" {}h {}m left", left / 60, left % 60))
        };
        let _ = write!(output, "\n{}{}{}\x1b[0m", color, icon, msg);
    }
}

