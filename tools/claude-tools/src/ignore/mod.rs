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
    let _ = non_interactive; // flag already handled by dispatch logic
    let dot_dir = find_dotfiles_dir()?;
    let patterns_path = format!("{}/config/ignore/patterns", dot_dir);
    let categories = patterns::parse_patterns_file(&patterns_path)?;

    let git_root = find_git_root()?;
    let gitignore_path = format!("{}/.gitignore", git_root);
    let ignore_path = format!("{}/.ignore", git_root);

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

pub fn print_summary(selections: &[(String, patterns::PatternState)]) {
    let gi_count = selections.iter()
        .filter(|(_, s)| matches!(s, patterns::PatternState::Gitignore | patterns::PatternState::GitignoreSearchable))
        .count();
    let ig_count = selections.iter()
        .filter(|(_, s)| matches!(s, patterns::PatternState::GitignoreSearchable))
        .count();
    println!("Applied: {} → .gitignore, {} → .ignore", gi_count, ig_count);
}

pub fn find_dotfiles_dir() -> Result<String, Box<dyn std::error::Error>> {
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

pub fn find_git_root() -> Result<String, Box<dyn std::error::Error>> {
    let repo = git2::Repository::discover(".")?;
    let workdir = repo.workdir()
        .ok_or("Not a git work tree")?;
    Ok(workdir.to_string_lossy().trim_end_matches('/').to_string())
}
