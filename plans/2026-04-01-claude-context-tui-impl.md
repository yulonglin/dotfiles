# claude-context TUI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Python `claude-context` CLI with a Rust implementation inside `claude-tools`, adding an interactive TUI for profile selection via `ratatui`.

**Architecture:** Extend the existing `claude-tools` binary with a `context` subcommand. Core logic (registry, profiles, builder, settings) is extracted from `context_apply.rs` into a `context/` module. TUI uses ratatui with Elm-style Model/Update/View. Non-interactive CLI modes (apply, list, sync, clean) are plain stdout. clap derive handles arg parsing within the `context` subcommand only; top-level routing stays manual.

**Tech Stack:** Rust, ratatui 0.30, crossterm 0.29, clap 4.6, serde/serde_json/serde_yaml (existing)

**Spec:** `plans/2026-04-01-claude-context-tui.md`

---

### Task 1: Add dependencies and create module skeleton

**Files:**
- Modify: `tools/claude-tools/Cargo.toml`
- Create: `tools/claude-tools/src/util.rs`
- Create: `tools/claude-tools/src/context/mod.rs`
- Create: `tools/claude-tools/src/context/registry.rs`
- Create: `tools/claude-tools/src/context/profiles.rs`
- Create: `tools/claude-tools/src/context/builder.rs`
- Create: `tools/claude-tools/src/context/settings.rs`
- Create: `tools/claude-tools/src/context/sync.rs`
- Create: `tools/claude-tools/src/context/display.rs`
- Create: `tools/claude-tools/src/context/tui/mod.rs`
- Create: `tools/claude-tools/src/context/tui/state.rs`
- Create: `tools/claude-tools/src/context/tui/theme.rs`

- [ ] **Step 1: Add dependencies to Cargo.toml**

Add after the existing `[dependencies]` entries:

```toml
ratatui = "0.30"
crossterm = "0.29"
clap = { version = "4.6", features = ["derive"] }
```

- [ ] **Step 2: Create `src/util.rs` with shared `expand_home`**

```rust
/// Expand `~/` prefix to the user's home directory.
pub fn expand_home(path: &str) -> String {
    if let Some(rest) = path.strip_prefix("~/") {
        if let Ok(home) = std::env::var("HOME") {
            return format!("{}/{}", home, rest);
        }
    }
    path.to_string()
}
```

- [ ] **Step 3: Create empty module files**

Create these files with minimal content so the project compiles:

`src/context/mod.rs`:
```rust
pub mod registry;
pub mod profiles;
pub mod builder;
pub mod settings;
pub mod sync;
pub mod display;
pub mod tui;

use clap::Parser;

#[derive(Parser, Debug)]
#[command(name = "context", about = "YAML-driven plugin profiles for Claude Code")]
pub struct ContextArgs {
    /// Profile names to apply
    #[arg()]
    pub profiles: Vec<String>,

    /// Show active plugins and available profiles
    #[arg(long)]
    pub list: bool,

    /// Remove project plugin config
    #[arg(long, alias = "reset")]
    pub clean: bool,

    /// Force --clean even on git-tracked files
    #[arg(long, short)]
    pub force: bool,

    /// Sync plugin marketplaces from profiles.yaml
    #[arg(long, alias = "sync-marketplaces")]
    pub sync: bool,

    /// Verbose output (for --sync)
    #[arg(short, long)]
    pub verbose: bool,

    /// Explicit non-interactive apply (for hooks)
    #[arg(long)]
    pub apply: bool,

    /// Force TUI even when not a TTY
    #[arg(long)]
    pub tui: bool,
}

/// Entry point called from main.rs. Parses remaining args via clap.
pub fn run(args: Vec<String>) -> Result<(), Box<dyn std::error::Error>> {
    let ctx_args = ContextArgs::parse_from(args);

    if ctx_args.sync {
        sync::run(ctx_args.verbose)?;
    } else if ctx_args.list {
        display::show_status()?;
    } else if ctx_args.clean {
        settings::reset(ctx_args.force)?;
    } else if !ctx_args.profiles.is_empty() {
        // Non-interactive apply with specified profiles
        let reg = registry::load_registry()?;
        let (base, profiles) = profiles::load_profiles()?;
        let enabled = builder::build_plugins(&reg, &base, &profiles, &ctx_args.profiles, &[], &[])?;
        settings::apply_to_settings(&enabled)?;
        settings::write_context_yaml(&ctx_args.profiles, &[], &[])?;
        display::print_apply_summary(&ctx_args.profiles, &enabled);
    } else if ctx_args.apply {
        // Explicit apply from context.yaml (hook path)
        let applied = settings::apply_from_context_yaml()?;
        if applied {
            display::print_context_yaml_summary()?;
        }
    } else if ctx_args.tui || std::io::IsTerminal::is_terminal(&std::io::stdout()) {
        // Interactive TUI
        tui::run()?;
    } else {
        // No TTY, no args: apply context.yaml if present, then show status
        let _ = settings::apply_from_context_yaml();
        display::show_status()?;
    }

    Ok(())
}
```

`src/context/registry.rs`:
```rust
use std::collections::BTreeMap;
use serde::Deserialize;
use crate::util::expand_home;

const INSTALLED_PLUGINS: &str = "~/.claude/plugins/installed_plugins.json";

#[derive(Deserialize)]
struct InstalledPlugins {
    plugins: Option<BTreeMap<String, serde_json::Value>>,
}

/// Load plugin registry: short_name -> qualified_id.
/// Handles collisions by keeping both with full qualified IDs.
pub fn load_registry() -> Result<BTreeMap<String, String>, Box<dyn std::error::Error>> {
    let path = expand_home(INSTALLED_PLUGINS);
    let content = std::fs::read_to_string(&path)?;
    let data: InstalledPlugins = serde_json::from_str(&content)?;
    let plugins = data.plugins.unwrap_or_default();
    let mut registry: BTreeMap<String, String> = BTreeMap::new();

    for qid in plugins.keys() {
        let short = qid.split('@').next().unwrap_or(qid).to_string();
        if registry.contains_key(&short) {
            if let Some(old_qid) = registry.remove(&short) {
                registry.insert(old_qid.clone(), old_qid);
            }
            registry.insert(qid.clone(), qid.clone());
        } else {
            registry.insert(short, qid.clone());
        }
    }

    Ok(registry)
}
```

