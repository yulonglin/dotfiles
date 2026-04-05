//! API usage tracking for Claude Code statusline.
//!
//! Fetches 5-hour and 7-day rate limit utilization from the Anthropic OAuth
//! usage endpoint, with file-based caching (60s TTL) and graceful degradation.
//!
//! Fetch strategy: ureq (native Rust) → curl fallback → stale cache → error.

use serde::Deserialize;
use std::fmt::Write;
use std::path::PathBuf;
use std::time::Duration;

// --- Constants ---

const API_URL: &str = "https://api.anthropic.com/api/oauth/usage";
const CACHE_FILENAME: &str = "claude-statusline-usage.json";
const CACHE_MAX_AGE: Duration = Duration::from_secs(300);
const REQUEST_TIMEOUT: Duration = Duration::from_secs(2);

const SEVEN_DAY_SECS: f64 = 7.0 * 86400.0;

// --- API response ---

#[derive(Deserialize, Clone)]
pub struct UsageResponse {
    pub five_hour: Option<UsageBucket>,
    pub seven_day: Option<UsageBucket>,
}

#[derive(Deserialize, Clone)]
pub struct UsageBucket {
    pub utilization: Option<f64>,
    pub resets_at: Option<String>,
}

// --- Public entry point ---

/// Append usage bars (or error) to output as a second statusline line.
pub fn format_usage(output: &mut String) {
    match fetch_cached_usage() {
        Ok(usage) => format_usage_bars(output, &usage),
        Err(e) => {
            output.push('\n');
            let _ = write!(output, "\x1b[2m\x1b[31m{}\x1b[0m", e);
        }
    }
}

fn format_usage_bars(output: &mut String, usage: &UsageResponse) {
    let five = usage.five_hour.as_ref().and_then(|b| b.utilization);
    let seven = usage.seven_day.as_ref().and_then(|b| b.utilization);

    if five.is_none() && seven.is_none() {
        output.push('\n');
        let _ = write!(output, "\x1b[2m\u{2014}\x1b[0m"); // dim em-dash placeholder
        return;
    }

    output.push('\n');

    if let Some(pct) = five {
        let pct = pct.round().clamp(0.0, 100.0) as u8;
        format_bar(output, "5h", pct);
        format_reset_time(output, usage.five_hour.as_ref());
    }

    if let Some(pct) = seven {
        let pct = pct.round().clamp(0.0, 100.0) as u8;
        if five.is_some() {
            output.push_str("  \u{00b7}  ");
        }
        format_bar(output, "7d", pct);
        format_pace(output, pct, usage.seven_day.as_ref());
    }

}

// --- Bar rendering ---

fn format_bar(output: &mut String, label: &str, pct: u8) {
    const BAR_WIDTH: u8 = 10;
    let filled = (pct as u16 * BAR_WIDTH as u16 / 100).min(BAR_WIDTH as u16) as u8;
    let empty = BAR_WIDTH - filled;

    let color = color_for_pct(pct);

    let _ = write!(output, "{}{}\x1b[0m ", color, label);
    let _ = write!(output, "{}", color);
    for _ in 0..filled {
        output.push('●');
    }
    output.push_str("\x1b[2m");
    for _ in 0..empty {
        output.push('○');
    }
    let _ = write!(output, "\x1b[0m {}{}%\x1b[0m", color, pct);
}

/// Append time remaining until reset for a bucket (e.g., "⟳ 2h30m").
/// Uses countdown (timezone-independent) so it works correctly on remote servers.
fn format_reset_time(output: &mut String, bucket: Option<&UsageBucket>) {
    let resets_at = match bucket.and_then(|b| b.resets_at.as_deref()) {
        Some(s) => s,
        None => return,
    };
    if let Some(epoch) = parse_iso_epoch(resets_at) {
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs() as i64;
        let remaining_secs = (epoch - now).max(0) as f64;
        let display = fmt_time_remaining(remaining_secs);
        if !display.is_empty() {
            let _ = write!(output, " \x1b[2m\u{27f3} {}\x1b[0m", display);
        }
    }
}

