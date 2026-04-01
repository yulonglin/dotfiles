use std::collections::BTreeMap;
use serde::Deserialize;
use crate::util::expand_home;

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

fn load_profiles_yaml() -> Result<ProfilesYaml, Box<dyn std::error::Error>> {
    let path = expand_home(super::PROFILES_PATH);
    let content = std::fs::read_to_string(&path)?;
    Ok(serde_yaml::from_str(&content)?)
}

/// Load base plugins and profile definitions from profiles.yaml.
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
