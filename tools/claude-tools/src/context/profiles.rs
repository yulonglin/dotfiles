use std::collections::BTreeMap;
use serde::Deserialize;
use crate::util::expand_home;

#[derive(Deserialize)]
struct ProfilesYaml {
    pub base: Option<Vec<String>>,
    /// OS-gated plugins loaded only on macOS (checked at runtime via std::env::consts::OS).
    pub macos: Option<Vec<String>>,
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

fn load_profiles_yaml() -> Result<ProfilesYaml, Box<dyn std::error::Error>> {
    let path = expand_home(super::PROFILES_PATH);
    let content = std::fs::read_to_string(&path)?;
    Ok(serde_yaml::from_str(&content)?)
}

/// Load base plugins and profile definitions from profiles.yaml.
/// Note: does NOT include the `macos:` list; use `collect_wanted_plugins` for the full
/// OS-aware set. This function is used by callers that only need base + profile defs.
pub fn load_profiles() -> Result<(Vec<String>, BTreeMap<String, ProfileDef>), Box<dyn std::error::Error>> {
    let data = load_profiles_yaml()?;
    Ok((
        data.base.unwrap_or_default(),
        data.profiles.unwrap_or_default(),
    ))
}

/// Load marketplace configurations from profiles.yaml.
pub fn load_marketplaces() -> Result<BTreeMap<String, MarketplaceConfig>, Box<dyn std::error::Error>> {
    let data = load_profiles_yaml()?;
    Ok(data.marketplaces.unwrap_or_default())
}

/// Collect all plugin short names referenced in base + all profiles + OS-gated sections.
pub fn collect_wanted_plugins() -> Result<std::collections::HashSet<String>, Box<dyn std::error::Error>> {
    let data = load_profiles_yaml()?;

    let mut wanted: std::collections::HashSet<String> = data.base.unwrap_or_default().into_iter().collect();

    // Load macOS-specific plugins only when running on macOS.
    // Use std::env::consts::OS (runtime) rather than cfg!(target_os) (compile-time)
    // so a Linux-targeted binary correctly gates even if cross-compiled on macOS.
    if std::env::consts::OS == "macos" {
        if let Some(macos_plugins) = data.macos {
            wanted.extend(macos_plugins);
        }
    }

    if let Some(profiles) = data.profiles {
        for (_name, pdef) in &profiles {
            if let Some(ref enable) = pdef.enable {
                wanted.extend(enable.iter().cloned());
            }
        }
    }

    Ok(wanted)
}