/// Show pace indicator and reset date for the 7-day bucket.
///
/// Pace = how far ahead or behind the linear burn rate you are.
/// If the window is 4/7 elapsed and you've used 61%, expected is ~57%,
/// so you're +4% ahead of pace.
fn format_pace(output: &mut String, pct: u8, bucket: Option<&UsageBucket>) {
    let resets_at = match bucket.and_then(|b| b.resets_at.as_deref()) {
        Some(s) => s,
        None => return,
    };

    if let Some(reset_epoch) = parse_iso_epoch(resets_at) {
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs() as i64;

        let remaining_secs = (reset_epoch - now).max(0) as f64;
        let elapsed_secs = SEVEN_DAY_SECS - remaining_secs;
        let elapsed_frac = (elapsed_secs / SEVEN_DAY_SECS).clamp(0.0, 1.0);

        let expected_pct = (elapsed_frac * 100.0).round() as i16;
        let delta = pct as i16 - expected_pct;

        // Pace indicator: green if under, red if over
        let (sign, pace_color) = if delta > 0 {
            ("+", "\x1b[31m") // Red — ahead of pace (using more)
        } else if delta < 0 {
            ("", "\x1b[32m") // Green — behind pace (have headroom)
        } else {
            ("", "\x1b[2m") // Dim — on pace
        };

        let _ = write!(output, " {}{}{}%\x1b[0m", pace_color, sign, delta);

        // Time remaining until reset
        let reset_display = fmt_time_remaining(remaining_secs);
        if !reset_display.is_empty() {
            let _ = write!(output, " \x1b[2m\u{27f3} {}\x1b[0m", reset_display);
        }
    }
}

/// Format remaining seconds as a compact countdown: "2h30m" / "45m" / "5d3h".
fn fmt_time_remaining(secs: f64) -> String {
    let mins = (secs / 60.0).round() as u32;
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

/// Parse ISO 8601 timestamp to unix epoch. Handles common formats from the API.
fn parse_iso_epoch(iso: &str) -> Option<i64> {
    // Try macOS date -j first
    let stripped = iso.split('.').next().unwrap_or(iso);
    let stripped = stripped.trim_end_matches('Z');

    // macOS: date -j -f format
    let output = std::process::Command::new("date")
        .args(["-j", "-u", "-f", "%Y-%m-%dT%H:%M:%S", stripped, "+%s"])
        .stderr(std::process::Stdio::null())
        .output();

    if let Ok(o) = output {
        if o.status.success() {
            if let Ok(s) = String::from_utf8(o.stdout) {
                if let Ok(epoch) = s.trim().parse::<i64>() {
                    return Some(epoch);
                }
            }
        }
    }

    // Linux fallback: date -d
    let output = std::process::Command::new("date")
        .args(["-d", iso, "+%s"])
        .stderr(std::process::Stdio::null())
        .output();

    if let Ok(o) = output {
        if o.status.success() {
            if let Ok(s) = String::from_utf8(o.stdout) {
                if let Ok(epoch) = s.trim().parse::<i64>() {
                    return Some(epoch);
                }
            }
        }
    }

    None
}

fn color_for_pct(pct: u8) -> &'static str {
    if pct >= 90 {
        "\x1b[31m" // Red
    } else if pct >= 70 {
        "\x1b[33m" // Yellow
    } else if pct >= 50 {
        "\x1b[38;2;255;176;85m" // Orange
    } else {
        "\x1b[32m" // Green
    }
}

// --- Caching ---

fn cache_path() -> Option<PathBuf> {
    let dir = std::env::var("TMPDIR")
        .unwrap_or_else(|_| "/tmp/claude".to_string());
    let dir = PathBuf::from(dir);
    std::fs::create_dir_all(&dir).ok()?;
    Some(dir.join(CACHE_FILENAME))
}

fn read_cache() -> Option<(UsageResponse, bool)> {
    let path = cache_path()?;
    let metadata = std::fs::metadata(&path).ok()?;
    let age = metadata.modified().ok()?.elapsed().unwrap_or(Duration::MAX);
    let fresh = age < CACHE_MAX_AGE;
    let data = std::fs::read_to_string(&path).ok()?;
    let usage: UsageResponse = serde_json::from_str(&data).ok()?;
    Some((usage, fresh))
}

fn write_cache(data: &str) {
    if let Some(path) = cache_path() {
        let _ = std::fs::write(&path, data);
    }
}

// --- Token resolution ---

fn resolve_oauth_token() -> Result<String, &'static str> {
    // 1. Environment variable
    if let Ok(token) = std::env::var("CLAUDE_CODE_OAUTH_TOKEN") {
        if !token.is_empty() {
            return Ok(token);
        }
    }

    // 2. macOS Keychain
    if let Some(token) = token_from_keychain() {
        return Ok(token);
    }

    // 3. Credentials file
    token_from_credentials_file().ok_or("no oauth token found")
}

