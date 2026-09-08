//! Read subscription quotas through Codex's public app-server protocol.
//! No token parsing, private HTTP endpoints, transcript scanning, or model calls.

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::BTreeMap;
use std::hash::{Hash, Hasher};
use std::io::{Read, Write};
use std::os::fd::OwnedFd;
use std::os::unix::fs::MetadataExt;
use std::os::unix::net::UnixStream;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

const CACHE_TTL: u64 = 300;
const FAILURE_BACKOFF: u64 = 60;
const FETCH_TIMEOUT: Duration = Duration::from_millis(2500);
const MAX_RESPONSE_BYTES: usize = 1024 * 1024;

#[derive(Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
struct Window {
    used_percent: i64,
    window_duration_mins: Option<i64>,
    resets_at: Option<i64>,
}

#[derive(Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
struct Bucket {
    limit_id: Option<String>,
    limit_name: Option<String>,
    primary: Option<Window>,
    secondary: Option<Window>,
}

#[derive(Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
struct Quotas {
    rate_limits: Option<Bucket>,
    rate_limits_by_limit_id: Option<BTreeMap<String, Bucket>>,
}

#[derive(Deserialize, Serialize)]
struct Cache {
    auth_stamp: String,
    fetched_at: u64,
    attempted_at: u64,
    quotas: Option<Quotas>,
}

fn now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}

/// Metadata only: changing/replacing auth.json invalidates the account cache.
/// File-backed Codex login is required; keyring-only logins are not probed, so a
/// fake HOME cannot accidentally discover a real account in an OS keychain.
fn auth_stamp(home: &Path) -> Option<String> {
    let m = std::fs::metadata(home.join("auth.json")).ok()?;
    if !m.is_file() {
        return None;
    }
    Some(format!(
        "{}:{}:{}:{}:{}:{}",
        m.ino(),
        m.len(),
        m.mtime(),
        m.mtime_nsec(),
        m.ctime(),
        m.ctime_nsec()
    ))
}

fn codex_executable() -> Option<PathBuf> {
    std::env::split_paths(&std::env::var_os("PATH")?)
        .map(|p| p.join("codex"))
        .find(|p| std::fs::metadata(p).is_ok_and(|m| m.is_file() && m.mode() & 0o111 != 0))
}

fn cache_path(home: &Path) -> Option<PathBuf> {
    let base = std::env::var_os("XDG_CACHE_HOME")
        .filter(|p| !p.is_empty())
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|p| PathBuf::from(p).join(".cache")))?;
    let directory = base.join("claude-tools");
    std::fs::create_dir_all(&directory).ok()?;
    let mut key = std::collections::hash_map::DefaultHasher::new();
    home.hash(&mut key);
    Some(directory.join(format!("codex-usage-{:016x}.json", key.finish())))
}

fn write_cache(path: &Path, cache: &Cache) {
    // Only the typed quota fields and file metadata are persisted, never the
    // raw RPC response (which can acquire new account fields in later CLIs).
    let Ok(data) = serde_json::to_vec(cache) else {
        return;
    };
    let temporary = path.with_extension(format!("{}.tmp", std::process::id()));
    if std::fs::write(&temporary, data).is_ok() {
        let _ = std::fs::rename(&temporary, path);
    }
    let _ = std::fs::remove_file(temporary);
}

/// Append a separate line; the Claude line and its cache are untouched.
pub fn format_usage(output: &mut String) {
    let home = std::env::var_os("CODEX_HOME")
        .filter(|p| !p.is_empty())
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|p| PathBuf::from(p).join(".codex")));
    let Some(home) = home.and_then(|p| p.canonicalize().ok()) else {
        return;
    };
    let Some(stamp) = auth_stamp(&home) else {
        return;
    };
    let Some(executable) = codex_executable() else {
        return;
    };
    let path = cache_path(&home);
    let mut cache: Cache = path
        .as_ref()
        .and_then(|p| std::fs::read(p).ok())
        .and_then(|data| serde_json::from_slice::<Cache>(&data).ok())
        .filter(|cache| cache.auth_stamp == stamp)
        .unwrap_or(Cache {
            auth_stamp: stamp.clone(),
            fetched_at: 0,
            attempted_at: 0,
            quotas: None,
        });
    let timestamp = now();
    let fresh = cache.quotas.is_some()
        && timestamp
            .checked_sub(cache.fetched_at)
            .is_some_and(|age| age < CACHE_TTL);
    let backoff = timestamp
        .checked_sub(cache.attempted_at)
        .is_some_and(|age| age < FAILURE_BACKOFF);
    if !fresh && !backoff {
        cache.attempted_at = timestamp;
        if let Ok(quotas) = fetch(&executable, &home) {
            cache.fetched_at = now();
            cache.quotas = Some(quotas);
        }
        // A login/logout during the query must not publish old-account data.
        if auth_stamp(&home).as_deref() != Some(&stamp) {
            return;
        }
        if let Some(path) = path.as_ref() {
            write_cache(path, &cache);
        }
    }
    output.push_str("\nCodex ");
    if let Some(quotas) = cache.quotas.as_ref() {
        let stale = now()
            .checked_sub(cache.fetched_at)
            .is_none_or(|age| age >= CACHE_TTL);
        render(output, quotas, now() as i64, stale);
    } else {
        output.push_str("usage unavailable");
    }
}

