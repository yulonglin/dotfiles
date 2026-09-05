# Deployment Components

Reference for every component `deploy.sh` deploys, with the non-obvious rationale for each. Read this when adding, debugging, or disabling a deploy component; the full mechanics live in the matching `deploy_*()` function in [`../deploy.sh`](../deploy.sh).

Per-component subtleties are tabulated under [Per-Component Behaviors](#per-component-behaviors) below. Two of them — the Obsidian manual-promotion rule and the per-project secrets model — stay inline in [`../CLAUDE.md`](../CLAUDE.md) because getting them wrong destroys data.

Each component in `deploy.sh` is deployed with inline logic or helper functions:

- ZSH configuration - Main shell setup
- Tmux configuration - Shell multiplexer config + TPM plugins (resurrect, continuum) for session persistence
- Gist sync - Bidirectional sync of SSH config and git identity with GitHub gist, automated daily at 8 AM
- Git config - Smart conflict resolution with user prompts
- VSCode/Cursor/Antigravity settings - Merges with existing settings
- Finicky - Browser routing (macOS only, symlinked)
- Ghostty - Terminal emulator configuration (symlinked to platform-specific path)
- Zed - Editor config (settings + keymap, symlinked to ~/.config/zed/)
- gitui - Theme (symlinked to ~/.config/gitui/theme.ron). Theme-reactive: uses named ANSI colors so gitui inherits whichever Ghostty theme the active window uses (default, g0-g9, SSH themes). Fixes gitui's default `disabled_fg: DarkGray`, which is unreadable on Catppuccin Mocha and similar dark backgrounds.
- Claude Code - AI assistant configuration (symlinked)
- Codex - CLI tool configuration (symlinked)
- Serena - MCP server configuration (symlinked, dashboard auto-open disabled)
- Mouseless - Keyboard-driven mouse control (macOS only, copied not symlinked)
- Alfred prefs repair - Fixes Dropbox-synced Alfred breakage (macOS only): strips `com.apple.quarantine` xattrs that block workflow scripts (`posix_spawn: error 1`), restores lost script `+x` bits, and seeds the per-machine summon hotkey from a golden snapshot. Runs `custom_bins/alfred-fix`; capture a new golden hotkey with `alfred-fix --capture`. Clipboard history is intentionally local-only and never syncs (Alfred design) — it starts fresh on each machine.
- Bear CLI symlink - `/Applications/Bear.app/Contents/MacOS/bearcli` → `/usr/local/bin/bearcli` (macOS only, so `bearcli` works in cron/scripts where shell aliases don't apply)
- Text replacements - Bidirectional sync with macOS + Alfred snippets (daily 9 AM, requires Full Disk Access for terminal app). macOS uses raw shortcuts; Alfred applies collection prefix at runtime (e.g., `fm.hi`)
- Encrypted secrets (BWS) - Stores API keys via Bitwarden Secrets Manager. Run `secrets init` to configure.
- File cleanup - Downloads/Screenshots cleanup (macOS only, launchd)
- Claude Code cleanup - No-output-for-24h session cleanup (tmux preserved, launchd/cron)
- Claude plugin-cache cleanup - Daily 3 AM `claude-cache-clean --apply` (launchd/cron). Reaps superseded plugin versions and the abandoned `cache/temp_git_*` clones that plugin install/update leaves behind (~6MB/day combined). Scheduled via `scripts/cleanup/setup_cache_clean.sh`, gated by `--claude-cleanup`; disable with `setup_cache_clean.sh --uninstall`. The `custom_bins/claude-cache-clean-apply` wrapper exists because `schedule_daily` embeds its command as a single launchd `ProgramArguments` string, so a command with arguments can't be scheduled directly on macOS; it resolves `DOT_DIR` via `realpath "$0"` so it stays machine-portable
- AI tools auto-update - Daily update of Claude Code, Codex CLI, OpenCode, Antigravity CLI (6 AM, launchd/cron)
- Usage ping - Hourly minimal Haiku message (subscription/OAuth only, API key unset) to keep the Claude 5-hour usage window warm so capacity isn't wasted. `custom_bins/usage-ping`, scheduled at :00 (launchd/cron). Toggle with `--no-usage-ping`.
- Tmux resume - Hourly scan of all tmux panes; on a rate-limit prompt (Claude Code / Codex) sends configured keystrokes to resume. Detection anchors on durable rate-limit-state strings; the action (default `1 Enter ; continue`) is the fragile part — re-verify with `tmux-resume --dry-run` after CLI upgrades. Patterns in `config/tmux-resume-patterns.conf`. Scheduled at :05. Toggle with `--no-tmux-resume`.
- Hide idle apps (macOS only, **off by default** — enable with `--hide-idle-apps`) - Polls every 60s and walks each covered-up app along a three-rung ladder: hide → close windows → quit (defaults 15 / 15 / 30 minutes), with the two destructive rungs gated on the machine being idle. Per-app policy in `config/app-lifecycle.yaml` (`manual:` for the Shortcut, `auto:` for this job; it replaced `config/clear_mac_apps.conf`), poll interval in `config/hide-idle.conf`. `clear-mac-apps` is the manual trigger and the shared escalation path; it reports a failed action two ways, because its two callers can use only one each — a non-zero exit for the idle job (which always passes `--only` and gives the rung back on it), and a **notification** naming the rung and app for a bare run, since that is the macOS Shortcut and "Run Shell Script" would turn any non-zero status into an error dialog. Calibrate with `hide-idle-apps --dry-run`. Mechanics, config reference, and known limits: [`docs/hide-idle-apps.md`](hide-idle-apps.md)
- Developer config files - EditorConfig, curlrc, inputrc, .hushlogin (deployed with --editor flag)
- Global gitattributes - Binary file handling + line endings (deployed with --git-config flag)
- File associations - Set default editor for coding file types and default terminal for `.command`/`.tool` (macOS only, reads `config/macos_default_apps.conf`)
- Pueue + resource slices - Local job queue with cgroup-enforced CPU/memory limits (Linux only, systemd user slices, `j*` aliases)
- Package auto-update - Weekly upgrade + cleanup (Sunday 5 AM, launchd/cron). `custom_bins/update-packages` runs brew wherever it exists (macOS Homebrew or Linuxbrew) and then the system manager on Linux (apt/dnf/pacman), so a Linux box with brew CLI tools gets both upgraded in one pass
- Package manager configs - Global npmrc, bunfig.toml, pnpm rc, uv.toml with 7-day min-release-age + ignore-scripts (symlinked)
- Dependency audit - Weekly scan for known-bad packages across all repos (Sunday 10 AM, launchd/cron)

## Per-Component Behaviors

Subtleties worth knowing per component. Full mechanics live in the matching `deploy_*()` function in [`../deploy.sh`](../deploy.sh).

| Component | Mechanism | Key gotcha |
|-----------|-----------|------------|
| **Dotfiles Sync** (`dotfiles-sync` scheduled job) | `custom_bins/dotfiles-sync` commits the dirty tree as `sync: <host> <utc>` through the pre-commit hook, rebases onto `origin/<branch>`, pushes. Daily 08:05 via `scripts/cleanup/setup_dotfiles_sync.sh` (launchd/cron, same scheduler as gist sync), covering this repo plus `~/code/dotfiles-personal` when present. Outcome per repo in `~/.local/state/dotfiles-sync/<repo>.json`; `nudge_dotfiles_sync.sh` surfaces failures at session start, macOS also gets a notification. | Never `--no-verify`, never `--force`: a conflicting rebase is aborted and left for a human. When the pre-commit gateway guard rejects `claude/settings.json`, that file alone is held back and the rest ships, so the machine-local gateway diff never blocks the sync. Does NOT run `deploy.sh` after a pull (the nudge says when to). The same installer schedules `dotfiles-prune` (`dotfiles-sync --prune`) Sundays 08:15: removes `<repo>/.claude/worktrees/*` whose branch has no commits beyond the checked-out branch, `branch -d` those and merged orphan branches, `remote prune`; dirty, locked, tmux-attached and unmerged worktrees are kept, and unmerged ones past `DOTFILES_SYNC_STALE_DAYS` (14) are listed for the nudge. Never `--force`, never `-D`. Test: `tests/test_dotfiles_sync.sh`. |
| **Gist Sync** (`deploy_secrets`) | Bidirectional sync of `~/.ssh/config`, `authorized_keys`, `config/user.conf` with gist `3cc239...371`. `authorized_keys` uses **disable-wins union merge** (local is always the canonical base; whole-line-commented keys are tombstones that suppress that key everywhere even if the gist still lists it active); `~/.ssh/config` and `user.conf` use last-modified-wins. Daily 8 AM (launchd/cron). | Requires `gh auth login`. Manual: `sync-gist`. Runs before git config (user.conf provides identity). Merge logic in `scripts/shared/merge_authorized_keys.py`; active convention `<type> <blob> [## note]`, disable convention `# <type> <blob>` under `# --- Disabled / pending deletion ---`. |
| **Git Config** (`deploy_git_config`) | Reads `config/user.conf`; prompts on conflicts. Deploys split ignores: `~/.gitignore_global` (git, broad), `~/.ignore_global` (ripgrep, narrow), `~/.config/fd/ignore` (fd). Result: git ignores `data/`/`archive/`, but search tools can still see them. | `fd` has no `--no-ignore-global` flag — use `fd -I` to traverse research dirs. |
| **Editor Settings** (`deploy_editor_settings`) | Merges into VSCode/Cursor/Antigravity settings (no overwrite, existing wins). Auto-installs 38 curated extensions from `vscode_extensions.txt`. | Antigravity CLI at `/Applications/Antigravity.app/Contents/Resources/app/bin/antigravity`. |
| **Zed** | Symlinks `config/zed/{settings,keymap}.json` → `~/.config/zed/`. Searches gitignored files by default. | SSH hosts read from `~/.ssh/config` (gist-synced). Cmd+K overrides Zed's chord prefix → inline AI edit. |
| **Finicky, Ghostty** | Symlinked to fixed paths (the Ghostty path is platform-specific). Existing files backed up with a timestamp. | Ghostty needs a reload (Cmd+Shift+Comma) after a config change. |
| **Playwright** (`--playwright`) | **Off by default.** Installs the `playwright` CLI via `uv tool` and fetches Chromium into the shared `~/.cache/ms-playwright` (honouring `PLAYWRIGHT_BROWSERS_PATH` when set). | ~650MB, so it is opt-in rather than part of any profile. Browser builds are keyed to the package version — the component runs the CLI's own `playwright install` so the two cannot drift. On Linux the system libraries may still need `sudo playwright install-deps chromium`. |
| **Plotting + matplotlib** (`--matplotlib`) | **Copies** Python modules to `~/.local/lib/plotting/` (isolation); **symlinks** `.mplstyle` files to `~/.config/matplotlib/stylelib/` (live updates). PYTHONPATH set in zshrc. | Python module updates require re-running `deploy.sh --matplotlib`. Default style: `anthropic`. |
| **File Associations** (`--file-apps`) | Reads `config/macos_default_apps.conf`, compiles `tools/set-default-app/main.swift` (cached), calls the deprecated `LSSetDefaultRoleHandlerForContentType` (still works on Sequoia). The same conf drives `$EDITOR`/`$VISUAL`. | macOS only. Linux would need `xdg-mime` (not implemented). |
| **Claude Code** (smart merge) | Symlinks `claude/` → `~/.claude/`. If `~/.claude/` predates dotfiles it is backed up to `~/.claude.backup.<ts>`, then runtime files are restored: `.credentials.json`, `history.jsonl`, `cache/`, `projects/`, `plans/`, `todos/`, `mcp_servers.json`. | Works whether `install.sh` or `deploy.sh` runs first. |

## Cloud Environments

The standard directory structure works transparently on RunPod/cloud via symlinks created by `scripts/cloud/setup.sh`. `setup.sh` runs the lean **`cloud` profile** (`install.sh --profile=cloud` / `deploy.sh --profile=cloud`) — `server` minus pueue, zotero MCP, Rust extras, and Docker; it keeps the modern CLI tools, uv, gh, claude, and codex.

It provisions the **`main` branch by default**; pin another with `--branch <name>` (env `DOTFILES_BRANCH`), e.g. `curl … | bash -s -- --branch yulong`. `setup.sh` is **always fetched from `main`** (one canonical bootstrap URL); `--branch` only chooses which branch is cloned on the box. `provision.py --branch yulong` likewise fetches `setup.sh` from main and passes `--branch yulong` through to the clone. The active branch is printed in the setup banner.

gh is installed current (Linux: the official `cli.github.com` apt repo with sudo, else a release binary), not jammy's 2.4.0, so `gh auth login --git-protocol ssh` works.

## Extending

**New alias** — general ones go in the matching themed split in `config/aliases/<topic>.sh` (sourced by `zshrc.sh`'s `aliases/*.sh` loop); environment-specific ones go in `config/aliases_<name>.sh` and deploy with `./deploy.sh --aliases=<name>`.

**New dependency** — add to `install.sh` with OS detection (`is_macos`/`is_linux`), and add a feature flag if it is optional (e.g. `--extras`, `--experimental`). Update the defaults at the top of `install.sh` if it should be included by default.

**New deployment component** — create a `deploy_X()` function in `deploy.sh`, add flag parsing in the `while` loop, call the function in the appropriate section (symlink/copy/append), then update the help text and defaults.

**New custom binary** — add the script to `custom_bins/` (automatically on PATH) and `chmod +x` it.

**Code style** — 2-space indentation in shell scripts; use the `backup_file()` helper for anything destructive. General language conventions live in `~/.claude/rules/coding-conventions.md`.
