# `claude-tools ignore` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an interactive TUI to `claude-tools` for managing per-repo `.gitignore` and `.ignore` patterns with tri-state toggles (skip / gitignore / gitignore+searchable).

**Architecture:** New `src/ignore/` module with pattern parser, managed-section reader/writer, and ratatui TUI. Reuses theme conventions from `src/context/tui/`. File reorganization moves `config/ignore_*` into `config/ignore/` directory with clearer naming.

**Tech Stack:** Rust, ratatui 0.30, crossterm 0.29, clap 4.6 (all already in Cargo.toml)

---

### Task 1: File Reorganization

**Files:**
- Move: `config/ignore_global` → `config/ignore/gitignore_base`
- Move: `config/ignore_research` → `config/ignore/gitignore_research`
- Delete: `config/ignore_template`
- Modify: `scripts/shared/helpers.sh:976-1009`
- Modify: `CLAUDE.md:136-138, 251-254, 382`

- [ ] **Step 1: Create `config/ignore/` directory and move files**

```bash
mkdir -p config/ignore
git mv config/ignore_global config/ignore/gitignore_base
git mv config/ignore_research config/ignore/gitignore_research
git rm config/ignore_template
```

- [ ] **Step 2: Update header comments in `config/ignore/gitignore_base`**

Replace the first 4 lines of `config/ignore/gitignore_base` with:

```gitignore
# gitignore_base — Universal ignore patterns (OS, editors, Python, LaTeX, Claude Code)
#
# Consumers:
#   - git: via ~/.gitignore_global (concatenated with gitignore_research)
#   - ripgrep: via ~/.ignore_global (symlink to this file)
#   - fd: via ~/.config/fd/ignore (symlink to this file)
#   - Claude Code / Cursor: via ripgrep (Glob/Grep tools)
#
# Deployment: `deploy.sh --git-config` (see scripts/shared/helpers.sh)
# Source of truth: config/ignore/gitignore_base (this file)
#
# Adding entries: Add universal patterns here. For project-specific patterns
# that should be interactively selectable, add to config/ignore/patterns instead.
```

- [ ] **Step 3: Update header comments in `config/ignore/gitignore_research`**

Replace the first 4 lines of `config/ignore/gitignore_research` with:

```gitignore
# gitignore_research — Research-specific ignore patterns
#
# Consumers:
#   - git ONLY: via ~/.gitignore_global (concatenated after gitignore_base)
#   - NOT used by: ripgrep, fd, Claude Code, Cursor
#
# Purpose: These directories are git-ignored but remain searchable by rg/fd/Claude.
# This separation lets search tools index research files while git ignores them.
#
# Deployment: `deploy.sh --git-config` (see scripts/shared/helpers.sh)
# Source of truth: config/ignore/gitignore_research (this file)
```

- [ ] **Step 4: Update `helpers.sh` paths**

In `scripts/shared/helpers.sh`, replace lines 982-999 — change all `config/ignore_global` to `config/ignore/gitignore_base` and `config/ignore_research` to `config/ignore/gitignore_research`:

```bash
    # Deploy global gitignore (composed from universal + research patterns)
    # Git sees both; search tools (rg, fd, Claude Code) see only universal.
    if [[ -f "$DOT_DIR/config/ignore/gitignore_base" ]] && [[ -f "$DOT_DIR/config/ignore/gitignore_research" ]]; then
        cat "$DOT_DIR/config/ignore/gitignore_base" "$DOT_DIR/config/ignore/gitignore_research" > "$HOME/.gitignore_global"
        log_success "Deployed ~/.gitignore_global (universal + research)"
    elif [[ -f "$DOT_DIR/config/ignore/gitignore_base" ]]; then
        cp "$DOT_DIR/config/ignore/gitignore_base" "$HOME/.gitignore_global"
        log_success "Deployed ~/.gitignore_global (universal only)"
    fi

    # Deploy search tool ignore files (universal only, symlinked for auto-update)
    if [[ -f "$DOT_DIR/config/ignore/gitignore_base" ]]; then
        # ripgrep + Claude Code: symlink universal ignore
        ln -sf "$DOT_DIR/config/ignore/gitignore_base" "$HOME/.ignore_global"
        log_success "Symlinked ~/.ignore_global"

        # fd: symlink to same file
        local fd_config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/fd"
        mkdir -p "$fd_config_dir"
        ln -sf "$DOT_DIR/config/ignore/gitignore_base" "$fd_config_dir/ignore"
        log_success "Symlinked $fd_config_dir/ignore"
```

- [ ] **Step 5: Update `CLAUDE.md` config tree (lines 136-138)**