/// Own the child for every exit path, including malformed JSON and timeouts.
/// There is no reader thread to leak or join on a pipe held open by descendants.
struct Server(Child);
impl Drop for Server {
    fn drop(&mut self) {
        let _ = self.0.kill();
        let _ = self.0.wait();
    }
}

fn fetch(executable: &Path, home: &Path) -> Result<Quotas, ()> {
    let deadline = Instant::now() + FETCH_TIMEOUT;
    // A nonblocking socket as stdout gives stdlib-only deadline-aware reads on
    // both supported OSes. A blocking read_line can hang on a partial line.
    let (mut reader, writer) = UnixStream::pair().map_err(|_| ())?;
    reader.set_nonblocking(true).map_err(|_| ())?;
    let fd: OwnedFd = writer.into();
    let mut server = Server(
        Command::new(executable)
            .arg("app-server")
            .env("CODEX_HOME", home)
            .stdin(Stdio::piped())
            .stdout(Stdio::from(fd))
            .stderr(Stdio::null())
            .spawn()
            .map_err(|_| ())?,
    );
    let mut stdin = server.0.stdin.take().ok_or(())?;
    // These three small writes fit in an empty pipe; keep stdin open until the
    // response arrives. Closing it early asks app-server to shut down.
    writeln!(stdin, "{}", json!({"id":1,"method":"initialize","params":{"clientInfo":{"name":"claude_statusline","version":"1"}}})).map_err(|_| ())?;
    let mut pending = Vec::new();
    read_response(&mut reader, &mut pending, 1, deadline)?;
    writeln!(stdin, "{}", json!({"method":"initialized"})).map_err(|_| ())?;
    writeln!(
        stdin,
        "{}",
        json!({"id":2,"method":"account/rateLimits/read"})
    )
    .map_err(|_| ())?;
    let result = read_response(&mut reader, &mut pending, 2, deadline)?;
    serde_json::from_value(result).map_err(|_| ())
}

fn read_response(
    reader: &mut UnixStream,
    pending: &mut Vec<u8>,
    id: u64,
    deadline: Instant,
) -> Result<Value, ()> {
    let mut buffer = [0u8; 8192];
    loop {
        if Instant::now() >= deadline {
            return Err(());
        }
        if let Some(end) = pending.iter().position(|b| *b == b'\n') {
            let message: Value = serde_json::from_slice(&pending[..end]).map_err(|_| ())?;
            pending.drain(..=end);
            if message.get("method").is_none()
                && message.get("id").and_then(Value::as_u64) == Some(id)
            {
                if message.get("error").is_some() {
                    return Err(());
                }
                return message.get("result").cloned().ok_or(());
            }
            continue; // notifications and responses for other request IDs
        }
        match reader.read(&mut buffer) {
            Ok(0) => return Err(()),
            Ok(n) => {
                pending.extend_from_slice(&buffer[..n]);
                if pending.len() > MAX_RESPONSE_BYTES {
                    return Err(());
                }
            }
            Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                std::thread::sleep(Duration::from_millis(5));
            }
            Err(e) if e.kind() == std::io::ErrorKind::Interrupted => continue,
            Err(_) => return Err(()),
        }
    }
}

fn duration_label(minutes: Option<i64>) -> String {
    match minutes {
        Some(m) if m > 0 && m % 1440 == 0 => format!("{}d", m / 1440),
        Some(m) if m > 0 && m % 60 == 0 => format!("{}h", m / 60),
        Some(m) if m > 0 => format!("{}m", m),
        _ => "window?".to_string(),
    }
}

/// Only the aggregate `codex` quota is shown. Per-model scopes in the same map
/// (Spark, keyed by an opaque `codex_*` id) are separate allowances that do
/// not gate ordinary Codex use, so they are not rendered.
fn aggregate_bucket(quotas: &Quotas) -> Option<&Bucket> {
    match quotas
        .rate_limits_by_limit_id
        .as_ref()
        .filter(|m| !m.is_empty())
    {
        Some(map) => map.get("codex"),
        None => quotas
            .rate_limits
            .as_ref()
            .filter(|b| b.limit_id.as_deref().is_none_or(|id| id == "codex")),
    }
}

fn render(output: &mut String, quotas: &Quotas, timestamp: i64, stale: bool) {
    let mut count = 0;
    if let Some(bucket) = aggregate_bucket(quotas) {
        for window in [bucket.primary.as_ref(), bucket.secondary.as_ref()]
            .into_iter()
            .flatten()
        {
            if count > 0 {
                output.push_str(" · ");
            }
            count += 1;
            let label = duration_label(window.window_duration_mins);
            let pct = window.used_percent.clamp(0, 100) as u8;
            let expired = window.resets_at.is_some_and(|reset| reset <= timestamp);
            // Historical values do not have a current burn pace. Do not turn a
            // past reset into a made-up 0% allowance, either.
            let reset = if stale || expired {
                None
            } else {
                window.resets_at
            };
            let seconds = window
                .window_duration_mins
                .filter(|m| *m > 0)
                .map(|m| m as f64 * 60.0);
            crate::usage::render_epoch_bucket(output, &label, pct, reset, seconds, timestamp);
            if expired {
                output.push_str(" (expired)");
            }
        }
    }
    if count == 0 {
        output.push_str("usage unavailable");
    }
    if stale {
        output.push_str(" (stale)");
    }
}
