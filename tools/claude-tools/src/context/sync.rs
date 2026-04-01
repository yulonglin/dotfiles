use std::collections::BTreeMap;
use std::path::Path;
use std::process::Command;
use super::profiles::MarketplaceConfig;
use crate::util::{self, expand_home, plugin_short_name, atomic_write_json};

/// Main sync entry point.
pub fn run(verbose: bool) -> Result<(), Box<dyn std::error::Error>> {
    if which("claude").is_none() {
        println!("{}Claude CLI not found — skipping marketplace sync.{}", util::YELLOW, util::RESET);
        return Ok(());
    }

    let marketplaces = super::profiles::load_marketplaces()?;
    if marketplaces.is_empty() {
        println!("{}No marketplaces defined in profiles.yaml{}", util::YELLOW, util::RESET);
        return Ok(());
    }

    let registered = get_registered_marketplaces();

    // Phase 1: Register new marketplaces (sequential — rare)
    let mut to_update = Vec::new();
    let mut errors = 0;
    for (name, config) in &marketplaces {
        let source = resolve_source(name, config);
        let Some(source) = source else {
            eprintln!("{}  {}: no valid source configured{}", util::RED, name, util::RESET);
            errors += 1;
            continue;
        };

        if !registered.contains(name) {
            if verbose {
                println!("  Registering {} ({})...", name, source);
            }
            let result = Command::new("claude")
                .args(["plugin", "marketplace", "add", &source])
                .output();
            match result {
                Ok(out) if !out.status.success() => {
                    let err = String::from_utf8_lossy(&out.stderr);
                    eprintln!("{}  {}: registration failed — {}{}", util::RED, name, err.trim(), util::RESET);
                    errors += 1;
                    continue;
                }
                Err(e) => {
                    eprintln!("{}  {}: registration failed — {}{}", util::RED, name, e, util::RESET);
                    errors += 1;
                    continue;
                }
                _ => {}
            }
        } else if verbose {
            println!("  {}: already registered", name);
        }
        to_update.push(name.clone());
    }

    // Phase 2: Update all in parallel via std::thread
    if verbose {
        println!("  Updating {} marketplaces in parallel...", to_update.len());
    }
    let handles: Vec<_> = to_update.iter().map(|name| {
        let name = name.clone();
        std::thread::spawn(move || {
            let result = Command::new("claude")
                .args(["plugin", "marketplace", "update", &name])
                .output();
            match result {
                Ok(out) if out.status.success() => (name, true, String::new()),
                Ok(out) => (name, false, String::from_utf8_lossy(&out.stderr).trim().to_string()),
                Err(e) => (name, false, e.to_string()),
            }
        })
    }).collect();

    let mut synced = 0;
    for handle in handles {
        let (name, ok, msg) = handle.join().unwrap_or_else(|_| ("?".into(), false, "thread panic".into()));
        if ok {
            synced += 1;
            if verbose {
                println!("  {}✔{} {}", util::GREEN, util::RESET, name);
            }
        } else {
            println!("{}  {}: {}{}", util::YELLOW, name, msg, util::RESET);
        }
    }

    let total = marketplaces.len();
    if errors > 0 {
        println!("{}Synced {}/{} marketplaces ({} error(s)){}", util::YELLOW, synced, total, errors, util::RESET);
    } else {
        println!("{}Synced {}/{} marketplaces{}", util::GREEN, synced, total, util::RESET);
    }

    fix_hook_permissions(verbose);
    apply_auto_update(&marketplaces, verbose)?;
    normalize_scopes(verbose)?;

    Ok(())
}

fn which(cmd: &str) -> Option<String> {
    Command::new("which").arg(cmd).output().ok()
        .filter(|o| o.status.success())
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
}

fn get_registered_marketplaces() -> std::collections::HashSet<String> {
    let mut set = std::collections::HashSet::new();
    if let Ok(out) = Command::new("claude").args(["plugin", "marketplace", "list"]).output() {
        for line in String::from_utf8_lossy(&out.stdout).lines() {
            let line = line.trim();
            if let Some(name) = line.strip_prefix("❯ ") {
                set.insert(name.trim().to_string());
            }
        }
    }
    set
}

fn resolve_source(_name: &str, config: &MarketplaceConfig) -> Option<String> {
    if std::env::var("CLAUDE_CONTEXT_LOCAL").as_deref() == Ok("1") {
        if let Some(local) = &config.local {
            let expanded = expand_env(local);
            if Path::new(&expanded).join(".claude-plugin").is_dir() {
                return Some(expanded);
            }
        }
    }
    config.github.clone()
}