Replace:
```
├── ignore_global         # Universal ignore patterns (OS, editors, Python, LaTeX, Claude Code)
├── ignore_research       # Research-only ignore patterns (archive/, data/, experiments/, etc.)
├── ignore_template       # Per-project .ignore template (negation patterns for search tools)
```

With:
```
├── ignore/                   # Ignore pattern management
│   ├── gitignore_base        # Universal patterns — deployed to git AND search tools
│   ├── gitignore_research    # Research dirs — deployed to git ONLY (search tools skip)
│   └── patterns              # Pattern definitions for `claude-tools ignore apply` TUI
```

- [ ] **Step 6: Update `CLAUDE.md` git config references (lines 251-254)**

Replace all `config/ignore_global` with `config/ignore/gitignore_base` and `config/ignore_research` with `config/ignore/gitignore_research`.

- [ ] **Step 7: Update `CLAUDE.md` symlinks section (line 382)**

Replace:
```
`~/.gitignore_global` is composed (concatenated from `config/ignore_global` + `config/ignore_research`)
```
With:
```
`~/.gitignore_global` is composed (concatenated from `config/ignore/gitignore_base` + `config/ignore/gitignore_research`)
```

- [ ] **Step 8: Verify deploy still works**

```bash
cd ~/code/dotfiles && bash -c 'source scripts/shared/helpers.sh && deploy_git_config'
ls -la ~/.gitignore_global ~/.ignore_global ~/.config/fd/ignore
```

Expected: all three files exist, symlinks point to new paths.

- [ ] **Step 9: Commit**

```bash
git add config/ignore/ scripts/shared/helpers.sh CLAUDE.md
git add -u config/ignore_global config/ignore_research config/ignore_template
git commit -m "refactor: reorganize ignore files into config/ignore/ with clearer naming"
```

---

### Task 2: Create Pattern Definitions File

**Files:**
- Create: `config/ignore/patterns`

- [ ] **Step 1: Create `config/ignore/patterns`**

```gitignore
# Pattern definitions for `claude-tools ignore apply`
#
# This file defines patterns available in the interactive TUI.
# Users select per-repo which patterns to apply to .gitignore and .ignore.
#
# Format:
#   - Lines starting with ## are category headers: ## name — description
#   - Each pattern line: glob  # description [default]
#   - Defaults: [G+S] = gitignore + searchable, [G] = gitignore only
#   - Blank lines and # comments are ignored by the parser
#
# Adding patterns: append to an existing category or create a new ## section.
# The TUI groups patterns by category and shows descriptions inline.

## research — Research project directories
data/                    # Dataset files [G+S]
experiments/             # Experiment outputs [G+S]
results/                 # Result artifacts [G+S]
out/                     # Output directory [G+S]
output/                  # Output directory (alt) [G+S]
outputs/                 # Output directory (alt) [G+S]
logs/                    # Log files [G+S]
archive/                 # Archived runs [G]

## python — Python build and runtime artifacts
.venv/                   # Virtual environment [G]
__pycache__/             # Bytecode cache [G]
*.egg-info/              # Package metadata [G]
.eggs/                   # Egg build dir [G]
dist/                    # Distribution packages [G]
build/                   # Build output [G]
.mypy_cache/             # Mypy cache [G]
.ruff_cache/             # Ruff cache [G]
.pytest_cache/           # Pytest cache [G]

## node — Node.js artifacts
node_modules/            # Dependencies [G]
.next/                   # Next.js build [G]
.nuxt/                   # Nuxt build [G]

## ml — Machine learning artifacts
checkpoints/             # Model checkpoints [G+S]
wandb/                   # W&B run logs [G+S]
models/                  # Saved models [G]
.cache/huggingface/      # HF model cache [G]

## misc — Common project artifacts
.env                     # Environment secrets [G]
.env.*                   # Environment variants [G]
*.sqlite                 # SQLite databases [G]
```

- [ ] **Step 2: Commit**

```bash
git add config/ignore/patterns
git commit -m "feat: add ignore pattern definitions for interactive TUI"
```

---

### Task 3: Pattern Parser and Managed Section Logic

**Files:**
- Create: `tools/claude-tools/src/ignore/mod.rs`
- Create: `tools/claude-tools/src/ignore/patterns.rs`
- Create: `tools/claude-tools/src/ignore/managed.rs`
- Modify: `tools/claude-tools/src/main.rs` (add `mod ignore;`)

- [ ] **Step 1: Create `src/ignore/mod.rs`**

