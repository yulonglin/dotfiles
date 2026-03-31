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
    if profile_names.is_empty() {
        return Err("cannot write context.yaml with empty profiles".into());
    }
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
            let files = tracked.iter().map(|f| format!("  {}", f)).collect::<Vec<_>>().join("\n");
            return Err(format!(
                "Refusing to modify git-tracked files:\n{}\n\nUse --force to override (changes will show in git diff).",
                files
            ).into());
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