`src/context/profiles.rs`:
```rust
use std::collections::BTreeMap;
use serde::Deserialize;
use crate::util::expand_home;

const PROFILES_PATH: &str = "~/.claude/templates/contexts/profiles.yaml";

#[derive(Deserialize)]
struct ProfilesYaml {
    pub base: Option<Vec<String>>,
    pub profiles: Option<BTreeMap<String, ProfileDef>>,
    pub marketplaces: Option<BTreeMap<String, MarketplaceConfig>>,
}

#[derive(Deserialize, Clone)]
pub struct ProfileDef {
    pub enable: Option<Vec<String>>,
    pub comment: Option<String>,
}

#[derive(Deserialize, Clone)]
pub struct MarketplaceConfig {
    pub github: Option<String>,
    pub local: Option<String>,
    #[serde(rename = "autoUpdate")]
    pub auto_update: Option<bool>,
}

/// Load base plugins and profile definitions from profiles.yaml.
pub fn load_profiles() -> Result<(Vec<String>, BTreeMap<String, ProfileDef>), Box<dyn std::error::Error>> {
    let path = expand_home(PROFILES_PATH);
    let content = std::fs::read_to_string(&path)?;
    let data: ProfilesYaml = serde_yaml::from_str(&content)?;
    Ok((
        data.base.unwrap_or_default(),
        data.profiles.unwrap_or_default(),
    ))
}

/// Load marketplace configurations from profiles.yaml.
pub fn load_marketplaces() -> Result<BTreeMap<String, MarketplaceConfig>, Box<dyn std::error::Error>> {
    let path = expand_home(PROFILES_PATH);
    let content = std::fs::read_to_string(&path)?;
    let data: ProfilesYaml = serde_yaml::from_str(&content)?;
    Ok(data.marketplaces.unwrap_or_default())
}
```

`src/context/builder.rs`:
```rust
use std::collections::BTreeMap;
use super::profiles::ProfileDef;

/// Build enabledPlugins map from registry + base + profiles + overrides.
///
/// Algorithm:
/// 1. All registry plugins -> false
/// 2. Enable base plugins
/// 3. For each profile: enable its plugins
/// 4. Apply enable/disable overrides
/// 5. Resolve short names to qualified IDs
pub fn build_plugins(
    registry: &BTreeMap<String, String>,
    base: &[String],
    profiles: &BTreeMap<String, ProfileDef>,
    profile_names: &[String],
    enable: &[String],
    disable: &[String],
) -> Result<BTreeMap<String, bool>, Box<dyn std::error::Error>> {
    let mut state: BTreeMap<&str, bool> =
        registry.keys().map(|k| (k.as_str(), false)).collect();

    for name in base {
        if state.contains_key(name.as_str()) {
            state.insert(name.as_str(), true);
        }
    }

    for pname in profile_names {
        let profile = profiles
            .get(pname)
            .ok_or_else(|| format!("Unknown profile: {}", pname))?;
        for plugin in profile.enable.as_deref().unwrap_or_default() {
            if !state.contains_key(plugin.as_str()) {
                eprintln!(
                    "\x1b[0;33mWarning: profile '{}' references uninstalled plugin: {} (skipped)\x1b[0m",
                    pname, plugin
                );
                continue;
            }
            state.insert(plugin.as_str(), true);
        }
    }

    for name in enable {
        if !state.contains_key(name.as_str()) {
            eprintln!(
                "\x1b[0;33mWarning: enable override references uninstalled plugin: {} (skipped)\x1b[0m",
                name
            );
            continue;
        }
        state.insert(name.as_str(), true);
    }
    for name in disable {
        if state.contains_key(name.as_str()) {
            state.insert(name.as_str(), false);
        }
    }

    let mut result = BTreeMap::new();
    for (name, enabled) in state {
        let qid = registry.get(name).unwrap_or(&name.to_string()).clone();
        result.insert(qid, enabled);
    }

    Ok(result)
}
```

