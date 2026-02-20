mod check_git_root;
mod context_apply;
mod resolve_file_path;
mod statusline;

fn main() {
    let args: Vec<String> = std::env::args().collect();

    if args.len() < 2 {
        eprintln!("Usage: claude-tools <subcommand>");
        eprintln!("Subcommands: statusline, check-git-root, context-apply, resolve-file-path");
        std::process::exit(1);
    }

    let result = match args[1].as_str() {
        "statusline" => statusline::run(),
        "check-git-root" => check_git_root::run(),
        "context-apply" => context_apply::run(),
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
