# CLAUDE.md

Project-specific guidance for Claude Code when working with the dotfiles repository.

## Project Overview

Comprehensive dotfiles repository for ZSH, Tmux, Vim, SSH, and development tools. Works across macOS, Linux, and RunPod containers. Uses oh-my-zsh with powerlevel10k theme.

## AI Agent Quick Reference

If you're an AI agent (Claude Code, Codex, etc.) working in this repo, read this first.

**What this repo is:** dotfiles deployed via `install.sh` + `deploy.sh`. `claude/` is symlinked to `~/.claude/` and `codex/` to `~/.codex/` — edits here affect your *running* environment immediately.

**Top rules:**
- **Direct pushes to main are allowed** — personal repo, no PR overhead. Use `cwmerge` from worktrees (note: `cwmerge` only recognises branches with the `worktree-` prefix; for branches like `claude/<name>` merge manually with `git -C <main-tree> merge --ff-only <branch>`).
- **Flags are ADDITIVE** to defaults unless `--minimal` is used. See [Flag Behavior](#flag-behavior-critical).
- **Sandbox blocks `git pull/merge/stash`** on `config/` and `claude/settings.json` even though git is in `excludedCommands` — pass `dangerouslyDisableSandbox: true`. Also in global `~/.claude/rules/safety-and-git.md`.
- **`codex exec` crashes inside sandbox on macOS** (`SCDynamicStoreCreate NULL` panic). Same workaround. Also in global `~/.claude/rules/agents-and-delegation.md`.
- **`claude/settings.json` is the global source of truth** (symlinked to `~/.claude/settings.json`). Before staging it, verify it has `statusLine`, `hooks`, `permissions` keys — see [`.claude/rules/dotfiles-settings.md`](.claude/rules/dotfiles-settings.md).
- **Secrets are NOT globally exported** (supply chain defense). Use `setup-envrc` per-project via direnv. Edit secrets via `secrets-edit`.
- **Plot with Anthropic style by default** — `from anthro_colors import use_anthropic_defaults`. See [Plotting with Anthropic Style](#plotting-with-anthropic-style).

**Common tasks:**

| Want to... | Command / file |
|---|---|
| Add a new alias | `config/aliases/<theme>.sh` (or `aliases_<name>.sh` for env-specific) |
| Add a deploy component | Create `deploy_X()` in `deploy.sh` — see [Adding New Features](#adding-new-features) |
| Add a custom binary | Drop it in `custom_bins/` (already on PATH); `chmod +x` |
| Install/manage Mac apps | Add a line to `config/apps.conf` → run `app-picker` (gum TUI) → `brew bundle --file=config/Brewfile`. Official casks + `mas` only, **no third-party taps**. Then `scripts/setup/auth-setup` |
| Add an encrypted secret | `secrets-edit` (interactive dotenv editor) |
| Run an experiment with resource caps | `jexp uv run python -m ...` (Linux: needs pueue + systemd user session) |
| Commit / commit + push + PR | `/commit` skill or `/commit-push-sync` |
| Switch active plugin context | `claude-tools context <profile>` (composable: `code python frontend`) |
| Merge worktree → parent branch | `cwmerge` (or `git merge <branch>` from parent if branch isn't `worktree-` prefixed) |
| Pre-deploy verification | See [Claude Code Verification Planning](#claude-code-verification-planning) |

**Where to look:**
- Operational gotchas / surprises → [Important Gotchas](#important-gotchas)
- File layout reference → [Configuration Structure](#configuration-structure)
- Per-deploy behavior → [Important Behaviors](#important-behaviors)
- Global behavioral rules → `~/.claude/rules/*.md`
- This repo's project rules → `.claude/rules/*.md`

## Key Conventions

### Flag Behavior (Critical)

**Flags are ADDITIVE to defaults unless `--minimal` is used**

- `install.sh` defaults: all components enabled (use `--no-<component>` to disable)
- `deploy.sh` defaults: all components enabled (use `--no-<component>` to disable)
- Adding flags extends defaults; `--no-<component>` disables specific ones
- `--minimal` flag disables all defaults (only installs what you specify)
- Modifiers (`--append`, `--ascii`, `--force`) don't affect defaults

See README.md for detailed usage.

### Spec and Plan Locations

- **Specs** go in `specs/`, not `docs/superpowers/specs/` (overrides brainstorming skill default)
- **Plans** go in `plans/` (via `plansDirectory` setting)

### Git Workflow

- **Direct pushes to main are allowed** - no PR required for this personal repo
- **Two long-lived branches** (see [Branching Strategy](#branching-strategy) below):
  `main` is the clean, public-facing branch; `yulong` is the personal superset
  (everything on `main` **plus** personal working content).

### Branching Strategy

The repo is public-ish (people star it), so `main` stays clean while personal
working artifacts live on a superset branch.

| Branch | Contents | Role |
|--------|----------|------|
| `main` | Shareable dotfiles only | Public-facing. What people clone/star. |
| `yulong` | `main` **+** personal content (`plans/`, `specs/`, `.remember/`, `tmp/`, personal `docs/`, `config/machines.conf`) | Where Yulong actually develops. Strict superset of `main`. |

**Why it doesn't explode:** `yulong` is built as `main` **+ one "restore personal
files" commit** (the personal files are force-added on top of an already-clean
tree). Because the *removal* of those files lives in the shared merge-base of both
branches, neither `git merge main` nor `git rebase main` into `yulong` will ever
delete your personal files. The personal paths are also in `.gitignore`, so they
can't accidentally re-enter `main` as untracked adds.

**The one rule:** never merge `yulong → main` wholesale — that re-adds personal
files. To publish shared work, do one of:
- Develop the shared change directly on `main` (or a branch off `main`), then
  `git checkout yulong && git rebase main` (or `git merge main`) to pull it into `yulong`.
- Or develop on `yulong` and `git cherry-pick <sha>` the shareable commits onto `main`.
  (Cherry-pick is clean because shared changes never touch the personal paths.)

**Adding personal content on `yulong`:** the personal paths are gitignored, so use
`git add -f <path>` to track them on `yulong`.

### Worktree Workflow

`yolo` works as before (skip permissions, no worktree). Use `cw`/`cwy` for isolated worktree sessions.

| Command | What it does |
|---------|-------------|
| `yolo` | Skip permissions (no worktree, no tmux) |
| `cw [name]` | Worktree + tmux (with permission prompts) |
| `cwy [name]` | Worktree + tmux + skip permissions |
| `cwl` | List all worktrees |
| `cwmerge [name]` | Merge worktree branch into parent (auto-detects from inside worktree) |
| `/merge-worktree` | Claude skill: merge + AI conflict resolution |
| `cwport <name> [dirs...]` | Copy artifacts (out/, logs/, etc.) from worktree to main tree |
| `cwrm [--no-merge] <name>` | Merge branch → remove worktree → delete branch |
| `cwclean [--dry-run]` | Remove clean worktrees (no changes, no artifacts) |

**`cwrm` merges by default** — the worktree branch is merged into your current branch before removal. Use `--no-merge` to skip. `--force` skips artifact warnings.

**Gitignored files** (.env, out/, logs/) do NOT exist in new worktrees. Each worktree starts clean with only tracked files.

**Artifact lifecycle**: `cw auth-fix` → work → `cwport auth-fix` → `cwrm auth-fix`

### Claude Code Verification Planning

**Use EnterPlanMode for verification activities, not just implementation:**

Verification is a design problem—you need to plan *how* you'll verify before you start verifying.

| Activity | Trigger EnterPlanMode | Why |
|----------|----------------------|-----|
| Implementing a feature | ✅ Yes | Need to decide implementation approach |
| Verifying it works | ✅ Yes | Need to decide validation strategy |
| Running an experiment | ✅ Yes | Need to plan test design |
| Analyzing results | ✅ Yes | Need to plan statistical approach |
| Fixing a bug | ✅ Yes | Need to decide debugging strategy |
| Confirming the fix | ✅ Yes | Need to plan regression/validation testing |

**Verification activities that need planning:**
- Reproducibility checks (rerun, validate numbers match, check for hidden bugs)
- Data validation (schema checks, contamination detection, canary verification)
- Statistical analysis (which metrics, confidence intervals, significance tests, N requirements)
- Integration testing (which scenarios to cover, edge cases)
- Error handling (what could break, how to test failures)
- Regression testing (what could be affected by this change)

**Red flag**: If you think "let me figure out how to verify this," that's EnterPlanMode.

### Deployment Components

Each component in `deploy.sh` is deployed with inline logic or helper functions:
- ZSH configuration - Main shell setup
- Tmux configuration - Shell multiplexer config + TPM plugins (resurrect, continuum) for session persistence
- Gist sync - Bidirectional sync of SSH config and git identity with GitHub gist, automated daily at 8 AM
- Git config - Smart conflict resolution with user prompts
- VSCode/Cursor/Antigravity settings - Merges with existing settings
- Finicky - Browser routing (macOS only, symlinked)
- Ghostty - Terminal emulator configuration (symlinked to platform-specific path)
- Zed - Editor config (settings + keymap, symlinked to ~/.config/zed/)
- Claude Code - AI assistant configuration (symlinked)
- Codex - CLI tool configuration (symlinked)
- Serena - MCP server configuration (symlinked, dashboard auto-open disabled)
- Mouseless - Keyboard-driven mouse control (macOS only, copied not symlinked)
- Alfred prefs repair - Fixes Dropbox-synced Alfred breakage (macOS only): strips `com.apple.quarantine` xattrs that block workflow scripts (`posix_spawn: error 1`), restores lost script `+x` bits, and seeds the per-machine summon hotkey from a golden snapshot. Runs `custom_bins/alfred-fix`; capture a new golden hotkey with `alfred-fix --capture`. Clipboard history is intentionally local-only and never syncs (Alfred design) — it starts fresh on each machine.
- Bear CLI symlink - `/Applications/Bear.app/Contents/MacOS/bearcli` → `/usr/local/bin/bearcli` (macOS only, so `bearcli` works in cron/scripts where shell aliases don't apply)
- Text replacements - Bidirectional sync with macOS + Alfred snippets (daily 9 AM, requires Full Disk Access for terminal app). macOS uses raw shortcuts; Alfred applies collection prefix at runtime (e.g., `fm.hi`)
- Encrypted secrets (BWS) - Stores API keys via Bitwarden Secrets Manager. Run `secrets-init bws` to configure.
- File cleanup - Downloads/Screenshots cleanup (macOS only, launchd)
- Claude Code cleanup - No-output-for-24h session cleanup (tmux preserved, launchd/cron)
- AI tools auto-update - Daily update of Claude Code, Codex CLI, OpenCode, Antigravity CLI (6 AM, launchd/cron)
- Developer config files - EditorConfig, curlrc, inputrc, .hushlogin (deployed with --editor flag)
- Global gitattributes - Binary file handling + line endings (deployed with --git-config flag)
- File associations - Set default editor for coding file types and default terminal for `.command`/`.tool` (macOS only, reads `config/macos_default_apps.conf`)
- Pueue + resource slices - Local job queue with cgroup-enforced CPU/memory limits (Linux only, systemd user slices, `j*` aliases)
- Package auto-update - Weekly upgrade + cleanup (Sunday 5 AM, brew/apt/dnf/pacman, launchd/cron)
- Package manager configs - Global npmrc, bunfig.toml, pnpm rc, uv.toml with 7-day min-release-age + ignore-scripts (symlinked)
- Dependency audit - Weekly scan for known-bad packages across all repos (Sunday 10 AM, launchd/cron)

## Architecture

### Core Scripts

- `install.sh` - Dependency installation (OS-specific, uses feature flags)
- `deploy.sh` - Configuration deployment (uses helper functions, supports --append/--backup)
- `config/macos_settings.sh` - macOS system defaults (run automatically on macOS)
- `scripts/cleanup/` - Automatic cleanup system (launchd/cron scheduled jobs)
- `scripts/security/` - Supply chain defense (dependency audit, known-bad package IOC registry)

### Configuration Structure

```
config/
├── zshrc.sh              # Main ZSH config, sources all other configs
├── aliases/              # Themed alias files (sourced alphabetically)
│   ├── claude.sh         #   Claude launchers, worktree helpers, AI CLI tools
│   ├── core.sh           #   Safety-wrapped rm/cp/mv, utilities
│   ├── editors.sh        #   edit-* shortcuts
│   ├── git.sh            #   g* git aliases
│   ├── jobs.sh           #   Pueue j* + Slurm q* job queues
│   ├── misc.sh           #   ghostty themes g0-g9, UV_EXCLUDE_NEWER, misc
│   ├── nav.sh            #   cd override, .. navigation, directory shortcuts
│   ├── net.sh            #   SSH, VPN, network aliases
│   ├── secrets.sh        #   SOPS/BWS, secrets-*, snippet aliases
│   └── tmux.sh           #   ta/tad/tn etc.
├── aliases_*.sh          # Environment-specific aliases (optional, e.g. aliases_inspect.sh)
├── tmux.conf             # Tmux configuration
├── p10k.zsh              # Powerlevel10k theme
├── vimrc                 # Vim configuration
├── vscode_settings.json  # VSCode/Cursor/Antigravity settings (merged, not overwritten)
├── vscode_extensions.txt # Auto-installed extensions (38 curated, categorized)
├── zed/                      # Zed editor config (symlinked to ~/.config/zed/)
│   ├── settings.json         # Zed settings (JSONC, feature parity with Cursor)
│   └── keymap.json           # Custom keybindings (Cmd+K = inline AI edit)
├── finicky.js            # Browser routing (macOS, symlinked)
├── ghostty               # Ghostty terminal config (symlinked to platform-specific path)
├── htop/htoprc           # htop config (symlinked, uses dynamic CPU meters)
├── serena/serena_config.yml  # Serena MCP config (symlinked, dashboard auto-open disabled)
├── mouseless/config.yaml # Mouseless keyboard mouse config (macOS only, copied not symlinked)
├── alfred/local-golden/  # Golden Alfred summon hotkey, seeded onto new Macs by alfred-fix
├── key_bindings.sh       # ZSH key bindings (sourced by zshrc.sh)
├── macos_default_apps.conf   # Default editor + file type associations (single source of truth)
├── gitconfig             # Git config template
├── ignore/                   # Ignore pattern management
│   ├── gitignore_base        # Universal patterns — deployed to git AND search tools
│   ├── gitignore_research    # Research dirs — deployed to git ONLY (search tools skip)
│   └── patterns              # Pattern definitions for `claude-tools ignore apply` TUI
├── user.conf.example     # User-specific git settings template
├── editorconfig          # EditorConfig formatting defaults (symlinked to ~/.editorconfig)
├── curlrc                # curl defaults: follow redirects, show errors (symlinked to ~/.curlrc)
├── inputrc               # Readline config for bash/python/node REPLs (symlinked to ~/.inputrc)
├── gitattributes_global  # Binary file handling + line endings (symlinked to ~/.gitattributes)
├── machines.conf.example # Machine registry template (machine-id → name + emoji, for prompt/statusline). Real `machines.conf` is gitignored / lives on `yulong`
├── npmrc                 # Global npm config: ignore-scripts + 7-day min-release-age (symlinked)
├── bunfig.toml           # Global bun config: 7-day min-release-age (symlinked)
├── pnpmrc                # Global pnpm config: 7-day min-release-age (symlinked)
├── uv.toml               # Global uv config: 7-day exclude-newer (symlinked)
├── resources.conf        # Resource partitioning for Pueue job management (CPU, memory, parallelism)
├── pueue.yml             # Pueue daemon config (symlinked to ~/.config/pueue/)
└── systemd-user/         # systemd user units (slices, pueued service, reset-failed timer)

claude/                   # Symlinked to ~/.claude/
├── CLAUDE.md             # Global AI instructions (slim ~120 lines, identity + pointers)
├── settings.json         # Claude Code settings
├── output-styles/        # Custom output styles (10x-mentor: 4-track growth coaching)
├── rules/                # Auto-loaded behavioral rules (safety, workflow, conventions)
├── agents/               # Personal agents (llm-billing)
├── skills/               # Personal skills (commit, anthropic-style, jobs, etc.)
├── ai-safety-plugins -> ~/code/marketplaces/ai-safety-plugins  # Symlink to marketplace repo
├── plugins/              # Plugin runtime (cache, installed_plugins.json)
├── docs/                 # On-demand knowledge (research, async, tmux, agent teams, etc.)
├── ai_docs -> docs       # Permanent backwards-compat symlink
├── hooks/                # Personal hook scripts (agent_spawned.sh, pre_session_start.sh)
├── templates/            # Templates for specs, reports, context profiles
│   └── contexts/         # profiles.yaml (plugin registry + profile definitions)
├── projects/             # Project-specific settings overrides
└── (runtime dirs)        # cache/, logs/, history.jsonl, todos/, etc.

plans/                    # Per-project implementation plans (via plansDirectory setting)
specs/                    # Specifications and requirements

codex/                    # Codex CLI configuration (symlinked to ~/.codex/)

.secrets                  # Legacy decrypted secrets file (gitignored, no longer the primary runtime path)

# Private dotfiles runtime secrets (BWS token) live outside this repo:
#   $BWS_TOKEN_FILE (default: ~/.config/bws/token)

custom_bins/              # Custom utilities (added to PATH)
├── utc_date              # Outputs DD-MM-YYYY in UTC
├── utc_timestamp         # Outputs DD-MM-YYYY_HH-MM-SS in UTC
├── machine-name          # Machine name for prompt/statusline (registry → SSH config → hostname)
├── machine-register      # Register/list/remove machines in config/machines.conf
├── claude-cache-clean    # Remove stale plugin cache versions
├── any2md                # Universal content-to-markdown converter (files, URLs, arxiv, dirs)
├── jguard                # Memory pressure monitor for Pueue workloads (PSI-based)
├── dotfiles-secrets      # Private dotfiles secrets helper (paths, key listing, shell exports)
├── setup-envrc           # Per-project secret picker + .envrc generator (fzf, drift detection, eval-based exports)
└── alfred-fix            # Repair Dropbox-synced Alfred prefs (de-quarantine, +x, hotkey seed); --capture saves golden hotkey

lib/plotting/             # Python plotting library (deployed to ~/.local/lib/plotting/)
├── anthro_colors.py      # Anthropic brand colors (ground truth)
└── petriplot.py          # Petri helpers (imports anthro_colors)

config/matplotlib/        # Matplotlib style files (.mplstyle only)
├── anthropic.mplstyle    # Anthropic brand (white bg, PRETTY_CYCLE)
├── deepmind.mplstyle     # DeepMind (Google colors, white bg)
└── petri.mplstyle        # Petri (ivory bg, editorial aesthetic)

tools/
├── claude-tools/         # Rust binary (statusline, context, ignore, setup)
└── set-default-app/      # Swift CLI (macOS file type associations)
```

### Directory Environment Variables

Standard directory locations can be customized via environment variables:

| Variable | Default | Purpose |
|----------|---------|---------|
| `CODE_DIR` | `~/code` | Primary code projects and repositories |
| `WRITING_DIR` | `~/writing` | Writing projects (papers, drafts, notes) |
| `SCRATCH_DIR` | `~/scratch` | Temporary experimentation and testing |
| `PROJECTS_DIR` | `~/projects` | General projects |
| `DOT_DIR` | (auto-detected) | Dotfiles repository location |
| `DOTFILES_SECRETS_DIR` | `~/.config/dotfiles-secrets` | Private repo/path for dotfiles runtime secrets |

**Customization:**
```bash
# In ~/.zshenv (loaded before zshrc, recommended)
export CODE_DIR="$HOME/work/projects"
export WRITING_DIR="$HOME/Documents/writing"
```

**Cloud environments:** The standard directory structure works transparently on RunPod/cloud via symlinks created by `scripts/cloud/setup.sh`.

**Related aliases:** `code`, `writing`, `scratch`, `projects`, `dotfiles`

### Important Behaviors

Subtleties worth knowing per deploy component. Full mechanics live in the matching `deploy_*()` function in [`deploy.sh`](./deploy.sh).

| Component | Mechanism | Key gotcha |
|-----------|-----------|------------|
| **Gist Sync** (`deploy_secrets`) | Bidirectional sync of `~/.ssh/config`, `authorized_keys`, `config/user.conf` with gist `3cc239...371`. Last-modified wins. Daily 8 AM (launchd/cron). | Requires `gh auth login`. Manual: `sync-gist`. Runs before git config (user.conf provides identity). |
| **Encrypted Secrets** (BWS) | API keys in Bitwarden Secrets Manager. **NOT globally exported** — use `setup-envrc` per repo (direnv), or `with-secrets KEY... -- <cmd>` for one-shot. Managed: `OPENAI/OPENROUTER/ANTHROPIC_API_KEY`, `HF_TOKEN`, `MODAL_TOKEN_ID/SECRET`. | BWS token at `~/.config/bws/token`. Run `secrets-init bws` on new machines. Use `secrets-edit` to add/update secrets. |
| **Git Config** (`deploy_git_config`) | Reads `config/user.conf`; prompts on conflicts. Deploys split ignores: `~/.gitignore_global` (git, broad), `~/.ignore_global` (ripgrep, narrow), `~/.config/fd/ignore` (fd). Result: git ignores `data/`/`archive/`, but search tools can still see them. | `fd` has no `--no-ignore-global` flag — use `fd -I` to traverse research dirs. |
| **Editor Settings** (`deploy_editor_settings`) | Merges into VSCode/Cursor/Antigravity settings (no overwrite, existing wins). Auto-installs 38 curated extensions from `vscode_extensions.txt`. | Antigravity CLI at `/Applications/Antigravity.app/Contents/Resources/app/bin/antigravity`. |
| **Zed** | Symlinks `config/zed/{settings,keymap}.json` → `~/.config/zed/`. Searches gitignored files by default. | SSH hosts read from `~/.ssh/config` (gist-synced). Cmd+K overrides Zed's chord prefix → inline AI edit. |
| **Finicky, Ghostty** | Symlinked to fixed paths (Ghostty path is platform-specific). Existing files backed up with timestamp. | Ghostty needs reload (Cmd+Shift+Comma) after config change. |
| **Plotting + matplotlib** (`--matplotlib`) | **Copies** Python modules to `~/.local/lib/plotting/` (isolation); **symlinks** `.mplstyle` files to `~/.config/matplotlib/stylelib/` (live updates). PYTHONPATH set in zshrc. | Python module updates require re-running `deploy.sh --matplotlib`. Default style: `anthropic`. |
| **File Associations** (`--file-apps`) | Reads `config/macos_default_apps.conf`, compiles `tools/set-default-app/main.swift` (cached), calls deprecated `LSSetDefaultRoleHandlerForContentType` (still works on Sequoia). Same conf drives `$EDITOR`/`$VISUAL`. | macOS only. Linux would need `xdg-mime` (not implemented). |
| **Claude Code** (smart merge) | Symlinks `claude/` → `~/.claude/`. If `~/.claude/` predates dotfiles, backed up to `~/.claude.backup.<ts>`, then runtime files restored: `.credentials.json`, `history.jsonl`, `cache/`, `projects/`, `plans/`, `todos/`, `mcp_servers.json`. | Works whether `install.sh` or `deploy.sh` runs first. |

## Plotting with Anthropic Style

**ALWAYS use Anthropic style as default** for all plots created by Claude Code:

```python
from anthro_colors import use_anthropic_defaults
use_anthropic_defaults()

# Now all plots use anthropic style (white background, PRETTY_CYCLE colors)
import matplotlib.pyplot as plt
fig, ax = plt.subplots()
# ... your plotting code
```

**Why:** Ensures consistent, professional appearance across all Claude-generated plots.

**Absolute path to styles:** `~/.config/matplotlib/stylelib/anthropic.mplstyle`

**Available styles:**
- `anthropic` - Default, white background, Anthropic brand colors (use this)
- `petri` - Ivory background, warm editorial aesthetic (use for specific Petri-paper style)
- `deepmind` - Google/DeepMind colors (use for DeepMind-related work)

**Importing colors:**
```python
from anthro_colors import CLAY, SKY, CACTUS, IVORY, SLATE, PRETTY_CYCLE
import petriplot as pp  # For Petri-specific plotting helpers
```

## Development Patterns

### Adding New Features

**New Aliases**:
- General: Add to the appropriate `config/aliases/<theme>.sh` (git.sh, nav.sh, net.sh, claude.sh, etc.)
- Environment-specific: Create `config/aliases_<name>.sh`
- Deploy with: `./deploy.sh --aliases=<name>`

**New Dependencies**:
- Add to `install.sh` with OS detection (`is_macos`/`is_linux`)
- Add feature flag if optional (e.g., `--extras`, `--experimental`)
- Update defaults at top of `install.sh` if should be included by default

**New Deployment Component**:
1. Create `deploy_X()` function in `deploy.sh`
2. Add flag parsing in `while` loop
3. Call function in appropriate section (symlink/copy/append logic)
4. Update help text and defaults

**New Custom Binary**:
- Add script to `custom_bins/` (automatically added to PATH)
- Make executable: `chmod +x custom_bins/<name>`

### Code Style

- Use functions for reusability
- Consistent indentation (2 spaces for shell scripts)
- Validate prerequisites before operations
- Provide clear user feedback for important operations
- Use `backup_file()` helper for destructive operations

## Important Gotchas

- **macOS vs Linux paths**: VSCode settings location differs by OS
- **Symlinks vs copies**: Some configs are symlinked (Finicky, Ghostty, Claude, Codex, Serena, `~/.ignore_global`, `~/.config/fd/ignore`), others copied (ZSH, git, Mouseless). `~/.gitignore_global` is composed (concatenated from `config/ignore/gitignore_base` + `config/ignore/gitignore_research`)
- **Mouseless config**: Copied (not symlinked) because Mouseless uses atomic `rename()` on UI save which destroys symlinks. Use `sync-mouseless` to pull UI changes back to dotfiles
- **Conditional loading**: ZSH config only sources tools if they exist (pyenv, micromamba, etc.)
- **Tmux environment pollution**: Use `tmux-clean` script to start with minimal env
- **TPM plugins**: Guarded with `if-shell` so tmux works fine without TPM installed. Deploy auto-installs plugins to disk, but already-running tmux sessions need `prefix + I` or a tmux restart to load them. `prefix + Ctrl-s` saves session, `prefix + Ctrl-r` restores. Continuum auto-restores last saved session on first server start after reboot; `touch ~/tmux_no_auto_restore` to suppress. Save files: `~/.tmux/resurrect/` (portable, auto-cleaned after 30 days)
- **Claude Code directory**: `claude/` is symlinked to `~/.claude/` (not copied)
- **Codex CLI directory**: `codex/` is symlinked to `~/.codex/` (not copied)
- **Serena MCP config**: `config/serena/serena_config.yml` symlinked to `~/.serena/serena_config.yml` (dashboard auto-open disabled)
- **Ghostty config**: Symlinked to platform-specific path, requires reload after changes (Cmd+Shift+Comma)
- **Zed config**: Symlinked (like Ghostty/Claude). `ssh_connections` are machine-specific (added via Zed UI, hosts from ~/.ssh/config)
- **Antigravity config**: VSCode fork by Google (`com.google.antigravity`). Same settings as Cursor, deployed via `--editor` flag. CLI at `/Applications/Antigravity.app/Contents/Resources/app/bin/antigravity`
- **Secrets (BWS)**: BWS token at `~/.config/bws/token`. Run `secrets-init bws` on new machines (paste token from Bitwarden). Use `secrets-edit` to add/update/delete secrets.
- **Secrets are per-project**: API keys require `setup-envrc` in each project. Running `npm postinstall` or `pip install` in a project without `.envrc` cannot access secrets (this is intentional — supply chain defense). Legacy `.secrets` / `.env` files may still exist locally but are no longer the intended runtime path.
- **min-release-age quarantine**: All package managers have a 7-day delay on new releases. Packages published <7 days ago will fail to install. This is intentional. See `claude/rules/supply-chain-security.md` for override syntax
- **Pueue + systemd slices**: `j*` aliases require pueue + systemd user session. `systemd --user` doesn't work inside Claude Code sandbox (bubblewrap blocks D-Bus) — test from normal shell. Cgroup delegation may need one-time `sudo systemctl set-property user-$(id -u).slice Delegate=yes`. Config in `config/resources.conf` (edit when scaling machine).
- **CLI tool package strategy**: macOS uses Homebrew (ecosystem, GUI apps, libraries). Linux uses apt for baseline + mise `github:` backend for modern versions of fast-moving CLI tools (fzf, bat, eza, fd, ripgrep, delta, dust, zoxide, jless, just, sd, duf, gum, vivid). apt packages are often years behind upstream; mise downloads release binaries from GitHub with version tracking (`mise upgrade --all`). Homebrew on Linux was rejected (too heavy, installs own gcc/glibc). See `PACKAGES_CORE` (apt/brew), `PACKAGES_MACOS` (brew), `PACKAGES_LINUX_MISE` (mise) in `config.sh`
- **Rust + bash dual implementations**: Some tools have a Rust version (for speed) and a bash fallback. Keep both in sync. Rust source lives in `tools/claude-tools/src/`, bash in `claude/`. Recompile with `cd tools/claude-tools && cargo build --release` then `cp target/release/claude-tools ../../custom_bins/`. Current dual-impl tools: statusline (`statusline.rs` + `claude/statusline.sh`), usage (`usage.rs` + inline in `statusline.sh`)

## Cross-Reference

- User documentation: README.md
- Cleanup system: scripts/cleanup/README.md
- Git config template: config/gitconfig
- Claude agents: claude/agents/*.md

## Learnings
<!-- Claude: add project-specific discoveries below. Prune entries >2 weeks old. Keep under 20 entries. -->
- tmux-resurrect: auto-save is on (15 min), auto-restore is OFF. Use `prefix+R` popup or `tmux-restore` CLI to selectively restore windows from any save. Resurrect file format: `pane` lines ($2=session, $3=win_index, $8=path) + `window` lines ($2=session, $3=win_index, $7=win_name) (2026-04-05)
- fzf pre-selection in `setup-envrc` requires fzf 0.54+ (`--bind "load:pos(N)+select"`). apt's fzf (0.44) is too old; mise installs 0.71 on Linux. macOS brew is fine. fzf is in both `PACKAGES_CORE` (apt baseline) and `PACKAGES_LINUX_MISE` (modern override) — mise's PATH takes precedence (2026-04-14)
- rust-skills plugin removed (2026-05-26). UserPromptSubmit matcher was hyper-broad ("error", "async", "API", "implement", "explain", "how to" — injected ~100 lines on most prompts). Neuter-via-SessionStart-hook didn't hold (still fired same session) and mutates a tracked file in the marketplace clone, blocking future `git pull`. Re-add if Rust work picks up