`src/context/settings.rs`:
```rust
use std::collections::BTreeMap;
use std::path::Path;
use serde::Deserialize;

const CONTEXT_FILE: &str = ".claude/context.yaml";
const TARGET_FILE: &str = ".claude/settings.json";

#[derive(Deserialize)]
struct ContextYaml {
    profiles: Option<Vec<String>>,
    enable: Option<Vec<String>>,
    disable: Option<Vec<String>>,
}

/// Write enabledPlugins to .claude/settings.json, preserving other keys.
/// Sorts: enabled first (by marketplace, then name), then disabled.
/// Uses atomic write (temp file + rename).
pub fn apply_to_settings(
    enabled_plugins: &BTreeMap<String, bool>,
) -> Result<(), Box<dyn std::error::Error>> {
    let mut existing: serde_json::Value = if Path::new(TARGET_FILE).exists() {
        let content = std::fs::read_to_string(TARGET_FILE)?;
        serde_json::from_str(&content)
            .unwrap_or_else(|_| serde_json::Value::Object(serde_json::Map::new()))
    } else {
        serde_json::Value::Object(serde_json::Map::new())
    };

    let mut sorted: Vec<(&String, &bool)> = enabled_plugins.iter().collect();
    sorted.sort_by(|(a_qid, a_on), (b_qid, b_on)| {
        let a_enabled = !**a_on;
        let b_enabled = !**b_on;
        let a_parts: Vec<&str> = a_qid.splitn(2, '@').collect();
        let b_parts: Vec<&str> = b_qid.splitn(2, '@').collect();
        let a_marketplace = a_parts.get(1).unwrap_or(&"");
        let b_marketplace = b_parts.get(1).unwrap_or(&"");
        let a_name = a_parts.first().unwrap_or(&"");
        let b_name = b_parts.first().unwrap_or(&"");
        (a_enabled, *a_marketplace, *a_name).cmp(&(b_enabled, *b_marketplace, *b_name))
    });

    let mut plugins_map = serde_json::Map::new();
    for (k, v) in sorted {
        plugins_map.insert(k.clone(), serde_json::Value::Bool(*v));
    }

    existing
        .as_object_mut()
        .ok_or("settings.json is not a JSON object")?
        .insert("enabledPlugins".to_string(), plugins_map.into());

    let dir = Path::new(TARGET_FILE).parent().unwrap_or(Path::new("."));
    std::fs::create_dir_all(dir)?;
    let tmp_path = format!("{}.tmp", TARGET_FILE);
    let content = serde_json::to_string_pretty(&existing)?;
    std::fs::write(&tmp_path, format!("{}\n", content))?;
    std::fs::rename(&tmp_path, TARGET_FILE)?;

    Ok(())
}

/// Write .claude/context.yaml with profile selection.
pub fn write_context_yaml(
    profile_names: &[String],
    enable: &[String],
    disable: &[String],
) -> Result<(), Box<dyn std::error::Error>> {
    let mut lines = vec![
        "# .claude/context.yaml — committed, declares project's plugin needs".to_string(),
        format!("profiles:\n{}", profile_names.iter().map(|p| format!("  - {}", p)).collect::<Vec<_>>().join("\n")),
    ];
    if !enable.is_empty() {
        lines.push(format!("enable:\n{}", enable.iter().map(|e| format!("  - {}", e)).collect::<Vec<_>>().join("\n")));
    }
    if !disable.is_empty() {
        lines.push(format!("disable:\n{}", disable.iter().map(|d| format!("  - {}", d)).collect::<Vec<_>>().join("\n")));
    }

    let dir = Path::new(CONTEXT_FILE).parent().unwrap_or(Path::new("."));
    std::fs::create_dir_all(dir)?;
    std::fs::write(CONTEXT_FILE, lines.join("\n") + "\n")?;
    Ok(())
}

/// Load .claude/context.yaml. Returns None if it doesn't exist.
pub fn load_context_yaml() -> Result<Option<(Vec<String>, Vec<String>, Vec<String>)>, Box<dyn std::error::Error>> {
    if !Path::new(CONTEXT_FILE).exists() {
        return Ok(None);
    }
    let content = std::fs::read_to_string(CONTEXT_FILE)?;
    let ctx: ContextYaml = serde_yaml::from_str(&content)?;
    Ok(Some((
        ctx.profiles.unwrap_or_default(),
        ctx.enable.unwrap_or_default(),
        ctx.disable.unwrap_or_default(),
    )))
}

/// Apply context.yaml to settings.json. Returns true if applied.
pub fn apply_from_context_yaml() -> Result<bool, Box<dyn std::error::Error>> {
    let ctx = match load_context_yaml()? {
        Some(c) => c,
        None => return Ok(false),
    };
    let (profile_names, enable, disable) = ctx;
    if profile_names.is_empty() {
        return Ok(false);
    }

    let reg = super::registry::load_registry()?;
    let (base, profiles) = super::profiles::load_profiles()?;
    let enabled = super::builder::build_plugins(&reg, &base, &profiles, &profile_names, &enable, &disable)?;
    apply_to_settings(&enabled)?;
    Ok(true)
}

/// Remove project plugin config. Guards git-tracked files unless force=true.
pub fn reset(force: bool) -> Result<(), Box<dyn std::error::Error>> {
    if !force {
        let mut tracked = Vec::new();
        for path in [CONTEXT_FILE, TARGET_FILE] {
            if Path::new(path).exists() && is_git_tracked(path) {
                tracked.push(path);
            }
        }
        if !tracked.is_empty() {
            eprintln!("\x1b[0;31mRefusing to modify git-tracked files:\x1b[0m");
            for f in &tracked {
                eprintln!("  {}", f);
            }
            eprintln!("\nUse \x1b[1m--force\x1b[0m to override (changes will show in git diff).");
            std::process::exit(1);
        }
    }

    let mut changed = false;

    if Path::new(CONTEXT_FILE).exists() {
        std::fs::remove_file(CONTEXT_FILE)?;
        println!("\x1b[0;32mRemoved:\x1b[0m {}", CONTEXT_FILE);
        changed = true;
    }

    if Path::new(TARGET_FILE).exists() {
        let content = std::fs::read_to_string(TARGET_FILE)?;
        let mut data: serde_json::Value = serde_json::from_str(&content)
            .unwrap_or_else(|_| serde_json::Value::Object(serde_json::Map::new()));

        if let Some(obj) = data.as_object_mut() {
            if obj.remove("enabledPlugins").is_some() {
                if obj.is_empty() {
                    std::fs::remove_file(TARGET_FILE)?;
                    println!("\x1b[0;32mRemoved:\x1b[0m {} (was empty after cleanup)", TARGET_FILE);
                } else {
                    let out = serde_json::to_string_pretty(&data)?;
                    std::fs::write(TARGET_FILE, format!("{}\n", out))?;
                    println!("\x1b[0;32mRemoved enabledPlugins from:\x1b[0m {}", TARGET_FILE);
                }
                changed = true;
            }
        }
    }

    if !changed {
        println!("\x1b[0;33mNothing to reset.\x1b[0m");
    } else {
        println!("\x1b[0;33mRestart Claude Code to apply changes.\x1b[0m");
    }
    Ok(())
}

fn is_git_tracked(path: &str) -> bool {
    std::process::Command::new("git")
        .args(["ls-files", "--error-unmatch", path])
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}
```

