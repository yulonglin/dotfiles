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
