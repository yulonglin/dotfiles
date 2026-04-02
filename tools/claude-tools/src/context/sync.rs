use std::collections::{BTreeMap, HashSet};
use std::path::Path;
use std::process::Command;
use super::profiles::MarketplaceConfig;
use crate::util::{self, expand_home, plugin_short_name, atomic_write_json};

/// Main sync entry point.
pub fn run(verbose: bool, prune: bool) -> Result<(), Box<dyn std::error::Error>> {
    if which("claude").is_none() {
        println!("{}Claude CLI not found — skipping marketplace sync.{}", util::YELLOW, util::RESET);
        return Ok(());
    }

    let marketplaces = super::profiles::load_marketplaces()?;
    if marketplaces.is_empty() {
        println!("{}No marketplaces defined in profiles.yaml{}", util::YELLOW, util::RESET);
        return Ok(());
    }

    let wanted = super::profiles::collect_wanted_plugins()?;
    if verbose {
        println!("  Wanted plugins (from profiles): {}", wanted.len());
    }

    let registered = get_registered_marketplaces();

    // Phase 1: Register new marketplaces (sequential — rare)
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
                }
                Err(e) => {
                    eprintln!("{}  {}: registration failed — {}{}", util::RED, name, e, util::RESET);
                    errors += 1;
                }
                _ => {}
            }
        } else if verbose {
            println!("  {}: already registered", name);
        }
    }

    // Phase 2: Update only marketplaces that contain wanted plugins
    let marketplace_index = build_marketplace_index(None);
    let needed_marketplaces: HashSet<&str> = wanted.iter()
        .filter_map(|p| marketplace_index.get(p.as_str()).map(|s| s.as_str()))
        .collect();

    // Also include marketplaces for plugins not yet in the index (not cloned yet)
    let unmapped: Vec<&str> = wanted.iter()
        .filter(|p| !marketplace_index.contains_key(p.as_str()))
        .map(|s| s.as_str())
        .collect();

    let to_update: Vec<String> = marketplaces.keys()
        .filter(|name| {
            needed_marketplaces.contains(name.as_str())
                || (!unmapped.is_empty() && registered.contains(*name))
        })
        .cloned()
        .collect();

    if verbose {
        let skipped = marketplaces.len() - to_update.len();
        if skipped > 0 {
            println!("  Skipping {} marketplace(s) with no wanted plugins", skipped);
        }
        if !unmapped.is_empty() {
            println!("  Unmapped plugins (updating all registered): {:?}", unmapped);
        }
        println!("  Updating {} marketplace(s) in parallel...", to_update.len());
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

    let total = to_update.len();
    if errors > 0 {
        println!("{}Synced {}/{} marketplace(s) ({} error(s)){}", util::YELLOW, synced, total, errors, util::RESET);
    } else {
        println!("{}Synced {}/{} marketplace(s){}", util::GREEN, synced, total, util::RESET);
    }

    // Phase 3: Selective install — install wanted plugins not yet installed
    // Rebuild index after marketplace updates (new plugins may now be discoverable).
    // Load installed_plugins.json once and share across Phase 3-4.
    let installed_data = load_installed_json().unwrap_or_else(|_| serde_json::json!({"plugins": {}}));
    let marketplace_index = build_marketplace_index(Some(&installed_data));
    let installed_short = installed_short_names(&installed_data);
    selective_install(&wanted, &marketplace_index, &installed_short, verbose)?;

    // Phase 4: Prune orphans (opt-in)
    let orphans = find_orphans(&wanted, &installed_data);
    if prune {
        prune_orphans(&orphans, verbose)?;
    } else if !orphans.is_empty() {
        println!("{}  {} orphan plugin(s) not in profiles (use --prune to remove): {}{}",
            util::YELLOW, orphans.len(), orphans.join(", "), util::RESET);
    }

    // Phase 5: Post-fixups (unchanged)
    fix_hook_permissions(verbose);
    apply_auto_update(&marketplaces, verbose)?;
    normalize_scopes(&wanted, verbose)?;

    Ok(())
}

/// Load and parse installed_plugins.json.
fn load_installed_json() -> Result<serde_json::Value, Box<dyn std::error::Error>> {
    let path = expand_home(super::INSTALLED_PLUGINS_PATH);
    let content = std::fs::read_to_string(&path)?;
    Ok(serde_json::from_str(&content)?)
}

/// Extract short plugin names from parsed installed data.
fn installed_short_names(data: &serde_json::Value) -> HashSet<String> {
    data.get("plugins").and_then(|v| v.as_object())
        .map(|plugins| plugins.keys().map(|qid| plugin_short_name(qid).to_string()).collect())
        .unwrap_or_default()
}