`src/context/display.rs`:
```rust
use std::collections::BTreeMap;
use std::path::Path;
use super::{profiles, settings};

const TARGET_FILE: &str = ".claude/settings.json";
const GLOBAL_SETTINGS: &str = "~/.claude/settings.json";

/// Show current active context and available profiles (--list mode).
pub fn show_status() -> Result<(), Box<dyn std::error::Error>> {
    let settings_path = if Path::new(TARGET_FILE).exists() {
        TARGET_FILE.to_string()
    } else {
        crate::util::expand_home(GLOBAL_SETTINGS)
    };

    let plugins: BTreeMap<String, bool> = if Path::new(&settings_path).exists() {
        let content = std::fs::read_to_string(&settings_path)?;
        let data: serde_json::Value = serde_json::from_str(&content).unwrap_or_default();
        data.get("enabledPlugins")
            .and_then(|v| serde_json::from_value(v.clone()).ok())
            .unwrap_or_default()
    } else {
        BTreeMap::new()
    };

    let mut on: Vec<&str> = plugins.iter().filter(|(_, v)| **v).map(|(k, _)| k.split('@').next().unwrap_or(k.as_str())).collect();
    let mut off: Vec<&str> = plugins.iter().filter(|(_, v)| !**v).map(|(k, _)| k.split('@').next().unwrap_or(k.as_str())).collect();
    on.sort();
    off.sort();

    // Context header
    match settings::load_context_yaml()? {
        Some((pnames, enable, disable)) => {
            print!("\x1b[1mActive context:\x1b[0m \x1b[0;34m{}\x1b[0m", pnames.join(", "));
            println!();
            if !enable.is_empty() {
                println!("  + {}", enable.join(", "));
            }
            if !disable.is_empty() {
                println!("  - {}", disable.join(", "));
            }
        }
        None if Path::new(TARGET_FILE).exists() => {
            println!("\x1b[1mActive context:\x1b[0m \x1b[0;33mmanual\x1b[0m (no context.yaml)");
        }
        None => {
            println!("\x1b[1mActive context:\x1b[0m \x1b[0;33mglobal defaults\x1b[0m");
        }
    }

    println!("\n\x1b[0;32mON  ({}):\x1b[0m {}", on.len(), on.join(", "));
    if !off.is_empty() {
        println!("\x1b[0;33mOFF ({}):\x1b[0m {}", off.len(), off.join(", "));
    }

    // Available profiles
    let (_, profile_defs) = profiles::load_profiles()?;
    println!("\n\x1b[1mProfiles:\x1b[0m");
    for (name, pdata) in &profile_defs {
        let comment = pdata.comment.as_deref().unwrap_or("");
        println!("  \x1b[0;32m{:<12}\x1b[0m {}", name, comment);
    }

    Ok(())
}

/// Print summary after applying profiles.
pub fn print_apply_summary(profile_names: &[String], enabled: &BTreeMap<String, bool>) {
    let mut on: Vec<&str> = enabled.iter().filter(|(_, v)| **v).map(|(k, _)| k.split('@').next().unwrap_or(k.as_str())).collect();
    on.sort();
    println!("\x1b[0;32mApplied:\x1b[0m {}", profile_names.join(", "));
    println!("\x1b[0;32mEnabled:\x1b[0m {}", on.join(", "));
    println!("  -> .claude/settings.json");
    println!("  -> .claude/context.yaml");
    println!("\x1b[0;33mRestart Claude Code to apply changes.\x1b[0m");
}

/// Print summary after applying from context.yaml.
pub fn print_context_yaml_summary() -> Result<(), Box<dyn std::error::Error>> {
    if let Some((pnames, _, _)) = settings::load_context_yaml()? {
        println!("\x1b[0;32mApplied from context.yaml:\x1b[0m profiles={:?}", pnames);
    }
    println!("  -> .claude/settings.json");
    println!("\x1b[0;33mRestart Claude Code to apply changes.\x1b[0m");
    Ok(())
}
```

`src/context/sync.rs`:
```rust
use std::collections::BTreeMap;
use std::path::Path;
use std::process::Command;
use super::profiles::MarketplaceConfig;
use crate::util::expand_home;

const KNOWN_MARKETPLACES: &str = "~/.claude/plugins/known_marketplaces.json";
const MARKETPLACES_DIR: &str = "~/.claude/plugins/marketplaces";
const INSTALLED_PLUGINS: &str = "~/.claude/plugins/installed_plugins.json";

/// Main sync entry point.
pub fn run(verbose: bool) -> Result<(), Box<dyn std::error::Error>> {
    // Check claude CLI exists
    if which("claude").is_none() {
        println!("\x1b[0;33mClaude CLI not found — skipping marketplace sync.\x1b[0m");
        return Ok(());
    }

    let marketplaces = super::profiles::load_marketplaces()?;
    if marketplaces.is_empty() {
        println!("\x1b[0;33mNo marketplaces defined in profiles.yaml\x1b[0m");
        return Ok(());
    }

    // Get currently registered marketplaces
    let registered = get_registered_marketplaces();

    // Phase 1: Register new marketplaces (sequential)
    let mut to_update = Vec::new();
    let mut errors = 0;
    for (name, config) in &marketplaces {
        let source = resolve_source(name, config);
        let Some(source) = source else {
            eprintln!("\x1b[0;31m  {}: no valid source configured\x1b[0m", name);
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
                    eprintln!("\x1b[0;31m  {}: registration failed — {}\x1b[0m", name, err.trim());
                    errors += 1;
                    continue;
                }
                Err(e) => {
                    eprintln!("\x1b[0;31m  {}: registration failed — {}\x1b[0m", name, e);
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
                println!("  \x1b[0;32m✔\x1b[0m {}", name);
            }
        } else {
            println!("\x1b[0;33m  {}: {}\x1b[0m", name, msg);
        }
    }

    let total = marketplaces.len();
    if errors > 0 {
        println!("\x1b[0;33mSynced {}/{} marketplaces ({} error(s))\x1b[0m", synced, total, errors);
    } else {
        println!("\x1b[0;32mSynced {}/{} marketplaces\x1b[0m", synced, total);
    }

    // Post-sync steps
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
    // CLAUDE_CONTEXT_LOCAL=1 prefers local paths
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

fn expand_env(s: &str) -> String {
    let expanded = regex_lite::Regex::new(r"\$\{(\w+)\}")
        .unwrap()
        .replace_all(s, |caps: &regex_lite::Captures| {
            let key = &caps[1];
            std::env::var(key).unwrap_or_else(|_| {
                match key {
                    "CODE_DIR" => expand_home("~/code"),
                    _ => caps[0].to_string(),
                }
            })
        });
    expand_home(&expanded)
}

/// chmod +x all .sh files under marketplaces dir.
fn fix_hook_permissions(verbose: bool) {
    let dir = expand_home(MARKETPLACES_DIR);
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
                    let _ = std::fs::set_permissions(&entry, std::fs::Permissions::from_mode(mode | 0o755));
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
        println!("\x1b[0;32mFixed {} hook script(s) missing execute permission\x1b[0m", fixed);
    }
}

/// Set autoUpdate in known_marketplaces.json from profiles.yaml config.
fn apply_auto_update(
    marketplaces: &BTreeMap<String, MarketplaceConfig>,
    verbose: bool,
) -> Result<(), Box<dyn std::error::Error>> {
    let path = expand_home(KNOWN_MARKETPLACES);
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
        let tmp = format!("{}.tmp", path);
        let out = serde_json::to_string_pretty(&data)?;
        std::fs::write(&tmp, format!("{}\n", out))?;
        std::fs::rename(&tmp, &path)?;
        if verbose {
            println!("  autoUpdate set for: {}", changed.join(", "));
        }
    }
    Ok(())
}

/// Replace "local" scope with "project" in installed_plugins.json.
fn normalize_scopes(verbose: bool) -> Result<(), Box<dyn std::error::Error>> {
    let path = expand_home(INSTALLED_PLUGINS);
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
                        changed.push(qid.split('@').next().unwrap_or(qid).to_string());
                    }
                }
            }
        }
    }

    if !changed.is_empty() {
        let tmp = format!("{}.tmp", path);
        let out = serde_json::to_string_pretty(&data)?;
        std::fs::write(&tmp, format!("{}\n", out))?;
        std::fs::rename(&tmp, &path)?;
        println!("\x1b[0;32mNormalized {} plugin scope(s): local → project\x1b[0m", changed.len());
        if verbose {
            for name in &changed {
                println!("  {}", name);
            }
        }
    }
    Ok(())
}

/// Simple recursive directory walker returning file paths.
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
```

