use std::collections::BTreeMap;
use crate::context::profiles::ProfileDef;

#[derive(Clone, Copy, PartialEq)]
pub enum View {
    Profiles,
    Plugins,
}

#[derive(Clone, Copy, PartialEq)]
pub enum Override {
    Inherit,
    ForceOn,
    ForceOff,
}

pub struct PluginItem {
    pub name: String,
    pub from_base: bool,
    pub from_profiles: Vec<String>,
    pub profile_enabled: bool,
    pub override_state: Override,
}

impl PluginItem {
    /// Effective enabled state after overrides.
    pub fn effective(&self) -> bool {
        match self.override_state {
            Override::Inherit => self.profile_enabled,
            Override::ForceOn => true,
            Override::ForceOff => false,
        }
    }

    pub fn has_override(&self) -> bool {
        self.override_state != Override::Inherit
    }

    /// Source description for display.
    pub fn source(&self) -> String {
        if self.from_base {
            "base".to_string()
        } else if self.from_profiles.is_empty() {
            String::new()
        } else {
            self.from_profiles.join(", ")
        }
    }
}

pub struct Profile {
    pub name: String,
    pub comment: String,
    pub plugins: Vec<String>,
    pub enabled: bool,
}

pub struct AppState {
    pub view: View,
    pub profiles: Vec<Profile>,
    pub plugins: Vec<PluginItem>,
    pub profile_cursor: usize,
    pub plugin_cursor: usize,
    pub original_profile_selection: Vec<bool>,
    pub original_overrides: Vec<Override>,
    pub quit: bool,
    pub apply: bool,
    pub sync: bool,
}

impl AppState {
    pub fn new(
        registry: &BTreeMap<String, String>,
        base: &[String],
        profile_defs: &BTreeMap<String, ProfileDef>,
        active_profiles: &[String],
        active_enable: &[String],
        active_disable: &[String],
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
        let original_profile_selection: Vec<bool> = profiles.iter().map(|p| p.enabled).collect();

        // Build plugin items from registry
        let selected_profiles: Vec<&String> = profiles
            .iter()
            .filter(|p| p.enabled)
            .map(|p| &p.name)
            .collect();

        let mut plugin_items: Vec<PluginItem> = registry
            .iter()
            .map(|(short, _qid)| {
                let from_base = base.contains(short);
                let from_profiles: Vec<String> = profile_defs
                    .iter()
                    .filter(|(pname, pdef)| {
                        selected_profiles.contains(&pname)
                            && pdef
                                .enable
                                .as_ref()
                                .map(|e| e.contains(short))
                                .unwrap_or(false)
                    })
                    .map(|(pname, _)| pname.clone())
                    .collect();
                let profile_enabled = from_base || !from_profiles.is_empty();

                let override_state = if active_enable.contains(short) {
                    Override::ForceOn
                } else if active_disable.contains(short) {
                    Override::ForceOff
                } else {
                    Override::Inherit
                };

                PluginItem {
                    name: short.clone(),
                    from_base,
                    from_profiles,
                    profile_enabled,
                    override_state,
                }
            })
            .collect();

        // Sort: enabled first, then alphabetical
        plugin_items.sort_by(|a, b| {
            let a_eff = !a.effective();
            let b_eff = !b.effective();
            (a_eff, &a.name).cmp(&(b_eff, &b.name))
        });

        let original_overrides: Vec<Override> =
            plugin_items.iter().map(|p| p.override_state).collect();

        Self {
            view: View::Profiles,
            profiles,
            plugins: plugin_items,
            profile_cursor: 0,
            plugin_cursor: 0,
            original_profile_selection,
            original_overrides,
            quit: false,
            apply: false,
            sync: false,
        }
    }

    pub fn is_modified(&self) -> bool {
        let profiles_changed = self
            .profiles
            .iter()
            .enumerate()
            .any(|(i, p)| p.enabled != self.original_profile_selection[i]);
        let overrides_changed = self
            .plugins
            .iter()
            .enumerate()
            .any(|(i, p)| p.override_state != self.original_overrides[i]);
        profiles_changed || overrides_changed
    }