/// Build plugin_short_name -> marketplace_name index by scanning marketplace dirs.
/// If `installed_data` is provided, augments from it; otherwise reads from disk.
fn build_marketplace_index(installed_data: Option<&serde_json::Value>) -> BTreeMap<String, String> {
    let dir = expand_home(super::MARKETPLACES_DIR);
    let mut index = BTreeMap::new();

    let Ok(entries) = std::fs::read_dir(&dir) else { return index };
    for entry in entries.flatten() {
        let marketplace_name = entry.file_name().to_string_lossy().to_string();
        let marketplace_path = entry.path();
        let plugins_dir = marketplace_path.join("plugins");

        if plugins_dir.is_dir() {
            // Multi-plugin marketplace: each subdir is a plugin
            if let Ok(plugins) = std::fs::read_dir(&plugins_dir) {
                for plugin in plugins.flatten() {
                    if plugin.path().is_dir() {
                        let plugin_name = plugin.file_name().to_string_lossy().to_string();
                        index.insert(plugin_name, marketplace_name.clone());
                    }
                }
            }
        } else {
            // Single-plugin marketplace: derive name from package.json or installed_plugins.json
            let plugin_name = single_plugin_name(&marketplace_path, &marketplace_name);
            index.insert(plugin_name, marketplace_name.clone());
        }
    }

    // Also include mappings from installed_plugins.json (authoritative for already-installed)
    let loaded;
    let data = match installed_data {
        Some(d) => d,
        None => {
            loaded = load_installed_json().ok();
            match loaded.as_ref() {
                Some(d) => d,
                None => return index,
            }
        }
    };
    if let Some(plugins) = data.get("plugins").and_then(|v| v.as_object()) {
        for qid in plugins.keys() {
            let short = plugin_short_name(qid).to_string();
            if let Some(at_pos) = qid.find('@') {
                let marketplace = &qid[at_pos + 1..];
                index.insert(short, marketplace.to_string());
            }
        }
    }

    index
}

/// Derive plugin name for a single-plugin marketplace.
fn single_plugin_name(marketplace_path: &Path, marketplace_name: &str) -> String {
    // Try package.json "name" field
    let pkg = marketplace_path.join("package.json");
    if let Ok(content) = std::fs::read_to_string(&pkg) {
        if let Ok(data) = serde_json::from_str::<serde_json::Value>(&content) {
            if let Some(name) = data.get("name").and_then(|v| v.as_str()) {
                return name.to_string();
            }
        }
    }
    // Fallback: marketplace name itself (works for rust-skills, etc.)
    marketplace_name.to_string()
}

/// Sequentially install wanted plugins not yet installed.
/// Sequential because `claude plugin install` does read-modify-write on
/// installed_plugins.json — parallel installs would race on that file.
fn selective_install(
    wanted: &HashSet<String>,
    marketplace_index: &BTreeMap<String, String>,
    installed_short: &HashSet<String>,
    verbose: bool,
) -> Result<(), Box<dyn std::error::Error>> {
    let to_install: Vec<(String, String)> = wanted.iter()
        .filter(|p| !installed_short.contains(*p))
        .filter_map(|p| {
            marketplace_index.get(p.as_str())
                .map(|m| (p.clone(), format!("{}@{}", p, m)))
        })
        .collect();

    if to_install.is_empty() {
        if verbose {
            println!("  All wanted plugins already installed");
        }
        return Ok(());
    }

    let unmapped: Vec<&String> = wanted.iter()
        .filter(|p| !installed_short.contains(p.as_str()) && !marketplace_index.contains_key(p.as_str()))
        .collect();
    if !unmapped.is_empty() {
        println!("{}  Could not find marketplace for: {}{}", util::YELLOW,
            unmapped.iter().map(|s| s.as_str()).collect::<Vec<_>>().join(", "), util::RESET);
    }

    println!("  Installing {} new plugin(s)...", to_install.len());
    for (short, qualified) in &to_install {
        let result = Command::new("claude")
            .args(["plugin", "install", qualified, "--scope", "user"])
            .output();
        match result {
            Ok(out) if out.status.success() => {
                println!("  {}✔{} installed {}", util::GREEN, util::RESET, short);
            }
            Ok(out) => {
                let err = String::from_utf8_lossy(&out.stderr);
                println!("{}  {}: {}{}", util::YELLOW, short, err.trim(), util::RESET);
            }
            Err(e) => {
                println!("{}  {}: {}{}", util::YELLOW, short, e, util::RESET);
            }
        }
    }

    Ok(())
}

/// Find orphan plugins (installed but not in any profile).
fn find_orphans(wanted: &HashSet<String>, installed_data: &serde_json::Value) -> Vec<String> {
    let Some(plugins) = installed_data.get("plugins").and_then(|v| v.as_object()) else { return vec![] };
    plugins.keys()
        .filter(|qid| !wanted.contains(&*plugin_short_name(qid)))
        .cloned()
        .collect()
}