`src/context/tui/mod.rs`:
```rust
pub mod state;
pub mod theme;

// TUI implementation goes in Task 2
pub fn run() -> Result<(), Box<dyn std::error::Error>> {
    todo!("TUI implementation in Task 2")
}
```

`src/context/tui/state.rs`:
```rust
// TUI state — implemented in Task 2
```

`src/context/tui/theme.rs`:
```rust
// TUI theme — implemented in Task 2
```

- [ ] **Step 4: Wire into main.rs**

Update `src/main.rs`:

```rust
mod check_git_root;
mod context;
mod context_apply;
mod resolve_file_path;
mod statusline;
mod usage;
mod util;

fn main() {
    let args: Vec<String> = std::env::args().collect();

    if args.len() < 2 {
        eprintln!("Usage: claude-tools <subcommand>");
        eprintln!("Subcommands: statusline, context, check-git-root, context-apply, resolve-file-path");
        std::process::exit(1);
    }

    let result = match args[1].as_str() {
        "statusline" => statusline::run(),
        "context" => {
            // Pass "claude-tools context" as argv[0] for clap, then remaining args
            let mut ctx_args = vec!["claude-tools-context".to_string()];
            ctx_args.extend_from_slice(&args[2..]);
            context::run(ctx_args)
        }
        "context-apply" => context_apply::run(), // Keep alias until Phase 6
        "check-git-root" => check_git_root::run(),
        "resolve-file-path" => resolve_file_path::run(),
        _ => {
            eprintln!("Unknown subcommand: {}", args[1]);
            std::process::exit(1);
        }
    };

    if let Err(e) = result {
        eprintln!("Error: {}", e);
        std::process::exit(1);
    }
}
```

- [ ] **Step 5: Verify it compiles**

Run: `cd tools/claude-tools && cargo build --release 2>&1 | tail -5`

Expected: successful build (TUI will panic at runtime if called, but all other paths work)

- [ ] **Step 6: Test non-interactive modes**

Run from a project with `.claude/context.yaml`:

```bash
# Apply
./target/release/claude-tools context --apply

# List
./target/release/claude-tools context --list

# Apply profiles
./target/release/claude-tools context code python

# Clean (dry run — don't actually delete in a real project)
./target/release/claude-tools context --clean
```

Compare output against `claude-context` (Python) for parity.

- [ ] **Step 7: Commit**

```bash
git add tools/claude-tools/
git commit -m "feat(claude-tools): add context subcommand with core logic, display, sync, settings"
```

---

### Task 2: Build the TUI

**Files:**
- Modify: `tools/claude-tools/src/context/tui/mod.rs`
- Modify: `tools/claude-tools/src/context/tui/state.rs`
- Modify: `tools/claude-tools/src/context/tui/theme.rs`

- [ ] **Step 1: Implement TUI theme**

`src/context/tui/theme.rs`:
```rust
use ratatui::style::{Color, Modifier, Style};

pub const TITLE: &str = " claude-context ";

// Colors
pub const GREEN: Color = Color::Green;
pub const YELLOW: Color = Color::Yellow;
pub const BLUE: Color = Color::Blue;
pub const GRAY: Color = Color::DarkGray;
pub const WHITE: Color = Color::White;

// Styles
pub fn selected() -> Style {
    Style::default().fg(GREEN).add_modifier(Modifier::BOLD)
}

pub fn unselected() -> Style {
    Style::default().fg(WHITE)
}

pub fn cursor() -> Style {
    Style::default().fg(BLUE).add_modifier(Modifier::BOLD)
}

pub fn header() -> Style {
    Style::default().fg(WHITE).add_modifier(Modifier::BOLD)
}

pub fn hint() -> Style {
    Style::default().fg(GRAY)
}

pub fn modified_indicator() -> Style {
    Style::default().fg(YELLOW)
}

pub fn tree_branch() -> Style {
    Style::default().fg(GRAY)
}

// Symbols
pub const FILLED: &str = "●";
pub const EMPTY: &str = "○";
pub const BRANCH: &str = "├";
pub const BRANCH_LAST: &str = "└";
```

