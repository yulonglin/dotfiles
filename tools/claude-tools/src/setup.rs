use std::process::Command;

#[derive(Debug)]
enum SetupAction {
    Secrets,
    Context,
    Auto,
}

/// Entry point called from main.rs.
pub fn run(args: Vec<String>) -> Result<(), Box<dyn std::error::Error>> {
    let action = if args.len() > 1 {
        match args[1].as_str() {
            "secrets" => SetupAction::Secrets,
            "context" => SetupAction::Context,
            _ => {
                eprintln!("Unknown setup subcommand: {}", args[1]);
                eprintln!("Usage: claude-tools setup [secrets|context]");
                std::process::exit(1);
            }
        }
    } else {
        SetupAction::Auto
    };

    match action {
        SetupAction::Secrets => run_secrets(&args[2..])?,
        SetupAction::Context => run_context(args)?,
        SetupAction::Auto => run_auto()?,
    }

    Ok(())
}

fn run_secrets(extra_args: &[String]) -> Result<(), Box<dyn std::error::Error>> {
    let mut cmd = Command::new("setup-envrc");
    cmd.args(extra_args);
    match cmd.status() {
        Ok(status) if !status.success() => std::process::exit(status.code().unwrap_or(1)),
        Ok(_) => Ok(()),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
            Err("setup-envrc not found in PATH. Ensure custom_bins/ is in your PATH.".into())
        }
        Err(e) => Err(e.into()),
    }
}

fn run_context(args: Vec<String>) -> Result<(), Box<dyn std::error::Error>> {
    // Rebuild args as if "claude-tools context" was called directly
    let mut ctx_args = vec!["claude-tools-context".to_string()];
    if args.len() > 2 {
        ctx_args.extend_from_slice(&args[2..]);
    }
    crate::context::run(ctx_args)
}

fn git_root() -> Option<std::path::PathBuf> {
    std::process::Command::new("git")
        .args(["rev-parse", "--show-toplevel"])
        .output()
        .ok()
        .filter(|o| o.status.success())
        .map(|o| std::path::PathBuf::from(String::from_utf8_lossy(&o.stdout).trim()))
}

fn run_auto() -> Result<(), Box<dyn std::error::Error>> {
    let root = git_root().ok_or("Not in a git repository. Run from a project directory.")?;
    let needs_secrets = !root.join(".envrc").exists();
    let needs_context = !root.join(".claude/context.yaml").exists();

    if !needs_secrets && !needs_context {
        eprintln!("✓ .envrc exists");
        eprintln!("✓ .claude/context.yaml exists");
        eprintln!("Nothing to set up. Use a specific subcommand to re-run (e.g. `setup secrets`).");
        return Ok(());
    }

    if needs_secrets {
        eprintln!("• secrets: .envrc not found — will run setup-envrc");
    } else {
        eprintln!("✓ .envrc exists (skipping secrets)");
    }

    if needs_context {
        eprintln!("• context: .claude/context.yaml not found — will launch context picker");
    } else {
        eprintln!("✓ .claude/context.yaml exists (skipping context)");
    }

    // Check if interactive (need TTY for both tools)
    if !std::io::IsTerminal::is_terminal(&std::io::stdin()) {
        eprintln!("\nNon-interactive terminal. Run specific subcommands instead:");
        if needs_secrets {
            eprintln!("  claude-tools setup secrets KEY1 KEY2");
        }
        if needs_context {
            eprintln!("  claude-tools setup context <profile>");
        }
        return Ok(());
    }

    eprintln!();

    // Run context first (faster, no external deps), then secrets
    if needs_context {
        eprintln!("── Setting up context profiles ──");
        run_context(vec!["claude-tools-setup".to_string(), "context".to_string()])?;
        eprintln!();
    }

    if needs_secrets {
        eprintln!("── Setting up secrets (.envrc) ──");
        run_secrets(&[])?;
    }

    Ok(())
}
