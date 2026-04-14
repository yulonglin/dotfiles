# `claude-tools setup` Unified Setup Command

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `setup` subcommand to `claude-tools` that unifies repo initialization — secrets (`.envrc`) and plugin context (`.claude/context.yaml`) — behind a single entry point with auto-detection.

**Architecture:** Thin Rust dispatcher (~80 lines in a new `setup` module). `setup secrets` shells out to `setup-envrc` (bash stays bash). `setup context` delegates to existing `context::run()`. Bare `setup` auto-detects what's needed, shows a summary, confirms, then runs each step. Existing `claude-tools context` remains unchanged (backwards compat).

**Tech Stack:** Rust (clap for arg parsing, std::process::Command for shell-out), Bash (existing setup-envrc)

---

### Task 1: Add `setup` Module with Subcommand Routing

**Files:**
- Create: `tools/claude-tools/src/setup.rs`
- Modify: `tools/claude-tools/src/main.rs:1-45`

- [ ] **Step 1: Create `setup.rs` with clap subcommand enum and dispatch**

```rust
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
```

- [ ] **Step 2: Wire `setup` into `main.rs`**

Add `mod setup;` to the module declarations at the top of `main.rs`, and add the match arm:

```rust
// In main.rs, add to mod declarations:
mod setup;

// In the match block, add before the wildcard:
"setup" => {
    let mut setup_args = vec!["claude-tools-setup".to_string()];
    setup_args.extend_from_slice(&args[2..]);
    setup::run(setup_args)
}
```

Also update the usage line to include `setup`:
```
eprintln!("Subcommands: statusline, timezone, context, ignore, check-git-root, resolve-file-path, setup");
```

- [ ] **Step 3: Build and verify it compiles**

Run:
```bash
cd tools/claude-tools && cargo build --release 2>&1
```
Expected: successful compilation, no errors.

- [ ] **Step 4: Test each subcommand path**

Run from any repo:
```bash
# Test help/unknown
./target/release/claude-tools setup unknown 2>&1
# Expected: "Unknown setup subcommand: unknown" + usage

# Test setup secrets --list (non-destructive, just delegates)
./target/release/claude-tools setup secrets --list 2>&1

# Test setup context --list (delegates to existing context module)
./target/release/claude-tools setup context --list 2>&1

# Test auto-detect (bare setup)
./target/release/claude-tools setup 2>&1
# Expected: shows which steps are needed based on file existence
```

- [ ] **Step 5: Copy binary to custom_bins and commit**

```bash
cp tools/claude-tools/target/release/claude-tools custom_bins/claude-tools
git add tools/claude-tools/src/setup.rs tools/claude-tools/src/main.rs custom_bins/claude-tools
git commit -m "feat: add claude-tools setup subcommand (secrets + context dispatcher)"
```

---

### Task 2: Fix `setup-envrc` Bugs Found by Review

**Files:**
- Modify: `custom_bins/setup-envrc`

These are real bugs caught during the design review. Fix them while we're touching this file.

- [ ] **Step 1: Fix `local` keyword used outside function scope**

Search for `local preview_dotenv preview_meta` — this was already partially fixed during the merge conflict resolution (the `local` was removed). Verify it's gone:

```bash
grep -n '^[[:space:]]*local ' custom_bins/setup-envrc
```

If any `local` declarations exist outside a function body, remove the `local` keyword (they become script-global, which is fine for a standalone script).

- [ ] **Step 2: Fix unbounded `find` in `find_env_files()`**

Find the `find_env_files` function and add `-maxdepth 3` to prevent traversing deep node_modules or vendor trees:

```bash
# Before:
find "$REPO_ROOT" -name '.env' -o -name '.env.*' ...

# After:
find "$REPO_ROOT" -maxdepth 3 -name '.env' -o -name '.env.*' ...
```

- [ ] **Step 3: Verify `mktemp` uses `$TMPDIR`**

Confirm the merge resolution already uses `$TMPDIR`:
```bash
grep -n 'mktemp' custom_bins/setup-envrc
```

All `mktemp` calls should use `mktemp "$TMPDIR/setup-envrc.XXXXXX"` (already fixed in conflict resolution).

- [ ] **Step 4: Run shellcheck**

```bash
shellcheck custom_bins/setup-envrc
```

Fix any new warnings introduced.

- [ ] **Step 5: Commit fixes**

```bash
git add custom_bins/setup-envrc
git commit -m "fix: setup-envrc unbounded find, local outside function, TMPDIR for mktemp"
```

---

### Task 3: Update Documentation

**Files:**
- Modify: `CLAUDE.md` (Deployment Components section + Architecture section)
- Modify: `claude/CLAUDE.md` (Plugin Organization & Context Profiles section)

- [ ] **Step 1: Add `setup` to CLAUDE.md deployment components**

In the `### Deployment Components` section of `CLAUDE.md`, the `claude-tools` entry should mention `setup`:

```markdown
# In the Architecture > Core Scripts or cross-reference area, add:
- `claude-tools setup` — unified repo initialization (secrets + context profiles)
  - `setup secrets` — delegates to `setup-envrc` (bash)
  - `setup context` — delegates to `context` subcommand (Rust)
  - bare `setup` — auto-detects missing `.envrc` / `.claude/context.yaml`
```

- [ ] **Step 2: Update `claude/CLAUDE.md` context profiles section**

Add `claude-tools setup` to the context profiles code block:

```markdown
claude-tools setup                      # Auto-detect + run needed setup steps
claude-tools setup secrets              # Interactive secret picker (setup-envrc)
claude-tools setup context              # Plugin profile picker (same as `context`)
```

- [ ] **Step 3: Commit docs**

```bash
git add CLAUDE.md claude/CLAUDE.md
git commit -m "docs: document claude-tools setup command"
```

---

### Task 4: Push and Verify End-to-End

- [ ] **Step 1: Run full verification**

```bash
# Build fresh
cd tools/claude-tools && cargo build --release 2>&1

# Copy binary
cp target/release/claude-tools ../../custom_bins/claude-tools

# Test from a repo that has both .envrc and context.yaml (dotfiles itself)
cd ../..
./custom_bins/claude-tools setup 2>&1
# Expected: "✓ .envrc exists" / "✓ .claude/context.yaml exists" / "Nothing to set up"

# Test from a repo without .envrc
cd /tmp && mkdir -p test-setup && cd test-setup && git init
/Users/yulong/code/dotfiles/custom_bins/claude-tools setup 2>&1
# Expected: "• secrets: .envrc not found" message
rm -rf /tmp/test-setup

# Verify context still works independently
cd /Users/yulong/code/dotfiles
./custom_bins/claude-tools context --list 2>&1
```

- [ ] **Step 2: Push**

```bash
git push
```