/// Expand ${VAR} syntax only (not bare $VAR).
fn expand_env(s: &str) -> String {
    let mut result = String::new();
    let mut chars = s.chars().peekable();
    while let Some(c) = chars.next() {
        if c == '$' && chars.peek() == Some(&'{') {
            chars.next();
            let key: String = chars.by_ref().take_while(|&c| c != '}').collect();
            let val = std::env::var(&key).unwrap_or_else(|_| {
                match key.as_str() {
                    "CODE_DIR" => expand_home("~/code"),
                    _ => format!("${{{}}}", key),
                }
            });
            result.push_str(&val);
        } else {
            result.push(c);
        }
    }
    expand_home(&result)
}

/// Marketplace hooks may lose execute bits when cloned from git tarballs.
fn fix_hook_permissions(verbose: bool) {
    let dir = expand_home(super::MARKETPLACES_DIR);
    if !Path::new(&dir).is_dir() {
        return;
    }
    let mut fixed = 0u32;
    for entry in walkdir(&dir) {
        if entry.ends_with(".sh") {
            if let Ok(meta) = std::fs::metadata(&entry) {
                use std::os::unix::fs::PermissionsExt;
                let mode = meta.permissions().mode();
                if mode & 0o111 == 0 {
                    let _ = std::fs::set_permissions(&entry, std::fs::Permissions::from_mode(mode | 0o111));
                    fixed += 1;
                    if verbose {
                        if let Ok(rel) = Path::new(&entry).strip_prefix(&dir) {
                            println!("  Fixed permissions: {}", rel.display());
                        }
                    }
                }
            }
        }
    }
    if fixed > 0 && verbose {
        println!("{}Fixed {} hook script(s) missing execute permission{}", util::GREEN, fixed, util::RESET);
    }
}

fn apply_auto_update(
    marketplaces: &BTreeMap<String, MarketplaceConfig>,
    verbose: bool,
) -> Result<(), Box<dyn std::error::Error>> {
    let path = expand_home(super::KNOWN_MARKETPLACES_PATH);
    if !Path::new(&path).exists() {
        return Ok(());
    }
    let content = std::fs::read_to_string(&path)?;
    let mut data: serde_json::Value = serde_json::from_str(&content)?;
    let mut changed = Vec::new();

    if let Some(obj) = data.as_object_mut() {
        for (name, config) in marketplaces {
            let want = config.auto_update.unwrap_or(false);
            if let Some(entry) = obj.get_mut(name) {
                if entry.get("autoUpdate").and_then(|v| v.as_bool()) != Some(want) {
                    entry.as_object_mut().map(|e| e.insert("autoUpdate".into(), want.into()));
                    changed.push(name.clone());
                }
            }
        }
    }

    if !changed.is_empty() {
        atomic_write_json(&path, &data)?;
        if verbose {
            println!("  autoUpdate set for: {}", changed.join(", "));
        }
    }
    Ok(())
}

fn normalize_scopes(verbose: bool) -> Result<(), Box<dyn std::error::Error>> {
    let path = expand_home(super::INSTALLED_PLUGINS_PATH);
    if !Path::new(&path).exists() {
        return Ok(());
    }
    let content = std::fs::read_to_string(&path)?;
    let mut data: serde_json::Value = serde_json::from_str(&content)?;
    let mut changed = Vec::new();

    if let Some(plugins) = data.get_mut("plugins").and_then(|v| v.as_object_mut()) {
        for (qid, entries) in plugins.iter_mut() {
            if let Some(arr) = entries.as_array_mut() {
                for entry in arr.iter_mut() {
                    if entry.get("scope").and_then(|v| v.as_str()) == Some("local") {
                        entry.as_object_mut().map(|e| e.insert("scope".into(), "project".into()));
                        changed.push(plugin_short_name(qid).to_string());
                    }
                }
            }
        }
    }

    if !changed.is_empty() {
        atomic_write_json(&path, &data)?;
        println!("{}Normalized {} plugin scope(s): local → project{}", util::GREEN, changed.len(), util::RESET);
        if verbose {
            for name in &changed {
                println!("  {}", name);
            }
        }
    }
    Ok(())
}

fn walkdir(dir: &str) -> Vec<String> {
    let mut result = Vec::new();
    fn walk(dir: &Path, result: &mut Vec<String>) {
        if let Ok(entries) = std::fs::read_dir(dir) {
            for entry in entries.flatten() {
                let path = entry.path();
                if path.is_dir() {
                    walk(&path, result);
                } else {
                    result.push(path.to_string_lossy().to_string());
                }
            }
        }
    }
    walk(Path::new(dir), &mut result);
    result
}