```rust
pub mod managed;
pub mod patterns;
pub mod tui;

use clap::{Parser, Subcommand};

#[derive(Parser)]
#[command(name = "claude-tools-ignore")]
pub struct IgnoreCli {
    #[command(subcommand)]
    command: Option<IgnoreCommand>,
}

#[derive(Subcommand)]
enum IgnoreCommand {
    /// Show current .gitignore and .ignore managed state
    Status,
    /// Interactive TUI to select patterns (default if no subcommand)
    Apply {
        /// Show what would change without writing
        #[arg(long)]
        dry_run: bool,
        /// Apply defaults from patterns file without TUI
        #[arg(long)]
        non_interactive: bool,
    },
}

pub fn run(args: Vec<String>) -> Result<(), Box<dyn std::error::Error>> {
    let cli = IgnoreCli::parse_from(&args);
    match cli.command {
        None | Some(IgnoreCommand::Apply { dry_run: false, non_interactive: false }) => {
            tui::run()
        }
        Some(IgnoreCommand::Apply { dry_run, non_interactive }) => {
            run_apply(dry_run, non_interactive)
        }
        Some(IgnoreCommand::Status) => {
            run_status()
        }
    }
}

fn run_apply(dry_run: bool, non_interactive: bool) -> Result<(), Box<dyn std::error::Error>> {
    let dot_dir = find_dotfiles_dir()?;
    let patterns_path = format!("{}/config/ignore/patterns", dot_dir);
    let categories = patterns::parse_patterns_file(&patterns_path)?;

    let git_root = find_git_root()?;
    let gitignore_path = format!("{}/.gitignore", git_root);
    let ignore_path = format!("{}/.ignore", git_root);

    // For non-interactive: use defaults from patterns file
    let selections: Vec<(String, patterns::PatternState)> = categories.iter()
        .flat_map(|c| c.patterns.iter())
        .map(|p| (p.glob.clone(), p.default_state))
        .collect();

    if dry_run {
        print_dry_run(&gitignore_path, &ignore_path, &selections);
    } else {
        managed::apply(&gitignore_path, &selections, false)?;
        managed::apply(&ignore_path, &selections, true)?;
        print_summary(&selections);
    }
    Ok(())
}

fn run_status() -> Result<(), Box<dyn std::error::Error>> {
    let git_root = find_git_root()?;
    let gitignore_path = format!("{}/.gitignore", git_root);
    let ignore_path = format!("{}/.ignore", git_root);

    let gi_managed = managed::read_managed_patterns(&gitignore_path);
    let ig_managed = managed::read_managed_patterns(&ignore_path);

    let gi_total = managed::count_non_managed_patterns(&gitignore_path);

    println!(".gitignore: {} managed patterns ({})",
        gi_managed.len(),
        gi_managed.join(", "));
    println!(".ignore:    {} managed patterns ({})",
        ig_managed.len(),
        ig_managed.join(", "));
    println!("Unmanaged:  .gitignore has {} manual entries", gi_total);
    Ok(())
}

fn print_dry_run(
    gitignore_path: &str,
    ignore_path: &str,
    selections: &[(String, patterns::PatternState)],
) {
    let gi: Vec<_> = selections.iter()
        .filter(|(_, s)| matches!(s, patterns::PatternState::Gitignore | patterns::PatternState::GitignoreSearchable))
        .map(|(g, _)| g.as_str())
        .collect();
    let ig: Vec<_> = selections.iter()
        .filter(|(_, s)| matches!(s, patterns::PatternState::GitignoreSearchable))
        .map(|(g, _)| format!("!{}", g))
        .collect();

    println!("Dry run — no files modified.\n");
    if !gi.is_empty() {
        println!("{} → {} patterns:", gitignore_path, gi.len());
        for p in &gi { println!("  {}", p); }
    }
    if !ig.is_empty() {
        println!("{} → {} patterns:", ignore_path, ig.len());
        for p in &ig { println!("  {}", p); }
    }
}

fn print_summary(selections: &[(String, patterns::PatternState)]) {
    let gi_count = selections.iter()
        .filter(|(_, s)| matches!(s, patterns::PatternState::Gitignore | patterns::PatternState::GitignoreSearchable))
        .count();
    let ig_count = selections.iter()
        .filter(|(_, s)| matches!(s, patterns::PatternState::GitignoreSearchable))
        .count();
    println!("Applied: {} → .gitignore, {} → .ignore", gi_count, ig_count);
}

/// Find the dotfiles repo root (contains config/ignore/patterns).
fn find_dotfiles_dir() -> Result<String, Box<dyn std::error::Error>> {
    // Try $DOT_DIR first, then common locations
    if let Ok(d) = std::env::var("DOT_DIR") {
        if std::path::Path::new(&format!("{}/config/ignore/patterns", d)).exists() {
            return Ok(d);
        }
    }
    let home = std::env::var("HOME")?;
    for candidate in &["code/dotfiles", "dotfiles", ".dotfiles"] {
        let path = format!("{}/{}", home, candidate);
        if std::path::Path::new(&format!("{}/config/ignore/patterns", path)).exists() {
            return Ok(path);
        }
    }
    Err("Cannot find dotfiles dir (set $DOT_DIR)".into())
}

/// Find the git root of the current working directory.
fn find_git_root() -> Result<String, Box<dyn std::error::Error>> {
    let repo = git2::Repository::discover(".")?;
    let workdir = repo.workdir()
        .ok_or("Not a git work tree")?;
    Ok(workdir.to_string_lossy().trim_end_matches('/').to_string())
}
```

