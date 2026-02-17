use serde::Deserialize;
use std::collections::BTreeMap;

// --- YAML/JSON structures ---

#[derive(Deserialize)]
struct ContextYaml {
    profiles: Option<Vec<String>>,
    enable: Option<Vec<String>>,
    disable: Option<Vec<String>>,
}

#[derive(Deserialize)]
struct InstalledPlugins {
    plugins: Option<BTreeMap<String, serde_json::Value>>,
}

#[derive(Deserialize)]
struct ProfilesYaml {
    base: Option<Vec<String>>,
    profiles: Option<BTreeMap<String, ProfileDef>>,
}

#[derive(Deserialize)]
struct ProfileDef {
    enable: Option<Vec<String>>,
    #[allow(dead_code)]
    comment: Option<String>,
}

// --- Constants ---

const CONTEXT_FILE: &str = ".claude/context.yaml";
const TARGET_FILE: &str = ".claude/settings.json";

// --- Main entry point ---

/// Apply context.yaml to settings.json. Errors are swallowed to never
/// block session start (matches original hook behavior: stderr→/dev/null, exit 0).
pub fn run() -> Result<(), Box<dyn std::error::Error>> {
    if let Err(_e) = run_inner() {
        // Silent failure — don't block session start.
        // Uncomment for debugging:
        // eprintln!("context-apply: {}", _e);
    }
    Ok(())
}

fn run_inner() -> Result<(), Box<dyn std::error::Error>> {
    // Check if context.yaml exists
    if !std::path::Path::new(CONTEXT_FILE).exists() {
        return Ok(());
    }

    // Parse context.yaml
    let ctx_content = std::fs::read_to_string(CONTEXT_FILE)?;
    let ctx: ContextYaml = serde_yaml::from_str(&ctx_content)?;

    let profile_names = ctx.profiles.unwrap_or_default();
    if profile_names.is_empty() {
        return Ok(());
    }

    let enable = ctx.enable.unwrap_or_default();
    let disable = ctx.disable.unwrap_or_default();

    // Load plugin registry from installed_plugins.json
    let installed_path = expand_home("~/.claude/plugins/installed_plugins.json");
    let registry = load_registry(&installed_path)?;

    // Load profile definitions
    let profiles_path = expand_home("~/.claude/templates/contexts/profiles.yaml");
    let profiles_content = std::fs::read_to_string(&profiles_path)?;
    let profiles_yaml: ProfilesYaml = serde_yaml::from_str(&profiles_content)?;
    let base = profiles_yaml.base.unwrap_or_default();
    let profiles = profiles_yaml.profiles.unwrap_or_default();

    // Build enabled plugins map
    let enabled = build_plugins(&registry, &base, &profiles, &profile_names, &enable, &disable)?;

    // Atomic write to settings.json
    apply_to_settings(TARGET_FILE, &enabled)?;

    // Print summary
    let mut on: Vec<&str> = enabled
        .iter()
        .filter(|(_, v)| **v)
        .map(|(k, _)| k.split('@').next().unwrap_or(k.as_str()))
        .collect();
    on.sort();

    println!(
        "\x1b[0;32mApplied from context.yaml:\x1b[0m profiles={:?}",
        profile_names
    );
    println!("\x1b[0;32mEnabled:\x1b[0m {}", on.join(", "));
    println!("  -> {}", TARGET_FILE);
    println!("\x1b[0;33mRestart Claude Code to apply changes.\x1b[0m");

    Ok(())
}

// --- Helpers ---

fn expand_home(path: &str) -> String {
    if let Some(rest) = path.strip_prefix("~/") {
        if let Ok(home) = std::env::var("HOME") {
            return format!("{}/{}", home, rest);
        }
    }
    path.to_string()
}

/// Build registry mapping short_name -> qualified_id.
/// Handles collisions by keeping both with full qualified IDs (matches Python version).
fn load_registry(path: &str) -> Result<BTreeMap<String, String>, Box<dyn std::error::Error>> {
    let content = std::fs::read_to_string(path)?;
    let data: InstalledPlugins = serde_json::from_str(&content)?;

    let plugins = data.plugins.unwrap_or_default();
    let mut registry: BTreeMap<String, String> = BTreeMap::new();

    for qid in plugins.keys() {
        let short = qid.split('@').next().unwrap_or(qid).to_string();
        if registry.contains_key(&short) {
            // Collision: promote both to full qualified IDs
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

/// Build enabledPlugins dict from base + profiles + overrides.
/// Algorithm matches the Python claude-context exactly:
/// 1. All registry plugins -> false
/// 2. Enable base plugins
/// 3. For each profile: enable its plugins
/// 4. Apply enable/disable overrides
/// 5. Resolve short names to qualified IDs
fn build_plugins(
    registry: &BTreeMap<String, String>,
    base: &[String],
    profiles: &BTreeMap<String, ProfileDef>,
    profile_names: &[String],
    enable: &[String],
    disable: &[String],
) -> Result<BTreeMap<String, bool>, Box<dyn std::error::Error>> {
    // Step 1: all false
    let mut state: BTreeMap<&str, bool> =
        registry.keys().map(|k| (k.as_str(), false)).collect();

    // Step 2: base
    for name in base {
        if state.contains_key(name.as_str()) {
            state.insert(name.as_str(), true);
        }
    }

    // Step 3: profiles
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

    // Step 4: overrides
    for name in enable {
        if !state.contains_key(name.as_str()) {
            eprintln!(
                "\x1b[0;33mWarning: enable references uninstalled plugin: {} (skipped)\x1b[0m",
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

    // Step 5: resolve to qualified IDs
    let mut result = BTreeMap::new();
    for (name, enabled) in state {
        let qid = registry.get(name).unwrap_or(&name.to_string()).clone();
        result.insert(qid, enabled);
    }

    Ok(result)
}

/// Write enabledPlugins to settings.json, preserving other keys.
/// Uses atomic write (write tmp + rename).
fn apply_to_settings(
    path: &str,
    enabled_plugins: &BTreeMap<String, bool>,
) -> Result<(), Box<dyn std::error::Error>> {
    let mut existing: serde_json::Value = if std::path::Path::new(path).exists() {
        let content = std::fs::read_to_string(path)?;
        serde_json::from_str(&content)
            .unwrap_or_else(|_| serde_json::Value::Object(serde_json::Map::new()))
    } else {
        serde_json::Value::Object(serde_json::Map::new())
    };

    // Build enabledPlugins JSON object
    let plugins_value: serde_json::Value = enabled_plugins
        .iter()
        .map(|(k, v)| (k.clone(), serde_json::Value::Bool(*v)))
        .collect::<serde_json::Map<String, serde_json::Value>>()
        .into();

    existing
        .as_object_mut()
        .ok_or("settings.json is not a JSON object")?
        .insert("enabledPlugins".to_string(), plugins_value);

    // Atomic write
    let dir = std::path::Path::new(path)
        .parent()
        .unwrap_or(std::path::Path::new("."));
    std::fs::create_dir_all(dir)?;

    let tmp_path = format!("{}.tmp", path);
    let content = serde_json::to_string_pretty(&existing)?;
    std::fs::write(&tmp_path, format!("{}\n", content))?;
    std::fs::rename(&tmp_path, path)?;

    Ok(())
}
