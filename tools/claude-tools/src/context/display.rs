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