/// Remove orphan plugins directly from installed_plugins.json and enabledPlugins.
/// Direct manipulation avoids Claude CLI's refusal to uninstall plugins referenced
/// in project settings.json (even when set to false).
fn prune_orphans(orphans: &[String], verbose: bool) -> Result<(), Box<dyn std::error::Error>> {
    if orphans.is_empty() {
        if verbose {
            println!("  No orphan plugins to prune");
        }
        return Ok(());
    }

    // Re-read installed_plugins.json for mutation (Phase 3 installs may have modified it)
    let installed_path = expand_home(super::INSTALLED_PLUGINS_PATH);
    let content = std::fs::read_to_string(&installed_path)?;
    let mut data: serde_json::Value = serde_json::from_str(&content)?;

    if let Some(plugins) = data.get_mut("plugins").and_then(|v| v.as_object_mut()) {
        for qid in orphans {
            plugins.remove(qid);
        }
    }
    atomic_write_json(&installed_path, &data)?;

    // Remove from enabledPlugins in both project and global settings.
    // Write may fail due to sandbox restrictions on settings.json — that's OK,
    // enabledPlugins gets rebuilt on next `claude-tools context <profile>` apply.
    for settings_path in &[super::TARGET_FILE, super::GLOBAL_SETTINGS] {
        let path = expand_home(settings_path);
        if !Path::new(&path).exists() { continue; }
        let Ok(content) = std::fs::read_to_string(&path) else { continue };
        let Ok(mut settings) = serde_json::from_str::<serde_json::Value>(&content) else { continue };

        let mut changed = false;
        if let Some(enabled) = settings.get_mut("enabledPlugins").and_then(|v| v.as_object_mut()) {
            for qid in orphans {
                if enabled.remove(qid).is_some() {
                    changed = true;
                }
            }
        }
        if changed {
            match atomic_write_json(&path, &settings) {
                Ok(()) => {
                    if verbose {
                        println!("  Cleaned enabledPlugins in {}", settings_path);
                    }
                }
                Err(e) => {
                    if verbose {
                        println!("{}  Could not update {} ({}), will be cleaned on next profile apply{}",
                            util::YELLOW, settings_path, e, util::RESET);
                    }
                }
            }
        }
    }

    println!("  Pruned {} orphan plugin(s):", orphans.len());
    for qid in orphans {
        println!("  {}✔{} {}", util::GREEN, util::RESET, plugin_short_name(qid));
    }

    Ok(())
}

fn which(cmd: &str) -> Option<String> {
    Command::new("which").arg(cmd).output().ok()
        .filter(|o| o.status.success())
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
}

fn get_registered_marketplaces() -> HashSet<String> {
    let mut set = HashSet::new();
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

fn normalize_scopes(wanted: &HashSet<String>, verbose: bool) -> Result<(), Box<dyn std::error::Error>> {
    let path = expand_home(super::INSTALLED_PLUGINS_PATH);
    if !Path::new(&path).exists() {
        return Ok(());
    }
    let content = std::fs::read_to_string(&path)?;
    let mut data: serde_json::Value = serde_json::from_str(&content)?;
    let mut upgraded = Vec::new();
    let mut deduped = Vec::new();

    if let Some(plugins) = data.get_mut("plugins").and_then(|v| v.as_object_mut()) {
        for (qid, entries) in plugins.iter_mut() {
            let short = plugin_short_name(qid).to_string();
            let Some(arr) = entries.as_array_mut() else { continue };
            let has_user = arr.iter().any(|e| e.get("scope").and_then(|v| v.as_str()) == Some("user"));

            if has_user && arr.len() > 1 {
                // Drop stale non-user entries when a user-scoped entry exists.
                let before = arr.len();
                arr.retain(|e| e.get("scope").and_then(|v| v.as_str()) == Some("user"));
                if arr.len() < before {
                    deduped.push(short);
                }
            } else if wanted.contains(&short) {
                // Upgrade wanted plugins (managed by --sync) to user scope.
                // Manually-installed project-scoped plugins are left alone.
                for entry in arr.iter_mut() {
                    let scope = entry.get("scope").and_then(|v| v.as_str()).unwrap_or("");
                    if scope == "local" || scope == "project" {
                        if let Some(e) = entry.as_object_mut() {
                            e.insert("scope".into(), "user".into());
                            e.remove("projectPath");
                        }
                        upgraded.push(short.clone());
                    }
                }
            }
        }
    }

    if !upgraded.is_empty() || !deduped.is_empty() {
        atomic_write_json(&path, &data)?;
        if !upgraded.is_empty() {
            println!("{}Upgraded {} plugin scope(s) → user{}", util::GREEN, upgraded.len(), util::RESET);
            if verbose {
                for name in &upgraded { println!("  {}", name); }
            }
        }
        if !deduped.is_empty() {
            println!("{}Removed {} duplicate non-user entries{}", util::GREEN, deduped.len(), util::RESET);
            if verbose {
                for name in &deduped { println!("  {}", name); }
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
