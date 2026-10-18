//! Claude Code status line — the only implementation. The claude/statusline.sh
//! fallback was retired on 2026-08-30, so an edit here changes what renders with
//! nothing to cross-check it: the guard is tests/test_statusline_classifier.sh
//! and tests/test_statusline_usage_gauge.sh, which pin the output to literal
//! expected strings. Rebuild every platform asset you can and check
//! scripts/check-claude-tools-fresh.sh — the committed binary is what runs.
//!
//! Layout: line 1 is location (machine, profiles, directory, branch); then the
//! session segments; then every coding agent's usage (Claude, the other Claude
//! account, Codex). The session and usage rows are packed to the terminal width
//! by pack_groups, so they stay one line each on a wide screen and wrap at
//! segment boundaries on a phone. The only square brackets are the model's.

use serde::Deserialize;
use unicode_width::UnicodeWidthStr;
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
    prompt_cache: Option<PromptCache>,
    transcript_path: Option<String>,
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
    /// Client-side estimate at list price, not the bill; resets on /clear.
    total_cost_usd: Option<f64>,
}

/// Main-conversation prompt cache, computed by Claude Code from the API's cache
/// token counts (v2.1.251+, absent until the first response). Claude Code
/// re-runs the statusline when a warm cache reaches `expires_at`, so the cold
/// flip lands on time; between events the countdown is as of the last run.
/// `ttl` is the cached prefix's lifetime, "1h" or "5m" — the 5m case is what
/// usage overage drops to, so it is the one worth seeing.
#[derive(Deserialize)]
struct PromptCache {
    warm: Option<bool>,
    caching_observed: Option<bool>,
    ttl: Option<String>,
    expires_at: Option<i64>,
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

    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |d| d.as_secs() as i64);
    let width = available_width(std::env::var("COLUMNS").ok().as_deref());
    let transcript = input.transcript_path.as_deref().map(std::path::Path::new);
    let started = transcript.and_then(transcript_started_at);
    let last_active = transcript.and_then(transcript_last_active_at);

    // Session state: one group, so it splits only between segments.
    let session_parts: Vec<String> = [
        format_model_str(input.model.as_ref(), input.effort.as_ref()),
        format_context_usage_str(input.context_window.as_ref()),
        format_duration_str(&input.cost),
        format_since_str("age", started, now),
        format_since_str("idle", last_active, now),
        format_cost_str(input.cost.as_ref()),
        format_prompt_cache_str(input.prompt_cache.as_ref(), now),
        format_classifier_str(),
    ]
    .into_iter()
    .flatten()
    .collect();
    if !session_parts.is_empty() {
        for line in pack_groups(&[session_parts], width) {
            output.push('\n');
            output.push_str(&line);
        }
    }

    // Every coding agent's usage on one row: Claude (plus the other account),
    // then Codex, whose window durations come from its own API.
    let mut usage_groups = crate::usage::usage_groups();
    usage_groups.extend(crate::codex_usage::usage_group());
    for line in pack_groups(&usage_groups, width) {
        output.push('\n');
        output.push_str(&line);
    }

    print!("{}", output);
    Ok(())
}

// --- Width-aware layout ---

/// Joins segments inside a group.
const SEGMENT_SEP: &str = " \u{00b7} ";
/// Joins groups (Claude, the other account, Codex) on a shared line. Each
/// group after the first carries its own label ("⇄", "Codex"), so plain space
/// is enough to separate them.
const GROUP_SEP: &str = "  ";
/// Columns Claude Code takes from COLUMNS before the script's text: the
/// `statusLine.padding` of 1 in claude/settings.json plus its own built-in
/// indent, which the docs do not size. Over-reserving only wraps a little early;
/// under-reserving lets Claude Code cut the line's tail.
const WIDTH_MARGIN: usize = 4;

/// Usable columns from Claude Code's `COLUMNS`. Claude Code captures the
/// script's stdout, so `tput cols` and a tty query see no terminal; the docs
/// say it sets `COLUMNS`/`LINES` to the terminal size before every run
/// (code.claude.com/docs/en/statusline, "Sizing output to the terminal").
/// None — no wrapping — when it is unset or unparsable.
fn available_width(columns: Option<&str>) -> Option<usize> {
    let cols: usize = columns?.trim().parse().ok().filter(|c| *c > 0)?;
    Some(cols.saturating_sub(WIDTH_MARGIN).max(1))
}