- [ ] **Step 2: Create `src/ignore/patterns.rs`**

```rust
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

/// Parse the patterns file into categories.
///
/// Format:
///   ## category_name — description
///   glob/pattern   # description [G] or [G+S]
pub fn parse_patterns_file(path: &str) -> Result<Vec<Category>, Box<dyn std::error::Error>> {
    let content = fs::read_to_string(path)?;
    let mut categories: Vec<Category> = Vec::new();
    let mut current: Option<Category> = None;

    for line in content.lines() {
        let trimmed = line.trim();

        // Skip blank lines and plain comments
        if trimmed.is_empty() || (trimmed.starts_with('#') && !trimmed.starts_with("##")) {
            continue;
        }

        // Category header: ## name — description
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

        // Pattern line: glob  # description [G] or [G+S]
        if let Some(cat) = current.as_mut() {
            let (glob_part, comment) = match trimmed.split_once('#') {
                Some((g, c)) => (g.trim(), c.trim()),
                None => (trimmed, ""),
            };

            if glob_part.is_empty() {
                continue;
            }

            let default_state = if comment.contains("[G+S]") {
                PatternState::GitignoreSearchable
            } else if comment.contains("[G]") {
                PatternState::Gitignore
            } else {
                PatternState::Skip
            };

            // Strip the [G] / [G+S] tag from description
            let description = comment
                .replace("[G+S]", "")
                .replace("[G]", "")
                .trim()
                .to_string();

            cat.patterns.push(Pattern {
                glob: glob_part.to_string(),
                description,
                default_state,
            });
        }
    }

    if let Some(cat) = current {
        categories.push(cat);
    }

    Ok(categories)
}

/// Normalize a pattern for dedup comparison.
/// Strips trailing `/` so `data/` matches `data`.
pub fn normalize_for_dedup(pattern: &str) -> String {
    let s = pattern.trim();
    // Strip leading `!` for negation patterns
    let s = s.strip_prefix('!').unwrap_or(s);
    // Strip trailing `/`
    s.strip_suffix('/').unwrap_or(s).to_string()
}
```

- [ ] **Step 3: Create `src/ignore/managed.rs`**