- [ ] **Step 2: Implement TUI state**

`src/context/tui/state.rs`:
```rust
use std::collections::BTreeMap;
use crate::context::profiles::ProfileDef;

pub struct Profile {
    pub name: String,
    pub comment: String,
    pub plugins: Vec<String>,
    pub enabled: bool,
}

pub struct AppState {
    pub profiles: Vec<Profile>,
    pub cursor: usize,
    pub original_selection: Vec<bool>,
    pub quit: bool,
    pub apply: bool,
}

impl AppState {
    pub fn new(
        profile_defs: &BTreeMap<String, ProfileDef>,
        active_profiles: &[String],
    ) -> Self {
        let profiles: Vec<Profile> = profile_defs
            .iter()
            .map(|(name, def)| Profile {
                name: name.clone(),
                comment: def.comment.clone().unwrap_or_default(),
                plugins: def.enable.clone().unwrap_or_default(),
                enabled: active_profiles.contains(name),
            })
            .collect();

        let original_selection: Vec<bool> = profiles.iter().map(|p| p.enabled).collect();

        Self {
            profiles,
            cursor: 0,
            original_selection,
            quit: false,
            apply: false,
        }
    }

    pub fn is_modified(&self) -> bool {
        self.profiles.iter().enumerate().any(|(i, p)| p.enabled != self.original_selection[i])
    }

    pub fn selected_profile_names(&self) -> Vec<String> {
        self.profiles.iter().filter(|p| p.enabled).map(|p| p.name.clone()).collect()
    }

    pub fn toggle_current(&mut self) {
        if let Some(p) = self.profiles.get_mut(self.cursor) {
            p.enabled = !p.enabled;
        }
    }

    pub fn move_up(&mut self) {
        if self.cursor > 0 {
            self.cursor -= 1;
        }
    }

    pub fn move_down(&mut self) {
        if self.cursor + 1 < self.profiles.len() {
            self.cursor += 1;
        }
    }

    pub fn select_all(&mut self) {
        for p in &mut self.profiles {
            p.enabled = true;
        }
    }

    pub fn select_none(&mut self) {
        for p in &mut self.profiles {
            p.enabled = false;
        }
    }
}
```

- [ ] **Step 3: Implement TUI app (init, update, view)**

`src/context/tui/mod.rs`:
```rust
pub mod state;
pub mod theme;

use crossterm::event::{self, Event, KeyCode, KeyEventKind};
use crossterm::terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen};
use crossterm::ExecutableCommand;
use ratatui::prelude::*;
use ratatui::widgets::{Block, Borders, Paragraph};

use state::AppState;
use crate::context::{profiles, registry, builder, settings};

pub fn run() -> Result<(), Box<dyn std::error::Error>> {
    // Load data
    let reg = registry::load_registry()?;
    let (base, profile_defs) = profiles::load_profiles()?;
    let active = settings::load_context_yaml()?
        .map(|(p, _, _)| p)
        .unwrap_or_default();

    let mut state = AppState::new(&profile_defs, &active);

    // Setup terminal
    enable_raw_mode()?;
    std::io::stdout().execute(EnterAlternateScreen)?;
    let backend = CrosstermBackend::new(std::io::stdout());
    let mut terminal = Terminal::new(backend)?;

    // Main loop
    loop {
        terminal.draw(|frame| view(frame, &state))?;

        if let Event::Key(key) = event::read()? {
            if key.kind != KeyEventKind::Press {
                continue;
            }
            match key.code {
                KeyCode::Char('q') | KeyCode::Esc => {
                    state.quit = true;
                    break;
                }
                KeyCode::Enter => {
                    state.apply = true;
                    break;
                }
                KeyCode::Up | KeyCode::Char('k') => state.move_up(),
                KeyCode::Down | KeyCode::Char('j') => state.move_down(),
                KeyCode::Char(' ') => state.toggle_current(),
                KeyCode::Char('a') => state.select_all(),
                KeyCode::Char('n') => state.select_none(),
                _ => {}
            }
        }
    }

    // Restore terminal
    disable_raw_mode()?;
    std::io::stdout().execute(LeaveAlternateScreen)?;

    // Apply if user pressed enter
    if state.apply && state.is_modified() {
        let selected = state.selected_profile_names();
        let enabled = builder::build_plugins(&reg, &base, &profile_defs, &selected, &[], &[])?;
        settings::apply_to_settings(&enabled)?;
        settings::write_context_yaml(&selected, &[], &[])?;

        // Print summary to restored terminal
        let mut on: Vec<&str> = enabled.iter()
            .filter(|(_, v)| **v)
            .map(|(k, _)| k.split('@').next().unwrap_or(k.as_str()))
            .collect();
        on.sort();
        println!("\x1b[0;32mApplied:\x1b[0m {}", selected.join(", "));
        println!("\x1b[0;32mEnabled:\x1b[0m {}", on.join(", "));
        println!("\x1b[0;33mRestart Claude Code to apply changes.\x1b[0m");
    } else if state.apply {
        println!("No changes.");
    }

    Ok(())
}

fn view(frame: &mut Frame, state: &AppState) {
    let area = frame.area();

    // Build content lines
    let mut lines: Vec<Line> = Vec::new();

    // Header: Active profiles
    let active: Vec<&str> = state.profiles.iter()
        .filter(|p| p.enabled)
        .map(|p| p.name.as_str())
        .collect();
    let header_text = if active.is_empty() {
        "(none)".to_string()
    } else {
        active.join(", ")
    };
    let mut header_line = vec![
        Span::styled("  Active: ", theme::header()),
        Span::styled(&header_text, Style::default().fg(theme::BLUE)),
    ];
    if state.is_modified() {
        header_line.push(Span::styled("  [modified]", theme::modified_indicator()));
    }
    lines.push(Line::from(header_line));
    lines.push(Line::from(""));

    // Profile list
    for (i, profile) in state.profiles.iter().enumerate() {
        let is_cursor = i == state.cursor;
        let symbol = if profile.enabled { theme::FILLED } else { theme::EMPTY };

        let name_style = if is_cursor {
            theme::cursor()
        } else if profile.enabled {
            theme::selected()
        } else {
            theme::unselected()
        };

        lines.push(Line::from(vec![
            Span::raw("  "),
            Span::styled(symbol, name_style),
            Span::raw(" "),
            Span::styled(format!("{:<12}", profile.name), name_style),
            Span::styled(&profile.comment, theme::hint()),
        ]));

        // Expand plugins for highlighted profile
        if is_cursor && !profile.plugins.is_empty() {
            for (j, plugin) in profile.plugins.iter().enumerate() {
                let branch = if j == profile.plugins.len() - 1 {
                    theme::BRANCH_LAST
                } else {
                    theme::BRANCH
                };
                lines.push(Line::from(vec![
                    Span::raw("    "),
                    Span::styled(branch, theme::tree_branch()),
                    Span::styled(format!(" {}", plugin), theme::tree_branch()),
                ]));
            }
        }
    }

    // Footer
    lines.push(Line::from(""));
    lines.push(Line::from(vec![
        Span::styled("  space", theme::hint()),
        Span::raw(": toggle  "),
        Span::styled("enter", theme::hint()),
        Span::raw(": apply  "),
        Span::styled("q", theme::hint()),
        Span::raw(": quit"),
    ]));

    let block = Block::default()
        .title(theme::TITLE)
        .borders(Borders::ALL)
        .border_style(Style::default().fg(theme::GRAY));

    let paragraph = Paragraph::new(lines).block(block);
    frame.render_widget(paragraph, area);
}
```

