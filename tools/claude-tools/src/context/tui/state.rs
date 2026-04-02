use std::collections::BTreeMap;
use crate::context::profiles::ProfileDef;

pub struct Profile {
    pub name: String,
    pub comment: String,
    pub plugins: Vec<String>,
    pub enabled: bool,
}

pub struct AppState {
    pub profiles: Vec<Profile>,
    pub cursor: usize,
    pub original_selection: Vec<bool>,
    pub quit: bool,
    pub apply: bool,
}

impl AppState {
    pub fn new(
        profile_defs: &BTreeMap<String, ProfileDef>,
        active_profiles: &[String],
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
        let original_selection: Vec<bool> = profiles.iter().map(|p| p.enabled).collect();
        Self {
            profiles,
            cursor: 0,
            original_selection,
            quit: false,
            apply: false,
        }
    }

    pub fn is_modified(&self) -> bool {
        self.profiles
            .iter()
            .enumerate()
            .any(|(i, p)| p.enabled != self.original_selection[i])
    }

    pub fn selected_profile_names(&self) -> Vec<String> {
        self.profiles
            .iter()
            .filter(|p| p.enabled)
            .map(|p| p.name.clone())
            .collect()
    }

    pub fn toggle_current(&mut self) {
        if let Some(p) = self.profiles.get_mut(self.cursor) {
            p.enabled = !p.enabled;
        }
    }

    pub fn move_up(&mut self) {
        if self.cursor > 0 {
            self.cursor -= 1;
        }
    }

    pub fn move_down(&mut self) {
        if self.cursor + 1 < self.profiles.len() {
            self.cursor += 1;
        }
    }

    pub fn select_all(&mut self) {
        for p in &mut self.profiles {
            p.enabled = true;
        }
    }

    pub fn select_none(&mut self) {
        for p in &mut self.profiles {
            p.enabled = false;
        }
    }
}