```rust
use std::fs;
use std::path::Path;

use super::patterns::{PatternState, normalize_for_dedup};

const BEGIN_MARKER: &str = "# --- claude-tools ignore begin ---";
const END_MARKER: &str = "# --- claude-tools ignore end ---";
const MANAGED_COMMENT: &str = "# Managed by `claude-tools ignore apply`. Do not edit manually.";

/// Read patterns from the managed section of a file.
/// Returns empty vec if file doesn't exist or has no managed section.
pub fn read_managed_patterns(path: &str) -> Vec<String> {
    let content = match fs::read_to_string(path) {
        Ok(c) => c,
        Err(_) => return Vec::new(),
    };
    extract_managed_patterns(&content)
}

fn extract_managed_patterns(content: &str) -> Vec<String> {
    let mut in_managed = false;
    let mut patterns = Vec::new();

    for line in content.lines() {
        let trimmed = line.trim();
        if trimmed == BEGIN_MARKER {
            in_managed = true;
            continue;
        }
        if trimmed == END_MARKER {
            break;
        }
        if in_managed && !trimmed.is_empty() && !trimmed.starts_with('#') {
            patterns.push(trimmed.to_string());
        }
    }
    patterns
}

/// Read all non-managed, non-comment patterns from a file.
pub fn count_non_managed_patterns(path: &str) -> usize {
    let content = match fs::read_to_string(path) {
        Ok(c) => c,
        Err(_) => return 0,
    };
    let mut in_managed = false;
    let mut count = 0;
    for line in content.lines() {
        let trimmed = line.trim();
        if trimmed == BEGIN_MARKER { in_managed = true; continue; }
        if trimmed == END_MARKER { in_managed = false; continue; }
        if !in_managed && !trimmed.is_empty() && !trimmed.starts_with('#') {
            count += 1;
        }
    }
    count
}

/// Read non-managed patterns for dedup checking.
fn read_user_patterns(content: &str) -> Vec<String> {
    let mut in_managed = false;
    let mut patterns = Vec::new();
    for line in content.lines() {
        let trimmed = line.trim();
        if trimmed == BEGIN_MARKER { in_managed = true; continue; }
        if trimmed == END_MARKER { in_managed = false; continue; }
        if !in_managed && !trimmed.is_empty() && !trimmed.starts_with('#') {
            patterns.push(trimmed.to_string());
        }
    }
    patterns
}

/// Apply selections to a file's managed section.
///
/// If `is_ignore_file` is true, writes negation patterns (`!glob`) for GitignoreSearchable.
/// If false, writes glob patterns for Gitignore and GitignoreSearchable.
pub fn apply(
    path: &str,
    selections: &[(String, PatternState)],
    is_ignore_file: bool,
) -> Result<Vec<String>, Box<dyn std::error::Error>> {
    // Determine which patterns to write
    let new_patterns: Vec<String> = if is_ignore_file {
        selections.iter()
            .filter(|(_, s)| matches!(s, PatternState::GitignoreSearchable))
            .map(|(g, _)| format!("!{}", g))
            .collect()
    } else {
        selections.iter()
            .filter(|(_, s)| matches!(s, PatternState::Gitignore | PatternState::GitignoreSearchable))
            .map(|(g, _)| g.clone())
            .collect()
    };

    // If nothing to write for .ignore, clean up managed section or skip
    if new_patterns.is_empty() {
        if Path::new(path).exists() {
            remove_managed_section(path)?;
        }
        return Ok(Vec::new());
    }

    // Read existing file content (or empty)
    let content = fs::read_to_string(path).unwrap_or_default();

    // Check for user-section duplicates
    let user_patterns = read_user_patterns(&content);
    let user_normalized: Vec<String> = user_patterns.iter()
        .map(|p| normalize_for_dedup(p))
        .collect();

    let mut warnings = Vec::new();
    let deduped: Vec<String> = new_patterns.into_iter()
        .filter(|p| {
            let norm = normalize_for_dedup(p);
            if user_normalized.contains(&norm) {
                warnings.push(format!("'{}' already in user section, skipping", p));
                false
            } else {
                true
            }
        })
        .collect();

    // Build new file content
    let before_managed = strip_managed_section(&content);
    let mut output = before_managed.trim_end().to_string();

    if !deduped.is_empty() {
        if !output.is_empty() {
            output.push_str("\n\n");
        }
        output.push_str(BEGIN_MARKER);
        output.push('\n');
        output.push_str(MANAGED_COMMENT);
        output.push('\n');
        for p in &deduped {
            output.push_str(p);
            output.push('\n');
        }
        output.push_str(END_MARKER);
    }
    output.push('\n');

    fs::write(path, output)?;
    Ok(warnings)
}

/// Remove the managed section from a file's content (returns content without it).
fn strip_managed_section(content: &str) -> String {
    let mut result = String::new();
    let mut in_managed = false;
    for line in content.lines() {
        let trimmed = line.trim();
        if trimmed == BEGIN_MARKER {
            in_managed = true;
            continue;
        }
        if trimmed == END_MARKER {
            in_managed = false;
            continue;
        }
        if !in_managed {
            result.push_str(line);
            result.push('\n');
        }
    }
    result
}

fn remove_managed_section(path: &str) -> Result<(), Box<dyn std::error::Error>> {
    let content = fs::read_to_string(path)?;
    let cleaned = strip_managed_section(&content);
    let trimmed = cleaned.trim();
    if trimmed.is_empty() {
        // File would be empty — leave it alone (don't delete user's file)
        // But remove managed content
        fs::write(path, format!("{}\n", trimmed))?;
    } else {
        fs::write(path, format!("{}\n", trimmed))?;
    }
    Ok(())
}
```

- [ ] **Step 4: Add `mod ignore` to `main.rs`**

Add `mod ignore;` to the module list and add the subcommand match arm in `main.rs`:

```rust
mod ignore;
```

And in the match:

```rust
        "ignore" => {
            let mut ig_args = vec!["claude-tools-ignore".to_string()];
            ig_args.extend_from_slice(&args[2..]);
            ignore::run(ig_args)
        }
```

Also update the usage line:

```rust
        eprintln!("Subcommands: statusline, context, check-git-root, resolve-file-path, ignore");
```

- [ ] **Step 5: Verify it compiles**

```bash
cd tools/claude-tools && cargo build 2>&1
```

Expected: compiles (TUI module will be a stub for now — create an empty `src/ignore/tui/mod.rs` placeholder):

```rust
// src/ignore/tui/mod.rs — placeholder, implemented in Task 4
pub fn run() -> Result<(), Box<dyn std::error::Error>> {
    println!("TUI not yet implemented. Use --non-interactive for now.");
    Ok(())
}
```

Create `src/ignore/tui/` directory:

```bash
mkdir -p src/ignore/tui
```

- [ ] **Step 6: Test pattern parser manually**

```bash
cd ~/code/dotfiles && cargo run --manifest-path tools/claude-tools/Cargo.toml -- ignore status
```

