use crate::ignore::patterns::{Category, PatternState};
use crate::ignore::managed;

pub enum ListItem {
    CategoryHeader { name: String, description: String },
    PatternRow {
        glob: String,
        description: String,
        state: PatternState,
        #[allow(dead_code)]
        default_state: PatternState,
    },
}

pub struct AppState {
    pub items: Vec<ListItem>,
    pub cursor: usize,
    pub quit: bool,
    pub apply: bool,
    pub warnings: Vec<String>,
}

impl AppState {
    pub fn new(
        categories: &[Category],
        gitignore_path: &str,
        ignore_path: &str,
    ) -> Self {
        let gi_managed = managed::read_managed_patterns(gitignore_path);
        let ig_managed = managed::read_managed_patterns(ignore_path);

        let gi_norm: Vec<String> = gi_managed.iter()
            .map(|p| crate::ignore::patterns::normalize_for_dedup(p))
            .collect();
        let ig_norm: Vec<String> = ig_managed.iter()
            .map(|p| crate::ignore::patterns::normalize_for_dedup(p))
            .collect();

        let mut items = Vec::new();

        for cat in categories {
            items.push(ListItem::CategoryHeader {
                name: cat.name.clone(),
                description: cat.description.clone(),
            });

            for pat in &cat.patterns {
                let norm = crate::ignore::patterns::normalize_for_dedup(&pat.glob);
                let state = if gi_norm.contains(&norm) && ig_norm.contains(&norm) {
                    PatternState::GitignoreSearchable
                } else if gi_norm.contains(&norm) {
                    PatternState::Gitignore
                } else {
                    pat.default_state
                };

                items.push(ListItem::PatternRow {
                    glob: pat.glob.clone(),
                    description: pat.description.clone(),
                    state,
                    default_state: pat.default_state,
                });
            }
        }

        let first_pattern = items.iter()
            .position(|i| matches!(i, ListItem::PatternRow { .. }))
            .unwrap_or(0);

        AppState {
            items,
            cursor: first_pattern,
            quit: false,
            apply: false,
            warnings: Vec::new(),
        }
    }

    pub fn toggle(&mut self) {
        if let Some(ListItem::PatternRow { state, .. }) = self.items.get_mut(self.cursor) {
            *state = state.cycle();
        }
    }

    pub fn move_down(&mut self) {
        let len = self.items.len();
        let mut next = self.cursor + 1;
        while next < len {
            if matches!(self.items[next], ListItem::PatternRow { .. }) {
                self.cursor = next;
                return;
            }
            next += 1;
        }
        // Wrap around
        for (i, item) in self.items.iter().enumerate() {
            if matches!(item, ListItem::PatternRow { .. }) {
                self.cursor = i;
                return;
            }
        }
    }

    pub fn move_up(&mut self) {
        if self.cursor == 0 { return; }
        let mut prev = self.cursor - 1;
        loop {
            if matches!(self.items[prev], ListItem::PatternRow { .. }) {
                self.cursor = prev;
                return;
            }
            if prev == 0 { break; }
            prev -= 1;
        }
        // Wrap around
        for (i, item) in self.items.iter().enumerate().rev() {
            if matches!(item, ListItem::PatternRow { .. }) {
                self.cursor = i;
                return;
            }
        }
    }

    pub fn selections(&self) -> Vec<(String, PatternState)> {
        self.items.iter()
            .filter_map(|item| {
                if let ListItem::PatternRow { glob, state, .. } = item {
                    Some((glob.clone(), *state))
                } else {
                    None
                }
            })
            .collect()
    }

    pub fn gitignore_count(&self) -> usize {
        self.items.iter().filter(|i| matches!(i,
            ListItem::PatternRow { state: PatternState::Gitignore | PatternState::GitignoreSearchable, .. }
        )).count()
    }

    pub fn ignore_count(&self) -> usize {
        self.items.iter().filter(|i| matches!(i,
            ListItem::PatternRow { state: PatternState::GitignoreSearchable, .. }
        )).count()
    }
}