/// Terminal columns a string occupies, ignoring ANSI CSI sequences.
fn visible_width(s: &str) -> usize {
    let mut plain = String::with_capacity(s.len());
    let mut chars = s.chars();
    while let Some(c) = chars.next() {
        if c == '\x1b' {
            if chars.next() == Some('[') {
                // Parameters and intermediates run until a final byte in @..~.
                for c in chars.by_ref() {
                    if ('@'..='~').contains(&c) {
                        break;
                    }
                }
            }
            continue;
        }
        plain.push(c);
    }
    UnicodeWidthStr::width(plain.as_str())
}

/// Lay groups of segments out in as few lines as fit `width`. A group moves
/// whole to the next line rather than being split, so a continuation never
/// starts with an orphaned "7d ready" whose label stayed behind; only a group
/// wider than a full line is broken, and then only between segments. A single
/// segment wider than the line is left for the terminal to cut. `None` width
/// puts everything on one line.
fn pack_groups(groups: &[Vec<String>], width: Option<usize>) -> Vec<String> {
    let limit = width.unwrap_or(usize::MAX);
    let mut lines = Vec::new();
    let mut line = String::new();
    let mut used = 0usize;

    for group in groups.iter().filter(|g| !g.is_empty()) {
        let joined = group.join(SEGMENT_SEP);
        let joined_width = visible_width(&joined);
        let sep_width = if line.is_empty() { 0 } else { visible_width(GROUP_SEP) };
        if used + sep_width + joined_width <= limit {
            if !line.is_empty() {
                line.push_str(GROUP_SEP);
            }
            line.push_str(&joined);
            used += sep_width + joined_width;
            continue;
        }
        if !line.is_empty() {
            lines.push(std::mem::take(&mut line));
            used = 0;
        }
        for segment in group {
            let segment_width = visible_width(segment);
            if !line.is_empty() && used + visible_width(SEGMENT_SEP) + segment_width > limit {
                lines.push(std::mem::take(&mut line));
                used = 0;
            }
            if !line.is_empty() {
                line.push_str(SEGMENT_SEP);
                used += visible_width(SEGMENT_SEP);
            }
            line.push_str(segment);
            used += segment_width;
        }
    }
    if !line.is_empty() {
        lines.push(line);
    }
    lines
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

/// Extract context profiles from .claude/context.yaml and display them in cyan,
/// unbracketed — square brackets are reserved for the model name.
fn format_context_profiles(output: &mut String, cwd: &str) {
    let context_path = format!("{}/.claude/context.yaml", cwd);
    let content = match std::fs::read_to_string(&context_path) {
        Ok(c) => c,
        Err(_) => return,
    };

    let profiles = extract_profiles_from_yaml(&content);
    if !profiles.is_empty() {
        let _ = write!(output, "\x1b[36m{}\x1b[0m ", profiles);
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
/// blue bracket, so the bracket colour is re-opened after the suffix — at normal
/// intensity (SGR 22), since a bare SGR 34 would leave the dim levels' SGR 2 set
/// and render the closing bracket dimmer than the opening one.
/// Effort has no segment of its own — a payload with an effort but no model
/// display name renders neither, which Claude Code never sends.
fn format_model_str(model: Option<&Model>, effort: Option<&Effort>) -> Option<String> {
    let name = model.and_then(|m| m.display_name.as_deref()).filter(|n| !n.is_empty())?;
    match format_effort_suffix(effort) {
        Some(suffix) => Some(format!("\x1b[34m[{} {}\x1b[22;34m]\x1b[0m", name, suffix)),
        None => Some(format!("\x1b[34m[{}]\x1b[0m", name)),
    }
}

/// Compact token count: "845" under a thousand, "123k", "1.0M".
/// The `k` branch stops below 999_500 so a value that would round to "1000k"
/// renders as "1.0M" instead.
/// Both boundaries are pinned in tests/test_statusline_classifier.sh.
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
/// colour and intensity open — format_model_str restores both for the closing bracket.
/// tests/test_statusline_classifier.sh pins the resulting bytes for both the
/// dim and the yellow case, so a palette change fails there rather than silently.
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

/// The fields of a transcript line that date it. Every line is one JSON object;
/// the metadata lines at the head (title, mode, file-history snapshot) carry no
/// timestamp and are rewritten in place, so the file's mtime says nothing about
/// when the conversation was last used.
#[derive(Deserialize)]
struct TranscriptEntry {
    #[serde(rename = "type")]
    kind: Option<String>,
    timestamp: Option<String>,
    #[serde(rename = "isMeta")]
    is_meta: Option<bool>,
}

/// Lines read from the head before giving up on finding a timestamp.
const TRANSCRIPT_HEAD_LINES: usize = 200;
/// First tail read; quadrupled on a miss up to the cap. Tool results make single
/// lines run to hundreds of KB, so the last user/assistant line can sit well
/// back from the end.
const TRANSCRIPT_TAIL_CHUNK: u64 = 256 * 1024;
const TRANSCRIPT_TAIL_MAX: u64 = 16 * 1024 * 1024;

/// When the conversation started: the first timestamped line. Resumes append to
/// the same file and compaction writes into it, so this spans both; `/clear`
/// starts a new transcript and so a new age.
fn transcript_started_at(path: &std::path::Path) -> Option<i64> {
    use std::io::BufRead;
    let file = std::fs::File::open(path).ok()?;
    std::io::BufReader::new(file)
        .lines()
        .take(TRANSCRIPT_HEAD_LINES)
        .map_while(Result::ok)
        .filter_map(|line| serde_json::from_str::<TranscriptEntry>(&line).ok())
        .find_map(|e| e.timestamp.as_deref().and_then(parse_utc_timestamp))
}

/// When the conversation was last used: the newest user or assistant line.
/// Attachments, system lines and meta user lines are skipped because a resume
/// writes them before anyone types, which would zero the idle time at exactly
/// the moment it is worth reading.
fn transcript_last_active_at(path: &std::path::Path) -> Option<i64> {
    use std::io::{Seek, SeekFrom};
    let mut file = std::fs::File::open(path).ok()?;
    let len = file.metadata().ok()?.len();
    let mut chunk = TRANSCRIPT_TAIL_CHUNK;
    loop {
        let start = len.saturating_sub(chunk);
        file.seek(SeekFrom::Start(start)).ok()?;
        let mut buf = Vec::new();
        file.read_to_end(&mut buf).ok()?;
        let text = String::from_utf8_lossy(&buf);
        // Mid-file, the first line is a fragment.
        let whole = if start == 0 { &text[..] } else { text.split_once('\n').map_or("", |(_, rest)| rest) };
        let found = whole
            .lines()
            .rev()
            .filter_map(|line| serde_json::from_str::<TranscriptEntry>(line).ok())
            .filter(|e| matches!(e.kind.as_deref(), Some("user" | "assistant")) && e.is_meta != Some(true))
            .find_map(|e| e.timestamp.as_deref().and_then(parse_utc_timestamp));
        if found.is_some() || start == 0 || chunk >= TRANSCRIPT_TAIL_MAX {
            return found;
        }
        chunk *= 4;
    }
}

/// "2026-10-14T04:59:26.105Z" → Unix seconds, in-process: the statusline runs
/// on a timer in every session, so spawning `date` like usage.rs does is too
/// dear. Only the UTC `Z` form Claude Code writes is accepted.
fn parse_utc_timestamp(s: &str) -> Option<i64> {
    let (date, time) = s.strip_suffix('Z')?.split_once('T')?;
    let mut d = date.splitn(3, '-').map(|p| p.parse::<i64>().ok());
    let (y, m, day) = (d.next()??, d.next()??, d.next()??);
    let mut t = time.split('.').next()?.splitn(3, ':').map(|p| p.parse::<i64>().ok());
    let (h, min, sec) = (t.next()??, t.next()??, t.next()??);
    // Days since 1970-01-01 (Howard Hinnant's days_from_civil).
    let y = if m <= 2 { y - 1 } else { y };
    let era = y.div_euclid(400);
    let yoe = y - era * 400;
    let doy = (153 * ((m + 9) % 12) + 2) / 5 + day - 1;
    let days = era * 146_097 + yoe * 365 + yoe / 4 - yoe / 100 + doy - 719_468;
    Some(days * 86_400 + h * 3_600 + min * 60 + sec)
}

/// "age 2d3h" (since the conversation started) or "idle 12m" (since it was last
/// used). Omitted under a minute, so an active session shows no "idle 0m".
/// Between events the value is as of the last run, which is why the statusLine
/// in claude/settings.json sets a refreshInterval.
fn format_since_str(label: &str, at: Option<i64>, now: i64) -> Option<String> {
    let secs = now - at?;
    if secs < 60 {
        return None;
    }
    Some(format!("\x1b[2m{} {}\x1b[0m", label, crate::usage::fmt_time_remaining(secs as f64)))
}

/// Session price so far from `cost.total_cost_usd`: "$7.42". Omitted until the
/// first billable response, like the duration.
fn format_cost_str(cost: Option<&Cost>) -> Option<String> {
    let usd = cost?.total_cost_usd.filter(|c| c.is_finite() && *c > 0.0)?;
    Some(format!("\x1b[2m${:.2}\x1b[0m", usd))
}

/// Prompt cache state: "cache 42m" while warm (time left before it goes cold),
/// "cache cold" once expired. A 5-minute TTL renders yellow with "(5m ttl)",
/// because it means the session has fallen back from the 1h TTL (usage overage)
/// and the cache now lapses between ordinary pauses. Omitted when Claude Code has
/// not seen caching at all, so a provider without it shows nothing rather than a
/// permanent "cold". `now` is a parameter so tests are deterministic.
fn format_prompt_cache_str(cache: Option<&PromptCache>, now: i64) -> Option<String> {
    let cache = cache?;
    if cache.caching_observed == Some(false) {
        return None;
    }
    let remaining = cache
        .expires_at
        .filter(|_| cache.warm == Some(true))
        .map(|at| at - now)
        .filter(|secs| *secs > 0);
    let Some(secs) = remaining else {
        return Some("\x1b[33mcache cold\x1b[0m".to_string());
    };
    let left = if secs < 60 {
        "<1m".to_string()
    } else {
        crate::usage::fmt_time_remaining(secs as f64)
    };
    Some(match cache.ttl.as_deref() {
        Some("5m") => format!("\x1b[33mcache {} (5m ttl)\x1b[0m", left),
        _ => format!("\x1b[32mcache {}\x1b[0m", left),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn cache(warm: bool, ttl: &str, expires_at: Option<i64>) -> PromptCache {
        PromptCache {
            warm: Some(warm),
            caching_observed: Some(true),
            ttl: Some(ttl.to_string()),
            expires_at,
        }
    }

    #[test]
    fn prompt_cache_warm_shows_time_left() {
        let now = 1_000_000;
        let c = cache(true, "1h", Some(now + 42 * 60 + 10));
        assert_eq!(
            format_prompt_cache_str(Some(&c), now).unwrap(),
            "\x1b[32mcache 42m\x1b[0m"
        );
        let c = cache(true, "1h", Some(now + 30));
        assert_eq!(
            format_prompt_cache_str(Some(&c), now).unwrap(),
            "\x1b[32mcache <1m\x1b[0m"
        );
    }

    #[test]
    fn prompt_cache_five_minute_ttl_is_flagged() {
        let now = 1_000_000;
        let c = cache(true, "5m", Some(now + 190));
        assert_eq!(
            format_prompt_cache_str(Some(&c), now).unwrap(),
            "\x1b[33mcache 3m (5m ttl)\x1b[0m"
        );
    }

    #[test]
    fn prompt_cache_cold_when_not_warm_or_expired() {
        let now = 1_000_000;
        let cold = "\x1b[33mcache cold\x1b[0m";
        // Not warm, even with a future expiry on record.
        let c = cache(false, "1h", Some(now + 600));
        assert_eq!(format_prompt_cache_str(Some(&c), now).unwrap(), cold);
        // Warm flag from the last run, but expires_at has passed since.
        let c = cache(true, "1h", Some(now - 1));
        assert_eq!(format_prompt_cache_str(Some(&c), now).unwrap(), cold);
        // Last response reported no cache tokens: expires_at is null.
        let c = cache(true, "1h", None);
        assert_eq!(format_prompt_cache_str(Some(&c), now).unwrap(), cold);
    }

    #[test]
    fn prompt_cache_hidden_without_caching() {
        assert_eq!(format_prompt_cache_str(None, 0), None);
        let mut c = cache(false, "1h", None);
        c.caching_observed = Some(false);
        assert_eq!(format_prompt_cache_str(Some(&c), 0), None);
    }

    #[test]
    fn prompt_cache_parses_documented_payload() {
        let input: Input = serde_json::from_str(
            r#"{"prompt_cache":{"warm":true,"caching_observed":true,"ttl":"1h",
                "expires_at":1738429200,"requests":14,"hit_ratio":0.91}}"#,
        )
        .unwrap();
        let c = input.prompt_cache.unwrap();
        assert_eq!(c.expires_at, Some(1_738_429_200));
        assert_eq!(c.ttl.as_deref(), Some("1h"));
    }

    #[test]
    fn cost_renders_two_decimals_and_hides_zero() {
        let cost = |usd: Option<f64>| Cost { total_duration_ms: None, total_cost_usd: usd };
        assert_eq!(format_cost_str(Some(&cost(Some(7.4213)))).unwrap(), "\x1b[2m$7.42\x1b[0m");
        assert_eq!(format_cost_str(Some(&cost(Some(0.0)))), None);
        assert_eq!(format_cost_str(Some(&cost(None))), None);
        assert_eq!(format_cost_str(None), None);
    }

    #[test]
    fn available_width_reads_columns() {
        assert_eq!(available_width(Some("120")), Some(120 - WIDTH_MARGIN));
        assert_eq!(available_width(Some(" 50\n")), Some(50 - WIDTH_MARGIN));
        assert_eq!(available_width(Some("2")), Some(1));
        assert_eq!(available_width(Some("0")), None);
        assert_eq!(available_width(Some("wide")), None);
        assert_eq!(available_width(None), None);
    }

    #[test]
    fn visible_width_ignores_ansi_and_counts_wide_glyphs() {
        assert_eq!(visible_width("\x1b[2m\x1b[36mabc\x1b[0m"), 3);
        assert_eq!(visible_width("\x1b[38;2;255;176;85m5h \u{25D4} 24%\x1b[0m"), 8);
        assert_eq!(visible_width("\x1b[31m🔴auto\x1b[0m"), 6);
    }

    fn groups(spec: &[&[&str]]) -> Vec<Vec<String>> {
        spec.iter().map(|g| g.iter().map(|s| s.to_string()).collect()).collect()
    }

    #[test]
    fn pack_keeps_everything_on_one_line_when_it_fits() {
        let g = groups(&[&["5h 4%", "7d 9%"], &["⇄ 5h 2h"], &["Codex 7d 1%"]]);
        assert_eq!(pack_groups(&g, None), vec!["5h 4% · 7d 9%  ⇄ 5h 2h  Codex 7d 1%"]);
        assert_eq!(pack_groups(&g, Some(35)), vec!["5h 4% · 7d 9%  ⇄ 5h 2h  Codex 7d 1%"]);
    }

    #[test]
    fn pack_moves_whole_groups_before_splitting_one() {
        let g = groups(&[&["5h 4%", "7d 9%"], &["⇄ 5h 2h", "7d ready"], &["Codex 7d 1%"]]);
        // "⇄ 5h 2h · 7d ready" would fit after the Claude group only in part:
        // it moves down whole instead of leaving "7d ready" orphaned.
        assert_eq!(
            pack_groups(&g, Some(24)),
            vec!["5h 4% · 7d 9%", "⇄ 5h 2h · 7d ready", "Codex 7d 1%"]
        );
    }

    #[test]
    fn pack_splits_a_group_wider_than_the_line_between_segments() {
        let g = groups(&[&["model", "ctx:129k/1.0M (13%)", "1h 5m", "$7.42", "cache 42m"]]);
        assert_eq!(
            pack_groups(&g, Some(30)),
            vec!["model · ctx:129k/1.0M (13%)", "1h 5m · $7.42 · cache 42m"]
        );
    }

    #[test]
    fn pack_measures_without_ansi() {
        let g = groups(&[&["\x1b[32mabc\x1b[0m"], &["\x1b[2mdef\x1b[0m"]]);
        assert_eq!(pack_groups(&g, Some(8)).len(), 1);
        assert_eq!(pack_groups(&g, Some(7)).len(), 2);
    }

    #[test]
    fn profiles_render_without_brackets() {
        let dir = std::env::temp_dir().join(format!("statusline-profiles-{}", std::process::id()));
        std::fs::create_dir_all(dir.join(".claude")).unwrap();
        std::fs::write(dir.join(".claude/context.yaml"), "profiles: [code, python]\n").unwrap();
        let mut out = String::new();
        format_context_profiles(&mut out, dir.to_str().unwrap());
        let _ = std::fs::remove_dir_all(&dir);
        assert_eq!(out, "\x1b[36mcode python\x1b[0m ");
    }

    #[test]
    fn utc_timestamps_parse_to_unix_seconds() {
        assert_eq!(parse_utc_timestamp("1970-01-01T00:00:00Z"), Some(0));
        assert_eq!(parse_utc_timestamp("2026-10-14T04:59:26.105Z"), Some(1_791_953_966));
        assert_eq!(parse_utc_timestamp("2024-02-29T12:00:00Z"), Some(1_709_208_000));
        assert_eq!(parse_utc_timestamp("2026-10-14T04:59:26+01:00"), None);
        assert_eq!(parse_utc_timestamp("garbage"), None);
    }

    #[test]
    fn since_renders_age_and_idle_and_hides_under_a_minute() {
        assert_eq!(format_since_str("age", Some(0), 2 * 86_400 + 3 * 3_600).unwrap(), "\x1b[2mage 2d3h\x1b[0m");
        assert_eq!(format_since_str("idle", Some(100), 100 + 12 * 60).unwrap(), "\x1b[2midle 12m\x1b[0m");
        assert_eq!(format_since_str("idle", Some(100), 159), None);
        assert_eq!(format_since_str("idle", None, 159), None);
    }

    #[test]
    fn transcript_times_skip_metadata_and_resume_lines() {
        let path = std::env::temp_dir().join(format!("statusline-transcript-{}.jsonl", std::process::id()));
        // Untimestamped metadata first; after the last real turn, a resume's
        // attachment, system line and meta user line, which must not count.
        let filler = "x".repeat(300 * 1024);
        let lines = [
            r#"{"type":"ai-title","title":"t"}"#.to_string(),
            r#"{"type":"attachment","timestamp":"2026-10-12T07:44:37.735Z"}"#.to_string(),
            r#"{"type":"user","timestamp":"2026-10-12T07:45:00.000Z","message":{"role":"user"}}"#.to_string(),
            r#"{"type":"assistant","timestamp":"2026-10-14T04:59:29.770Z"}"#.to_string(),
            format!(r#"{{"type":"attachment","timestamp":"2026-10-17T20:00:00.000Z","pad":"{}"}}"#, filler),
            r#"{"type":"system","timestamp":"2026-10-17T20:00:01.000Z"}"#.to_string(),
            r#"{"type":"user","isMeta":true,"timestamp":"2026-10-17T20:00:02.000Z"}"#.to_string(),
        ];
        std::fs::write(&path, lines.join("\n") + "\n").unwrap();
        let started = transcript_started_at(&path);
        let last = transcript_last_active_at(&path);
        let _ = std::fs::remove_file(&path);
        assert_eq!(started, parse_utc_timestamp("2026-10-12T07:44:37Z"));
        assert_eq!(last, parse_utc_timestamp("2026-10-14T04:59:29Z"));
    }
}