Expected: output showing "0 managed patterns" since no repo has managed sections yet.

- [ ] **Step 7: Test `--non-interactive --dry-run`**

```bash
cd ~/code/some-test-repo && cargo run --manifest-path ~/code/dotfiles/tools/claude-tools/Cargo.toml -- ignore apply --non-interactive --dry-run
```

Expected: lists default patterns that would be applied.

- [ ] **Step 8: Commit**

```bash
cd ~/code/dotfiles
git add tools/claude-tools/src/ignore/
git add tools/claude-tools/src/main.rs
git commit -m "feat(claude-tools): add ignore module with pattern parser and managed section logic"
```

---

### Task 4: TUI Implementation

**Files:**
- Create: `tools/claude-tools/src/ignore/tui/mod.rs` (replace placeholder)
- Create: `tools/claude-tools/src/ignore/tui/state.rs`

- [ ] **Step 1: Create `src/ignore/tui/state.rs`**

```rust
use crate::ignore::patterns::{Category, Pattern, PatternState};
use crate::ignore::managed;

/// A flattened item in the TUI list — either a category header or a pattern.
pub enum ListItem {
    CategoryHeader { name: String, description: String },
    PatternRow {
        glob: String,
        description: String,
        state: PatternState,
        default_state: PatternState,
    },
}

pub struct AppState {
    pub items: Vec<ListItem>,
    pub cursor: usize,
    pub quit: bool,
    pub apply: bool,
    /// Warnings from dedup (patterns already in user section).
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

        // Normalize for lookup
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
                    PatternState::Skip
                };

                items.push(ListItem::PatternRow {
                    glob: pat.glob.clone(),
                    description: pat.description.clone(),
                    state,
                    default_state: pat.default_state,
                });
            }
        }

        // Position cursor on first pattern row (skip first header)
        let first_pattern = items.iter().position(|i| matches!(i, ListItem::PatternRow { .. })).unwrap_or(0);

        AppState {
            items,
            cursor: first_pattern,
            quit: false,
            apply: false,
            warnings: Vec::new(),
        }
    }

    /// Toggle the state of the pattern at cursor position.
    pub fn toggle(&mut self) {
        if let Some(ListItem::PatternRow { state, .. }) = self.items.get_mut(self.cursor) {
            *state = state.cycle();
        }
    }

    /// Move cursor down, skipping category headers.
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
        // Wrap to first pattern
        for (i, item) in self.items.iter().enumerate() {
            if matches!(item, ListItem::PatternRow { .. }) {
                self.cursor = i;
                return;
            }
        }
    }

    /// Move cursor up, skipping category headers.
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
        // Wrap to last pattern
        for (i, item) in self.items.iter().enumerate().rev() {
            if matches!(item, ListItem::PatternRow { .. }) {
                self.cursor = i;
                return;
            }
        }
    }

    /// Collect selections as (glob, state) pairs.
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

    /// Count patterns by destination file.
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
```

- [ ] **Step 2: Implement `src/ignore/tui/mod.rs`**