- [ ] **Step 4: Verify TUI compiles and runs**

```bash
cd tools/claude-tools && cargo build --release 2>&1 | tail -5
# Then test interactively:
./target/release/claude-tools context --tui
```

Expected: TUI renders with profile list, arrow keys navigate, space toggles, enter applies, q quits.

- [ ] **Step 5: Commit**

```bash
git add tools/claude-tools/src/context/tui/
git commit -m "feat(claude-tools): add interactive TUI for profile selection"
```

---

### Task 3: Handle `sync.rs` dependency on `regex_lite`

**Files:**
- Modify: `tools/claude-tools/Cargo.toml`

The `expand_env` function in `sync.rs` uses `regex_lite` for `${VAR}` expansion. This is a lightweight regex crate (no Unicode tables, ~100KB).

- [ ] **Step 1: Add regex_lite dependency**

Add to `Cargo.toml`:
```toml
regex-lite = "0.1"
```

Alternatively, replace the regex with a simple manual parser to avoid the dep:

```rust
/// Expand ${VAR} in a string using env vars, with fallback defaults.
fn expand_env(s: &str) -> String {
    let mut result = String::new();
    let mut chars = s.chars().peekable();
    while let Some(c) = chars.next() {
        if c == '$' && chars.peek() == Some(&'{') {
            chars.next(); // consume '{'
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
```

If using the manual parser, remove the `regex_lite` import from `sync.rs` and skip adding the crate.

- [ ] **Step 2: Verify build**

```bash
cd tools/claude-tools && cargo build --release 2>&1 | tail -3
```

- [ ] **Step 3: Commit**

```bash
git add tools/claude-tools/
git commit -m "fix(claude-tools): handle env var expansion in marketplace source paths"
```

---

### Task 4: Update call sites and delete Python script

**Files:**
- Modify: `claude/hooks/context_auto_apply.sh`
- Modify: `deploy.sh`
- Delete: `custom_bins/claude-context`

- [ ] **Step 1: Update `claude/hooks/context_auto_apply.sh`**

Replace the full file content:

```bash
#!/usr/bin/env bash
# SessionStart hook: auto-apply context.yaml, warn if no context configured.
# Also triggers background marketplace sync if stale (>6h since last sync).
CONTEXT_FILE=".claude/context.yaml"
if [ -f "$CONTEXT_FILE" ]; then
    claude-tools context --apply 2>/dev/null
else
    # Warn if inside a git repo without context profiles
    if git rev-parse --is-inside-work-tree &>/dev/null; then
        echo -e "\033[0;33mNo context profiles configured for this project.\033[0m"
        echo -e "Run: claude-tools context <profile>  (e.g., claude-tools context code python)"
        echo -e "List profiles: claude-tools context --list"
    fi
fi

# Background marketplace sync (throttled: skip if synced within 6 hours)
SYNC_STAMP="$HOME/.claude/plugins/.last_sync"
SYNC_INTERVAL=$((6 * 3600))  # 6 hours in seconds

should_sync=false
if [ ! -f "$SYNC_STAMP" ]; then
    should_sync=true
elif command -v stat &>/dev/null; then
    if [[ "$OSTYPE" == darwin* ]]; then
        last_sync=$(stat -f %m "$SYNC_STAMP" 2>/dev/null || echo 0)
    else
        last_sync=$(stat -c %Y "$SYNC_STAMP" 2>/dev/null || echo 0)
    fi
    now=$(date +%s)
    if (( now - last_sync > SYNC_INTERVAL )); then
        should_sync=true
    fi
fi

if $should_sync && command -v claude-tools &>/dev/null; then
    # Run sync in background, then clean plugin symlinks (anthropics/claude-code#14549)
    CLEAN_SCRIPT="${DOT_DIR:-$HOME/code/dotfiles}/scripts/cleanup/clean_plugin_symlinks.sh"
    (claude-tools context --sync &>/dev/null && touch "$SYNC_STAMP"; bash "$CLEAN_SCRIPT" &>/dev/null) &
    disown 2>/dev/null
fi

# Always clean stale plugin symlinks (sync recreates them, but they also appear from other operations)
CLEAN_SCRIPT="${DOT_DIR:-$HOME/code/dotfiles}/scripts/cleanup/clean_plugin_symlinks.sh"
if [ -f "$CLEAN_SCRIPT" ]; then
    bash "$CLEAN_SCRIPT" &>/dev/null &
    disown 2>/dev/null
fi

exit 0  # Don't block session start
```

