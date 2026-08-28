# Tooling, Packages & Operational Gotchas

Reference for how this repo installs tools, where it puts them, and the surprises that have actually bitten. Read this when a tool is missing, a version is wrong, a config edit doesn't take effect, or something works on one machine and not another. Pointed at from [`../CLAUDE.md`](../CLAUDE.md) under *Where to look*; the deploy-time view of the same machinery is in [`deploy-components.md`](deploy-components.md).

## Directory Environment Variables

`CODE_DIR`, `WRITING_DIR`, `SCRATCH_DIR`, `PROJECTS_DIR`, `DOT_DIR`, `DOTFILES_SECRETS_DIR` override the standard locations — defaults and the `code`/`writing`/`scratch`/`projects`/`dotfiles` aliases are defined in `config/zshrc.sh`. Override in `~/.zshenv`, which loads before zshrc.

Cloud and RunPod provisioning lives in [`deploy-components.md`](deploy-components.md) § Cloud Environments.

## CLI Tool Package Strategy

macOS uses Homebrew (ecosystem, GUI apps, libraries). Linux uses apt for the baseline plus the mise `github:` backend for modern versions of fast-moving CLI tools (fzf, bat, eza, fd, ripgrep, delta, dust, zoxide, jless, just, sd, duf, gum, vivid). apt packages are often years behind upstream; mise downloads release binaries from GitHub with version tracking (`mise upgrade --all`). Homebrew on Linux was rejected — too heavy, installs its own gcc/glibc. See `PACKAGES_CORE` (apt/brew), `PACKAGES_MACOS` (brew), `PACKAGES_LINUX_MISE` (mise) in `config.sh`.