```rust
pub mod state;

use crossterm::event::{self, Event, KeyCode, KeyEventKind};
use crossterm::terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen};
use crossterm::ExecutableCommand;
use ratatui::prelude::*;
use ratatui::widgets::{Block, Borders, Paragraph};

use state::{AppState, ListItem};
use crate::ignore::patterns::PatternState;
use crate::context::tui::theme;

pub fn run() -> Result<(), Box<dyn std::error::Error>> {
    let dot_dir = super::find_dotfiles_dir()?;
    let patterns_path = format!("{}/config/ignore/patterns", dot_dir);
    let categories = crate::ignore::patterns::parse_patterns_file(&patterns_path)?;

    let git_root = super::find_git_root()?;
    let gitignore_path = format!("{}/.gitignore", git_root);
    let ignore_path = format!("{}/.ignore", git_root);

    let mut state = AppState::new(&categories, &gitignore_path, &ignore_path);

    // Setup terminal
    enable_raw_mode()?;
    std::io::stdout().execute(EnterAlternateScreen)?;

    let result = run_loop(&mut state);

    // Always restore terminal
    let _ = disable_raw_mode();
    let _ = std::io::stdout().execute(LeaveAlternateScreen);

    result?;

    if state.apply {
        let selections = state.selections();
        let gi_warnings = super::managed::apply(&gitignore_path, &selections, false)?;
        let ig_warnings = super::managed::apply(&ignore_path, &selections, true)?;

        for w in gi_warnings.iter().chain(ig_warnings.iter()) {
            println!("  ⚠ {}", w);
        }
        super::print_summary(&selections);
    }

    Ok(())
}

fn run_loop(state: &mut AppState) -> Result<(), Box<dyn std::error::Error>> {
    let mut terminal = ratatui::init();

    loop {
        terminal.draw(|f| render(f, state))?;

        if let Event::Key(key) = event::read()? {
            if key.kind != KeyEventKind::Press { continue; }
            match key.code {
                KeyCode::Char('q') | KeyCode::Esc => { state.quit = true; break; }
                KeyCode::Enter => { state.apply = true; break; }
                KeyCode::Char(' ') => state.toggle(),
                KeyCode::Down | KeyCode::Char('j') => state.move_down(),
                KeyCode::Up | KeyCode::Char('k') => state.move_up(),
                _ => {}
            }
        }
    }

    ratatui::restore();
    Ok(())
}

fn render(f: &mut ratatui::Frame, state: &AppState) {
    let area = f.area();

    // Layout: header (3 lines) + list (dynamic) + footer (2 lines)
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3),  // header
            Constraint::Min(1),    // list
            Constraint::Length(2), // footer
        ])
        .split(area);

    // Header
    let header = Paragraph::new(vec![
        Line::from(vec![
            Span::styled(" claude-tools ignore ", theme::header()),
        ]),
        Line::from(vec![
            Span::styled(" ↑↓ ", theme::hint()),
            Span::raw("navigate  "),
            Span::styled("space ", theme::hint()),
            Span::raw("cycle  "),
            Span::styled("enter ", theme::hint()),
            Span::raw("apply  "),
            Span::styled("q ", theme::hint()),
            Span::raw("quit"),
        ]),
    ]).block(Block::default().borders(Borders::BOTTOM));
    f.render_widget(header, chunks[0]);

    // Legend + list
    let list_area = chunks[1];
    let mut lines: Vec<Line> = Vec::new();

    // Legend line
    lines.push(Line::from(vec![
        Span::styled("  [   ] ", Style::default().fg(theme::GRAY)),
        Span::raw("skip  "),
        Span::styled("[ G ] ", Style::default().fg(theme::YELLOW)),
        Span::raw("gitignore  "),
        Span::styled("[G+S] ", Style::default().fg(theme::GREEN)),
        Span::raw("gitignore + searchable"),
    ]));
    lines.push(Line::raw(""));

    // Scrolling: calculate visible window
    let visible_height = list_area.height.saturating_sub(3) as usize; // legend + blank
    let scroll_offset = if state.cursor > visible_height / 2 {
        state.cursor.saturating_sub(visible_height / 2)
    } else {
        0
    };

    for (i, item) in state.items.iter().enumerate().skip(scroll_offset).take(visible_height) {
        match item {
            ListItem::CategoryHeader { name, description } => {
                lines.push(Line::from(vec![
                    Span::styled(format!("  {} ", name), theme::header()),
                    Span::styled(format!("— {}", description), theme::hint()),
                ]));
            }
            ListItem::PatternRow { glob, description, state: pat_state, .. } => {
                let is_cursor = i == state.cursor;
                let (bracket_style, label) = match pat_state {
                    PatternState::Skip => (Style::default().fg(theme::GRAY), "   "),
                    PatternState::Gitignore => (Style::default().fg(theme::YELLOW), " G "),
                    PatternState::GitignoreSearchable => (Style::default().fg(theme::GREEN), "G+S"),
                };
                let cursor_char = if is_cursor { "❯" } else { " " };
                let cursor_style = if is_cursor { theme::cursor() } else { Style::default() };

                lines.push(Line::from(vec![
                    Span::styled(format!(" {} ", cursor_char), cursor_style),
                    Span::styled("[", bracket_style),
                    Span::styled(label, bracket_style),
                    Span::styled("] ", bracket_style),
                    Span::styled(format!("{:<24}", glob), if is_cursor { theme::cursor() } else { theme::unselected() }),
                    Span::styled(description.to_string(), theme::hint()),
                ]));
            }
        }
    }

    let list = Paragraph::new(lines);
    f.render_widget(list, list_area);

    // Footer: counts
    let footer = Paragraph::new(Line::from(vec![
        Span::styled(format!("  {} patterns → .gitignore", state.gitignore_count()), Style::default().fg(theme::YELLOW)),
        Span::raw("   "),
        Span::styled(format!("{} patterns → .ignore", state.ignore_count()), Style::default().fg(theme::GREEN)),
    ])).block(Block::default().borders(Borders::TOP));
    f.render_widget(footer, chunks[2]);
}
```

- [ ] **Step 3: Build and test TUI**

```bash
cd ~/code/dotfiles/tools/claude-tools && cargo build 2>&1
```

- [ ] **Step 4: Test TUI in a real repo**

```bash
cd ~/code/some-test-repo && claude-tools ignore apply
```

Expected: TUI shows with pattern categories, tri-state toggles work, enter applies, q quits.

