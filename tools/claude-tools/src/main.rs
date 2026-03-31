mod check_git_root;
mod context;
mod context_apply;
mod resolve_file_path;
mod statusline;
mod usage;
mod util;

fn main() {
    let args: Vec<String> = std::env::args().collect();

    if args.len() < 2 {
        eprintln!("Usage: claude-tools <subcommand>");
        eprintln!("Subcommands: statusline, context, check-git-root, context-apply, resolve-file-path");
        std::process::exit(1);
    }

    let result = match args[1].as_str() {
        "statusline" => statusline::run(),
        "context" => {
            // Pass "claude-tools context" as argv[0] for clap, then remaining args
            let mut ctx_args = vec!["claude-tools-context".to_string()];
            ctx_args.extend_from_slice(&args[2..]);
            context::run(ctx_args)
        }
        "context-apply" => context_apply::run(), // Keep alias until Phase 6
        "check-git-root" => check_git_root::run(),
        "resolve-file-path" => resolve_file_path::run(),
        _ => {
            eprintln!("Unknown subcommand: {}", args[1]);
            std::process::exit(1);
        }
    };

    if let Err(e) = result {
        eprintln!("Error: {}", e);
        std::process::exit(1);
    }
}
