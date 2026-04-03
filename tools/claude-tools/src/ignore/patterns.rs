use std::fs;

#[derive(Clone, Copy, PartialEq, Debug)]
pub enum PatternState {
    Skip,
    Gitignore,
    GitignoreSearchable,
}

impl PatternState {
    pub fn cycle(self) -> Self {
        match self {
            PatternState::Skip => PatternState::Gitignore,
            PatternState::Gitignore => PatternState::GitignoreSearchable,
            PatternState::GitignoreSearchable => PatternState::Skip,
        }
    }

    pub fn label(self) -> &'static str {
        match self {
            PatternState::Skip => "   ",
            PatternState::Gitignore => " G ",
            PatternState::GitignoreSearchable => "G+S",
        }
    }
}

#[derive(Clone, Debug)]
pub struct Pattern {
    pub glob: String,
    pub description: String,
    pub default_state: PatternState,
}

#[derive(Clone, Debug)]
pub struct Category {
    pub name: String,
    pub description: String,
    pub patterns: Vec<Pattern>,
}

pub fn parse_patterns_file(path: &str) -> Result<Vec<Category>, Box<dyn std::error::Error>> {
    let content = fs::read_to_string(path)?;
    let mut categories: Vec<Category> = Vec::new();
    let mut current: Option<Category> = None;

    for line in content.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() || (trimmed.starts_with('#') && !trimmed.starts_with("##")) {
            continue;
        }
        if let Some(header) = trimmed.strip_prefix("## ") {
            if let Some(cat) = current.take() {
                categories.push(cat);
            }
            let (name, desc) = match header.split_once(" — ") {
                Some((n, d)) => (n.trim().to_string(), d.trim().to_string()),
                None => (header.trim().to_string(), String::new()),
            };
            current = Some(Category { name, description: desc, patterns: Vec::new() });
            continue;
        }
        if let Some(cat) = current.as_mut() {
            let (glob_part, comment) = match trimmed.split_once('#') {
                Some((g, c)) => (g.trim(), c.trim()),
                None => (trimmed, ""),
            };
            if glob_part.is_empty() { continue; }
            let default_state = if comment.contains("[G+S]") {
                PatternState::GitignoreSearchable
            } else if comment.contains("[G]") {
                PatternState::Gitignore
            } else {
                PatternState::Skip
            };
            let description = comment.replace("[G+S]", "").replace("[G]", "").trim().to_string();
            cat.patterns.push(Pattern { glob: glob_part.to_string(), description, default_state });
        }
    }
    if let Some(cat) = current { categories.push(cat); }
    Ok(categories)
}

pub fn normalize_for_dedup(pattern: &str) -> String {
    let s = pattern.trim();
    let s = s.strip_prefix('!').unwrap_or(s);
    s.strip_suffix('/').unwrap_or(s).to_string()
}
