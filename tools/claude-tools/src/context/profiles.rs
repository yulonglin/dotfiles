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
