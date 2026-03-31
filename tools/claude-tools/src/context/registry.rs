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