- [ ] **Step 5: Test round-trip — apply, then re-open shows correct state**

```bash
cd ~/code/some-test-repo
claude-tools ignore apply          # select some patterns, enter
claude-tools ignore apply          # should show previous selections
claude-tools ignore status         # should show managed counts
```

- [ ] **Step 6: Test edge cases**

```bash
# Test in repo with no .gitignore
cd /tmp && mkdir test-ignore && cd test-ignore && git init
claude-tools ignore apply          # should create .gitignore with managed section

# Test dedup — add a pattern manually, then run apply
echo "data/" >> .gitignore
claude-tools ignore apply          # data/ should show warning, not duplicate
```

- [ ] **Step 7: Commit**

```bash
cd ~/code/dotfiles
git add tools/claude-tools/src/ignore/tui/
git commit -m "feat(claude-tools): add interactive TUI for ignore pattern management"
```

---

### Task 5: Build Release Binary and Integration Test

**Files:**
- Modify: (none — build + deploy)

- [ ] **Step 1: Build release binary**

```bash
cd ~/code/dotfiles/tools/claude-tools && cargo build --release 2>&1
```

- [ ] **Step 2: Copy to custom_bins**

```bash
cp tools/claude-tools/target/release/claude-tools custom_bins/claude-tools
```

- [ ] **Step 3: Verify subcommands work**

```bash
claude-tools ignore status
claude-tools ignore apply --dry-run --non-interactive
claude-tools ignore apply --help
```

- [ ] **Step 4: Full integration test — apply to a real repo**

```bash
cd ~/code/sandbagging-detection
claude-tools ignore apply
# Select: research patterns as G+S, python patterns as G
# Press enter
cat .gitignore | tail -20
cat .ignore
claude-tools ignore status
```

- [ ] **Step 5: Commit binary**

```bash
cd ~/code/dotfiles
git add custom_bins/claude-tools
git commit -m "build: update claude-tools binary with ignore subcommand"
```

---

### Task 6: Documentation Updates

**Files:**
- Modify: `CLAUDE.md` (already partially done in Task 1)
- Modify: `README.md`

- [ ] **Step 1: Add `claude-tools ignore` to CLAUDE.md cross-references or architecture**

Add after the existing `claude-tools` references in the architecture section, near the `tools/` tree:

```markdown
├── claude-tools/         # Rust binary (statusline, context, ignore)
```

- [ ] **Step 2: Add `claude-tools ignore` usage to README.md**

Find the section documenting `claude-tools` commands and add:

```markdown
### Ignore Pattern Management

`claude-tools ignore` manages per-repo `.gitignore` and `.ignore` patterns interactively.

```bash
claude-tools ignore                # Launch TUI (same as `ignore apply`)
claude-tools ignore apply          # Interactive pattern selection
claude-tools ignore apply --dry-run  # Preview without writing
claude-tools ignore status         # Show current managed patterns
```

The TUI shows patterns grouped by category with tri-state toggles:
- `[ ]` skip — pattern not applied
- `[G]` gitignore — added to `.gitignore` only
- `[G+S]` gitignore + searchable — added to `.gitignore` AND negated in `.ignore`

Patterns in `[G+S]` state are git-ignored but remain searchable by rg, fd, Claude Code, and Cursor.
```

- [ ] **Step 3: Commit docs**

```bash
cd ~/code/dotfiles
git add CLAUDE.md README.md
git commit -m "docs: add claude-tools ignore documentation"
```

---

## File Map Summary

| File | Action | Purpose |
|------|--------|---------|
| `config/ignore/gitignore_base` | Move from `config/ignore_global` | Universal patterns |
| `config/ignore/gitignore_research` | Move from `config/ignore_research` | Git-only research patterns |
| `config/ignore/patterns` | Create | TUI pattern definitions |
| `config/ignore_template` | Delete | Replaced by `patterns` |
| `scripts/shared/helpers.sh` | Modify (lines 982-999) | Update paths |
| `CLAUDE.md` | Modify (lines 136-138, 251-254, 382) | Update config tree |
| `tools/claude-tools/src/main.rs` | Modify | Add `ignore` subcommand |
| `tools/claude-tools/src/ignore/mod.rs` | Create | Module root, CLI, orchestration |
| `tools/claude-tools/src/ignore/patterns.rs` | Create | Pattern file parser |
| `tools/claude-tools/src/ignore/managed.rs` | Create | Managed section read/write/dedup |
| `tools/claude-tools/src/ignore/tui/mod.rs` | Create | TUI rendering and event loop |
| `tools/claude-tools/src/ignore/tui/state.rs` | Create | TUI state and tri-state toggle |
| `custom_bins/claude-tools` | Rebuild | Updated binary |
| `README.md` | Modify | Usage docs |
