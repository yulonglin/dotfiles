/// Warn if CWD is not the git repository root.
/// Catches IDE integrations and direct `command claude` that bypass the wrapper.
/// Always succeeds (exit 0) — never blocks session start.
pub fn run() -> Result<(), Box<dyn std::error::Error>> {
    let cwd = std::env::current_dir()?;

    let repo = match git2::Repository::discover(&cwd) {
        Ok(r) => r,
        Err(_) => return Ok(()), // Not in a git repo
    };

    let workdir = match repo.workdir() {
        Some(w) => w,
        None => return Ok(()), // Bare repo
    };

    // Canonicalize both paths for reliable comparison
    let cwd_canonical = cwd.canonicalize().unwrap_or(cwd);
    let workdir_canonical = workdir
        .canonicalize()
        .unwrap_or_else(|_| workdir.to_path_buf());

    if cwd_canonical != workdir_canonical {
        eprintln!(
            "WARNING: CWD ({}) is not the git root ({})",
            cwd_canonical.display(),
            workdir_canonical.display()
        );
        eprintln!("Plans will be created in the wrong location.");
        eprintln!("Consider: cd {}", workdir_canonical.display());
    }

    Ok(())
}