fn token_from_keychain() -> Option<String> {
    let output = std::process::Command::new("security")
        .args(["find-generic-password", "-s", "Claude Code-credentials", "-w"])
        .stderr(std::process::Stdio::null())
        .output()
        .ok()?;

    if !output.status.success() {
        return None;
    }

    let blob = String::from_utf8(output.stdout).ok()?;
    extract_access_token(blob.trim())
}

fn token_from_credentials_file() -> Option<String> {
    let home = std::env::var("HOME").ok()?;
    let path = format!("{}/.claude/.credentials.json", home);
    let data = std::fs::read_to_string(path).ok()?;
    extract_access_token(&data)
}

fn extract_access_token(json_str: &str) -> Option<String> {
    let v: serde_json::Value = serde_json::from_str(json_str).ok()?;
    v.get("claudeAiOauth")?
        .get("accessToken")?
        .as_str()
        .filter(|s| !s.is_empty())
        .map(|s| s.to_string())
}

// --- API fetch (ureq → curl fallback) ---

fn fetch_from_api(token: &str) -> Result<(UsageResponse, String), String> {
    // Try ureq first
    if let Some(result) = fetch_via_ureq(token) {
        return Ok(result);
    }

    // Fall back to curl
    fetch_via_curl(token)
}

fn fetch_via_ureq(token: &str) -> Option<(UsageResponse, String)> {
    let config = ureq::Agent::config_builder()
        .timeout_global(Some(REQUEST_TIMEOUT))
        .build();
    let agent: ureq::Agent = config.into();

    let mut response = agent
        .get(API_URL)
        .header("Authorization", &format!("Bearer {}", token))
        .header("Accept", "application/json")
        .header("anthropic-beta", "oauth-2025-04-20")
        .call()
        .ok()?;

    let body = response.body_mut().read_to_string().ok()?;
    let usage: UsageResponse = serde_json::from_str(&body).ok()?;
    Some((usage, body))
}

fn fetch_via_curl(token: &str) -> Result<(UsageResponse, String), String> {
    let output = std::process::Command::new("curl")
        .args([
            "-s",
            "--max-time", "2",
            "-H", &format!("Authorization: Bearer {}", token),
            "-H", "Accept: application/json",
            "-H", "anthropic-beta: oauth-2025-04-20",
            API_URL,
        ])
        .stderr(std::process::Stdio::null())
        .output()
        .map_err(|_| "curl not available".to_string())?;

    if !output.status.success() {
        return Err("api request failed".to_string());
    }

    let body = String::from_utf8(output.stdout)
        .map_err(|_| "invalid response".to_string())?;
    let usage: UsageResponse = serde_json::from_str(&body)
        .map_err(|_| "invalid json from api".to_string())?;
    Ok((usage, body))
}

// --- Orchestration ---

/// Return cached usage if fresh, otherwise fetch and update cache.
/// Falls back to stale cache on fetch failure. Returns error only when
/// no data is available at all.
fn fetch_cached_usage() -> Result<UsageResponse, String> {
    let cached = read_cache();

    // Fresh cache — fast path
    if let Some((ref usage, true)) = cached {
        return Ok(usage.clone());
    }

    // Need to fetch (stale or no cache)
    let token = resolve_oauth_token();

    if let Ok(ref token) = token {
        match fetch_from_api(token) {
            Ok((usage, raw)) => {
                // Only cache and return if at least one utilization value is present,
                // otherwise fall through to stale cache
                let has_data = usage.five_hour.as_ref().and_then(|b| b.utilization).is_some()
                    || usage.seven_day.as_ref().and_then(|b| b.utilization).is_some();
                if has_data {
                    write_cache(&raw);
                    return Ok(usage);
                }
                // Null utilization — prefer stale cache if available
                if let Some((stale, _)) = &cached {
                    return Ok(stale.clone());
                }
                return Ok(usage);
            }
            Err(fetch_err) => {
                // Fall back to stale cache
                if let Some((usage, _)) = cached {
                    return Ok(usage);
                }
                return Err(fetch_err);
            }
        }
    }

    // No token — use stale cache or error
    if let Some((usage, _)) = cached {
        return Ok(usage);
    }

    Err(token.unwrap_err().to_string())
}
