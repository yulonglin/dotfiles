use std::collections::BTreeMap;
use std::path::Path;
use crate::util::{self, expand_home, plugin_short_name};
use super::{profiles, settings};

/// Show current active context and available profiles (--list mode).
pub fn show_status() -> Result<(), Box<dyn std::error::Error>> {
    let target = super::TARGET_FILE;
    let settings_path = if Path::new(target).exists() {
        target.to_string()
    } else {
        expand_home(super::GLOBAL_SETTINGS)
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

    let mut on: Vec<&str> = plugins.iter().filter(|(_, v)| **v).map(|(k, _)| plugin_short_name(k)).collect();
    let mut off: Vec<&str> = plugins.iter().filter(|(_, v)| !**v).map(|(k, _)| plugin_short_name(k)).collect();
    on.sort();
    off.sort();

    match settings::load_context_yaml()? {
        Some((pnames, enable, disable)) => {
            println!("{}Active context:{} {}{}{}", util::BOLD, util::RESET, util::BLUE, pnames.join(", "), util::RESET);
            if !enable.is_empty() {
                println!("  + {}", enable.join(", "));
            }
            if !disable.is_empty() {
                println!("  - {}", disable.join(", "));
            }
        }
        None if Path::new(target).exists() => {
            println!("{}Active context:{} {}manual{} (no context.yaml)", util::BOLD, util::RESET, util::YELLOW, util::RESET);
        }
        None => {
            println!("{}Active context:{} {}global defaults{}", util::BOLD, util::RESET, util::YELLOW, util::RESET);
        }
    }

    println!("\n{}ON  ({}):{} {}", util::GREEN, on.len(), util::RESET, on.join(", "));
    if !off.is_empty() {
        println!("{}OFF ({}):{} {}", util::YELLOW, off.len(), util::RESET, off.join(", "));
    }

    let (_, profile_defs) = profiles::load_profiles()?;
    println!("\n{}Profiles:{}", util::BOLD, util::RESET);
    for (name, pdata) in &profile_defs {
        let comment = pdata.comment.as_deref().unwrap_or("");
        println!("  {}{:<12}{} {}", util::GREEN, name, util::RESET, comment);
    }

    Ok(())
}

/// Print summary after applying profiles.
pub fn print_apply_summary(profile_names: &[String], enabled: &BTreeMap<String, bool>) {
    let mut on: Vec<&str> = enabled.iter().filter(|(_, v)| **v).map(|(k, _)| plugin_short_name(k)).collect();
    on.sort();
    println!("{}Applied:{} {}", util::GREEN, util::RESET, profile_names.join(", "));
    println!("{}Enabled:{} {}", util::GREEN, util::RESET, on.join(", "));
    println!("  -> .claude/settings.json");
    println!("  -> .claude/context.yaml");
    println!("{}Restart Claude Code to apply changes.{}", util::YELLOW, util::RESET);
}

/// Print summary after applying from context.yaml (used by --apply hot path).
pub fn print_applied_context(profile_names: &[String], enabled: &BTreeMap<String, bool>) {
    let mut on: Vec<&str> = enabled.iter().filter(|(_, v)| **v).map(|(k, _)| plugin_short_name(k)).collect();
    on.sort();
    println!("{}Applied from context.yaml:{} profiles={:?}", util::GREEN, util::RESET, profile_names);
    println!("{}Enabled:{} {}", util::GREEN, util::RESET, on.join(", "));
    println!("  -> .claude/settings.json");
    println!("{}Restart Claude Code to apply changes.{}", util::YELLOW, util::RESET);
}