- [ ] **Step 2: Update `deploy.sh`**

Find the marketplace sync section (around line 644) and replace:

```bash
        # Sync plugin marketplaces (declarative, from profiles.yaml)
        if command -v claude-tools &>/dev/null; then
            log_info "Syncing plugin marketplaces..."
            claude-tools context --sync -v || \
                log_warning "Marketplace sync had issues — run manually: claude-tools context --sync"
        else
            log_warning "claude-tools not found — skipping marketplace sync"
        fi
```

- [ ] **Step 3: Delete Python script**

```bash
trash custom_bins/claude-context
```

- [ ] **Step 4: Copy compiled binary to custom_bins**

```bash
cp tools/claude-tools/target/release/claude-tools custom_bins/
```

- [ ] **Step 5: Verify hook works**

```bash
cd /Users/yulong/code/dotfiles && bash claude/hooks/context_auto_apply.sh
```

Expected: applies context.yaml or shows "no context profiles" warning, no errors.

- [ ] **Step 6: Commit**

```bash
git add claude/hooks/context_auto_apply.sh deploy.sh custom_bins/
git commit -m "feat: migrate call sites from Python claude-context to claude-tools context"
```

---

### Task 5: Delete old context_apply.rs and update statusline

**Files:**
- Delete: `tools/claude-tools/src/context_apply.rs`
- Modify: `tools/claude-tools/src/main.rs`
- Modify: `tools/claude-tools/src/statusline.rs` (if it uses `expand_home` locally)

- [ ] **Step 1: Check if statusline.rs has its own expand_home**

```bash
grep -n "expand_home\|fn expand" tools/claude-tools/src/statusline.rs
```

If it does, replace with `use crate::util::expand_home;`.

- [ ] **Step 2: Remove context_apply.rs and update main.rs**

Delete `src/context_apply.rs`.

Update `main.rs` to remove the `mod context_apply;` line and the `"context-apply"` match arm:

```rust
mod check_git_root;
mod context;
mod resolve_file_path;
mod statusline;
mod usage;
mod util;

fn main() {
    let args: Vec<String> = std::env::args().collect();

    if args.len() < 2 {
        eprintln!("Usage: claude-tools <subcommand>");
        eprintln!("Subcommands: statusline, context, check-git-root, resolve-file-path");
        std::process::exit(1);
    }

    let result = match args[1].as_str() {
        "statusline" => statusline::run(),
        "context" | "context-apply" => {
            let mut ctx_args = vec!["claude-tools-context".to_string()];
            ctx_args.extend_from_slice(&args[2..]);
            context::run(ctx_args)
        }
        "check-git-root" => check_git_root::run(),
        "resolve-file-path" => resolve_file_path::run(),
        _ => {
            eprintln!("Unknown subcommand: {}", args[1]);
            std::process::exit(1);
        }
    };

    if let Err(e) = result {
        eprintln!("Error: {}", e);
        std::process::exit(1);
    }
}
```

Note: `"context-apply"` routes to the new `context::run()` with `--apply` semantics. The old `context_apply::run()` always applied from context.yaml, which matches `context::run(["claude-tools-context"])` with no args and no TTY (hook context).

- [ ] **Step 3: Verify build**

```bash
cd tools/claude-tools && cargo build --release 2>&1 | tail -3
```

- [ ] **Step 4: Re-copy binary**

```bash
cp tools/claude-tools/target/release/claude-tools custom_bins/
```

- [ ] **Step 5: Full integration test**

```bash
# From a project dir with .claude/context.yaml
claude-tools context --apply
claude-tools context --list
claude-tools context code python
claude-tools context --clean --force
# Restore
claude-tools context code python
```

- [ ] **Step 6: Commit**

```bash
cd /Users/yulong/code/dotfiles
git add tools/claude-tools/ custom_bins/claude-tools
git commit -m "refactor(claude-tools): remove context_apply.rs, unify under context subcommand"
```

---

### Task 6: Update documentation

**Files:**
- Modify: `CLAUDE.md`
- Modify: `README.md`

- [ ] **Step 1: Update CLAUDE.md**

Find all references to `claude-context` and replace with `claude-tools context`. Key sections:
- Architecture / Custom bins section: remove `claude-context` entry, note it's now `claude-tools context`
- Plugin Organization & Context Profiles: update command examples

- [ ] **Step 2: Update README.md**

Same replacements. Search for `claude-context` and update to `claude-tools context`.

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md README.md
git commit -m "docs: update claude-context references to claude-tools context"
```

---

### Task 7: Verify success criteria

- [ ] **Step 1: Startup time (non-interactive)**

```bash
time claude-tools context --apply
```

Expected: real < 0.01s (10ms)

- [ ] **Step 2: Startup time (TUI)**

```bash
time claude-tools context --tui <<< 'q'
```

Expected: real < 0.05s (50ms)

- [ ] **Step 3: All CLI flags parity check**

```bash
claude-tools context --list          # Shows status + profiles
claude-tools context code            # Applies profile
claude-tools context code python     # Applies multiple profiles
claude-tools context --clean --force # Removes config
claude-tools context --sync -v       # Syncs marketplaces
claude-tools context --apply         # Hook-style apply
claude-tools context --help          # Help text
```

- [ ] **Step 4: TUI interactive test**

```bash
claude-tools context
```

Verify:
- Profiles listed with ●/○ indicators
- Arrow keys + j/k navigate
- Space toggles profiles
- Highlighted profile expands to show plugin tree
- "Active:" header updates live
- `[modified]` shows when selection differs
- Enter applies and exits
- q/esc exits without changes

- [ ] **Step 5: Binary size check**

```bash
ls -lh custom_bins/claude-tools
```

Note the size for the record. Compare against pre-TUI binary if available.