    pub fn selected_profile_names(&self) -> Vec<String> {
        self.profiles
            .iter()
            .filter(|p| p.enabled)
            .map(|p| p.name.clone())
            .collect()
    }

    pub fn enable_overrides(&self) -> Vec<String> {
        self.plugins
            .iter()
            .filter(|p| p.override_state == Override::ForceOn)
            .map(|p| p.name.clone())
            .collect()
    }

    pub fn disable_overrides(&self) -> Vec<String> {
        self.plugins
            .iter()
            .filter(|p| p.override_state == Override::ForceOff)
            .map(|p| p.name.clone())
            .collect()
    }

    pub fn override_count(&self) -> usize {
        self.plugins.iter().filter(|p| p.has_override()).count()
    }

    // --- Navigation ---

    pub fn switch_view(&mut self) {
        self.view = match self.view {
            View::Profiles => View::Plugins,
            View::Plugins => View::Profiles,
        };
    }

    pub fn list_len(&self) -> usize {
        match self.view {
            View::Profiles => self.profiles.len(),
            View::Plugins => self.plugins.len(),
        }
    }

    pub fn move_up(&mut self) {
        let c = match self.view {
            View::Profiles => &mut self.profile_cursor,
            View::Plugins => &mut self.plugin_cursor,
        };
        if *c > 0 {
            *c -= 1;
        }
    }

    pub fn move_down(&mut self) {
        let len = self.list_len();
        let c = match self.view {
            View::Profiles => &mut self.profile_cursor,
            View::Plugins => &mut self.plugin_cursor,
        };
        if *c + 1 < len {
            *c += 1;
        }
    }

    pub fn toggle_current(&mut self) {
        match self.view {
            View::Profiles => {
                if let Some(p) = self.profiles.get_mut(self.profile_cursor) {
                    p.enabled = !p.enabled;
                }
                self.rebuild_plugin_profile_state();
            }
            View::Plugins => {
                if let Some(p) = self.plugins.get_mut(self.plugin_cursor) {
                    p.override_state = match p.override_state {
                        Override::Inherit => {
                            if p.profile_enabled {
                                Override::ForceOff
                            } else {
                                Override::ForceOn
                            }
                        }
                        Override::ForceOn => Override::Inherit,
                        Override::ForceOff => Override::Inherit,
                    };
                }
            }
        }
    }

    pub fn select_all(&mut self) {
        match self.view {
            View::Profiles => {
                for p in &mut self.profiles {
                    p.enabled = true;
                }
                self.rebuild_plugin_profile_state();
            }
            View::Plugins => {
                for p in &mut self.plugins {
                    if !p.effective() {
                        p.override_state = if p.profile_enabled {
                            Override::Inherit
                        } else {
                            Override::ForceOn
                        };
                    }
                }
            }
        }
    }

    pub fn select_none(&mut self) {
        match self.view {
            View::Profiles => {
                for p in &mut self.profiles {
                    p.enabled = false;
                }
                self.rebuild_plugin_profile_state();
            }
            View::Plugins => {
                for p in &mut self.plugins {
                    p.override_state = Override::Inherit;
                }
            }
        }
    }

    /// Recalculate plugin profile_enabled and from_profiles after profile toggles.
    fn rebuild_plugin_profile_state(&mut self) {
        // Collect enabled profile names and their plugins first (avoid borrow conflict)
        let enabled_profiles: Vec<(String, Vec<String>)> = self
            .profiles
            .iter()
            .filter(|p| p.enabled)
            .map(|p| (p.name.clone(), p.plugins.clone()))
            .collect();

        for plugin in &mut self.plugins {
            if plugin.from_base {
                plugin.profile_enabled = true;
                continue;
            }
            let from: Vec<String> = enabled_profiles
                .iter()
                .filter(|(_, plugins)| plugins.contains(&plugin.name))
                .map(|(name, _)| name.clone())
                .collect();
            plugin.profile_enabled = !from.is_empty();
            plugin.from_profiles = from;
        }
    }
}