**Node.js is the exception.** It is a global runtime (NodeSource `setup_lts.x` on Linux, brew on macOS), installed via `install_node` in `scripts/shared/helpers.sh`, **not** mise. Reason: tools shebang against `node` (e.g. obsidian-headless's `ob` → `#!/usr/bin/env node`), and systemd/cron can't see mise's shell-activated shims. It tracks the **current LTS line** (never an odd "Current" release); the skip-guard floor is the live latest-LTS major fetched from nodejs.org (never EOL — older node is converged up), so re-running `install.sh` after an LTS rollover force-upgrades the major and native modules must be rebuilt. `install_node` deliberately does **not** gate the `apt-get install` on the NodeSource script's exit code — it can exit non-zero after writing the repo, which once left a box on stock Ubuntu node 18.

bun stays the package manager/runtime for JS/TS; it is **not** a Node version manager and can't run direct-V8 native modules like better-sqlite3.

**min-release-age quarantine**: all package managers have a 7-day delay on new releases. Packages published <7 days ago will fail to install. This is intentional — see `claude/rules/safety.md` for the override syntax.

**`mas 7.0.0` requires sudo for every install** (`mas install`, `mas get`, `mas purchase`) and self-escalates by calling `sudo` internally. `install.sh --apps` pre-warms sudo with `sudo -v` (interactive TTY only) and keeps it alive with a background heartbeat for the duration of `brew bundle`, so a single password entry covers all mas apps. `mas account` was removed in 7.0.0 — there is no CLI way to confirm the signed-in store account (App Store UI only). The iCloud account and the Media & Purchases (store) account can differ; `mas` only cares about the store account.

## Symlink vs Copy vs Sourced

Getting this wrong is the most common cause of "I edited the config and nothing changed".

- **Symlinked** (edits are live): Finicky, Ghostty, Claude (`claude/` → `~/.claude/`), Codex (`codex/` → `~/.codex/`), Serena (`config/serena/serena_config.yml` → `~/.serena/serena_config.yml`), Zed, gitui, `~/.ignore_global`, `~/.config/fd/ignore`, and the matplotlib `.mplstyle` files.
- **Copied** (needs a re-deploy to take effect): git config, Mouseless, and the `lib/plotting/*.py` modules (`deploy.sh --matplotlib`).
- **Sourced by reference**: ZSH. `~/.zshrc` is a plain file containing only `source $DOT_DIR/config/zshrc.sh`, so edits to `config/zshrc.sh` in the main checkout are live in any new shell with no `deploy.sh` step.
- **Composed**: `~/.gitignore_global` is concatenated from `config/ignore/gitignore_base` + `config/ignore/gitignore_research`.

**Mouseless is copied, not symlinked**, because Mouseless uses an atomic `rename()` on UI save which destroys symlinks. Use `sync-mouseless` to pull UI changes back into dotfiles.

## Per-Tool Gotchas

- **macOS vs Linux paths**: the VSCode settings location differs by OS.
- **Conditional loading**: the ZSH config only sources tools if they exist (pyenv, micromamba, etc.).
- **Tmux environment pollution**: use the `tmux-clean` script to start with a minimal env.
- **TPM plugins**: guarded with `if-shell` so tmux works fine without TPM installed. Deploy auto-installs plugins to disk, but an already-running tmux needs `prefix + I` or a restart to load them. `prefix + Ctrl-s` saves a session, `prefix + Ctrl-r` restores. Continuum auto-restores the last saved session on the first server start after reboot; `touch ~/tmux_no_auto_restore` to suppress. Save files live in `~/.tmux/resurrect/` (portable, auto-cleaned after 30 days).
- **Ghostty** needs a reload (Cmd+Shift+Comma) after a config change.
- **Zed**: `ssh_connections` are machine-specific (added via the Zed UI; hosts come from `~/.ssh/config`).
- **Antigravity** is a VSCode fork by Google (`com.google.antigravity`). Same settings as Cursor, deployed via `--editor`. CLI at `/Applications/Antigravity.app/Contents/Resources/app/bin/antigravity`.
- **Secrets are per-project by design**: API keys require `setup-envrc` in each repo. Running `npm postinstall` or `pip install` in a project without `.envrc` cannot reach them — this is intentional supply-chain defense. Legacy `.secrets` / `.env` files may still exist locally but are no longer the intended runtime path.
- **Pueue + systemd slices**: the `j*` aliases need pueue plus a systemd user session. `systemd --user` does not work inside the Claude Code sandbox (bubblewrap blocks D-Bus) — test from a normal shell. Cgroup delegation may need a one-time `sudo systemctl set-property user-$(id -u).slice Delegate=yes`. Config in `config/resources.conf` (edit when scaling the machine).
- **Rust + bash dual implementations**: some tools have a Rust version (for speed) and a bash fallback, and the two must be kept in sync. Rust source is in `tools/claude-tools/src/`, bash in `claude/`. Recompile with `cd tools/claude-tools && cargo build --release && cp target/release/claude-tools ../../custom_bins/`. Current dual-impl tools: statusline (`statusline.rs` + `claude/statusline.sh`) and usage (`usage.rs` + inline in `statusline.sh`).

## Past Learnings

Older entries retired from `CLAUDE.md` § Learnings under the two-week pruning rule, kept because each one cost real debugging time.

- tmux-resurrect: auto-save is on (15 min), auto-restore is OFF. Use the `prefix+R` popup or the `tmux-restore` CLI to selectively restore windows from any save. Resurrect file format: `pane` lines ($2=session, $3=win_index, $8=path) + `window` lines ($2=session, $3=win_index, $7=win_name) (2026-04-05)
- fzf pre-selection in `setup-envrc` requires fzf 0.54+ (`--bind "load:pos(N)+select"`); multi-select pickers want `--bind 'space:toggle'`. apt's fzf (0.44) is too old; mise installs 0.71 on Linux, and macOS brew is fine. fzf is in both `PACKAGES_CORE` (apt baseline) and `PACKAGES_LINUX_MISE` (modern override) — mise's PATH takes precedence (2026-04-14)
- rust-skills plugin removed (2026-05-26). Its UserPromptSubmit matcher was hyper-broad ("error", "async", "API", "implement", "explain", "how to" — injecting ~100 lines on most prompts). Neutering it via a SessionStart hook didn't hold (it still fired the same session) and mutates a tracked file in the marketplace clone, which blocks future `git pull`. Re-add if Rust work picks up
- mas `install` vs `get`: `brew bundle` drives App Store installs via `mas install` (re-download only — it fails "Redownload Unavailable" on a new machine even for owned apps). `mas get` (= `mas purchase`) is acquire+install and actually works. Fixed by `custom_bins/mas-get`, called before `brew bundle` in install.sh. Ref: github.com/Homebrew/brew/issues/21559 (2026-06-20)
- Hourly checks: `usage-ping` warms the subscription 5-hour window (must run with `ANTHROPIC_API_KEY` unset so it uses OAuth, not the metered API — tested and confirmed 2026-06-21); `tmux-resume` auto-resumes rate-limited tmux Claude/Codex panes. Parser bug caught: `IFS='|' read` splits on `|` inside ERE patterns, garbling the send sequence — fixed to use ` | ` (space-pipe-space) as the field delimiter. Also: deploying `--only=usage-ping,tmux-resume` may race on Linux crontab since both run in parallel; install each setup script sequentially for guaranteed cron entries (2026-06-21)
