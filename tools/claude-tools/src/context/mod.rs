pub mod registry;
pub mod profiles;
pub mod builder;
pub mod settings;
pub mod sync;
pub mod display;
pub mod tui;

use clap::Parser;

// Shared path constants
pub const CONTEXT_FILE: &str = ".claude/context.yaml";
pub const TARGET_FILE: &str = ".claude/settings.json";
pub const INSTALLED_PLUGINS_PATH: &str = "~/.claude/plugins/installed_plugins.json";
pub const KNOWN_MARKETPLACES_PATH: &str = "~/.claude/plugins/known_marketplaces.json";
pub const MARKETPLACES_DIR: &str = "~/.claude/plugins/marketplaces";
pub const PROFILES_PATH: &str = "~/.claude/templates/contexts/profiles.yaml";
pub const GLOBAL_SETTINGS: &str = "~/.claude/settings.json";

#[derive(Parser, Debug)]
#[command(name = "context", about = "YAML-driven plugin profiles for Claude Code")]
pub struct ContextArgs {
    /// Profile names to apply
    #[arg()]
    pub profiles: Vec<String>,

    /// Show active plugins and available profiles
    #[arg(long)]
    pub list: bool,

    /// Remove project plugin config
    #[arg(long, alias = "reset")]
    pub clean: bool,

    /// Force --clean even on git-tracked files
    #[arg(long, short)]
    pub force: bool,

    /// Sync plugin marketplaces from profiles.yaml
    #[arg(long, alias = "sync-marketplaces")]
    pub sync: bool,

    /// Verbose output (for --sync)
    #[arg(short, long)]
    pub verbose: bool,

    /// Explicit non-interactive apply (for hooks)
    #[arg(long)]
    pub apply: bool,

    /// Force TUI even when not a TTY
    #[arg(long)]
    pub tui: bool,
}

/// Entry point called from main.rs. Parses remaining args via clap.
pub fn run(args: Vec<String>) -> Result<(), Box<dyn std::error::Error>> {
    let ctx_args = ContextArgs::parse_from(args);

    if ctx_args.sync {
        sync::run(ctx_args.verbose)?;
    } else if ctx_args.list {
        display::show_status()?;
    } else if ctx_args.clean {
        settings::reset(ctx_args.force)?;
    } else if !ctx_args.profiles.is_empty() {
        // Non-interactive apply with specified profiles
        let reg = registry::load_registry()?;
        let (base, profiles) = profiles::load_profiles()?;
        let enabled = builder::build_plugins(&reg, &base, &profiles, &ctx_args.profiles, &[], &[])?;
        settings::apply_to_settings(&enabled)?;
        settings::write_context_yaml(&ctx_args.profiles, &[], &[])?;
        display::print_apply_summary(&ctx_args.profiles, &enabled);
    } else if ctx_args.apply {
        // Explicit apply from context.yaml (hook path — keep lean)
        if let Some((pnames, enabled)) = settings::apply_from_context_yaml()? {
            display::print_applied_context(&pnames, &enabled);
        }
    } else if ctx_args.tui || std::io::IsTerminal::is_terminal(&std::io::stdout()) {
        // Interactive TUI
        tui::run()?;
    } else {
        // No TTY, no args: apply context.yaml if present, then show status
        let _ = settings::apply_from_context_yaml();
        display::show_status()?;
    }

    Ok(())
}
