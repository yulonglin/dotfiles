# CLAUDE.md

Project-specific guidance for Claude Code when working with the dotfiles repository.

## Project Overview

Comprehensive dotfiles repository for ZSH, Tmux, Vim, SSH, and development tools. Works across macOS, Linux, and RunPod containers. Uses oh-my-zsh with powerlevel10k theme.

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
- Text replacements - Bidirectional sync with macOS + Alfred snippets (daily 9 AM, requires Full Disk Access for terminal app). macOS uses raw shortcuts; Alfred applies collection prefix at runtime (e.g., `fm.hi`)
- Encrypted secrets (SOPS+age / BWS) - Stores API keys via Bitwarden Secrets Manager (primary) or SOPS+age (fallback). Backend auto-detected: bws if token + CLI exist, else sops. Override with `DOTFILES_SECRETS_BACKEND` env var
- File cleanup - Downloads/Screenshots cleanup (macOS only, launchd)
- Claude Code cleanup - No-output-for-24h session cleanup (tmux preserved, launchd/cron)
- AI tools auto-update - Daily update of Claude Code, Gemini CLI, Codex CLI (6 AM, launchd/cron)
- Developer config files - EditorConfig, curlrc, inputrc, .hushlogin (deployed with --editor flag)
- Global gitattributes - Binary file handling + line endings (deployed with --git-config flag)
- File associations - Set default editor for coding file types (macOS only, reads `config/macos_default_apps.conf`)
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
├── aliases.sh            # General aliases
├── aliases_*.sh          # Environment-specific aliases (optional)
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
├── machines.conf         # Machine registry (machine-id → name + emoji, for prompt/statusline)
├── secrets.env.enc       # SOPS-encrypted API keys (committed, requires age key to decrypt)
├── envrc_sops_template   # Template .envrc for per-project SOPS secrets
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

# Private dotfiles runtime secrets live outside this repo:
#   $DOTFILES_SECRETS_DIR/.sops.yaml
#   $DOTFILES_SECRETS_DIR/secrets.env.enc

custom_bins/              # Custom utilities (added to PATH)
├── utc_date              # Outputs DD-MM-YYYY in UTC
├── utc_timestamp         # Outputs DD-MM-YYYY_HH-MM-SS in UTC
├── machine-name          # Machine name for prompt/statusline (registry → SSH config → hostname)
├── machine-register      # Register/list/remove machines in config/machines.conf
├── claude-cache-clean    # Remove stale plugin cache versions
├── any2md                # Universal content-to-markdown converter (files, URLs, arxiv, dirs)
├── jguard                # Memory pressure monitor for Pueue workloads (PSI-based)
├── dotfiles-secrets      # Private dotfiles secrets helper (paths, key listing, shell exports)
└── setup-envrc           # Per-project secret picker + .envrc generator (fzf, drift detection, eval-based exports)

lib/plotting/             # Python plotting library (deployed to ~/.local/lib/plotting/)
├── anthro_colors.py      # Anthropic brand colors (ground truth)
└── petriplot.py          # Petri helpers (imports anthro_colors)

config/matplotlib/        # Matplotlib style files (.mplstyle only)
├── anthropic.mplstyle    # Anthropic brand (white bg, PRETTY_CYCLE)
├── deepmind.mplstyle     # DeepMind (Google colors, white bg)
└── petri.mplstyle        # Petri (ivory bg, editorial aesthetic)

tools/
├── claude-tools/         # Rust binary (statusline, context, ignore)
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

**Gist Sync (`deploy_secrets()`)**:
- Bidirectional sync with GitHub gist (ID: `3cc239f160a2fe8c9e6a14829d85a371`)
- Syncs: `~/.ssh/config`, `~/.ssh/authorized_keys`, `config/user.conf` (git identity)
- Auto-adds local public key to `authorized_keys` before sync (enables SSH between your machines)
- Last-modified wins: compares local mtime vs gist updated_at
- Requires `gh auth login` (browser OAuth, no extra keys needed)
- Runs before git config (user.conf provides git identity)
- Automated: Runs daily at 8:00 AM (launchd/cron), uninstall with `scripts/cleanup/setup_gist_sync.sh --uninstall`
- Manual: `sync-gist` (alias) or `scripts/sync_gist.sh`

**Encrypted Secrets (SOPS + age)**:
- Keeps API keys in `${DOTFILES_SECRETS_DIR:-~/.config/dotfiles-secrets}/secrets.env.enc` and decrypts them on demand using `sops -d --config $DOTFILES_SECRETS_DIR/.sops.yaml` with the age key
- Age private key at `~/.config/sops/age/keys.txt` (stored in Bitwarden, pasted during cloud setup)
- Shell integration: secrets are **NOT globally exported** (supply chain defense). Use `setup-envrc` per-project via direnv. It supports direct exports (`KEY`), renamed exports (`ENV_VAR=SECRET_NAME`), and Telegram plugin bindings (`--telegram-secret SECRET_NAME`) that let `claude()` materialize `.claude/channels/telegram/.env` at launch time. `with-secrets KEY... -- <cmd>` decrypts only the requested keys for one command. Claude hooks load only `ANTHROPIC_API_KEY` through a dedicated wrapper.
- **Managed secrets** (kept in the encrypted store, exported only per-project):
  - `OPENAI_API_KEY` — OpenAI API access
  - `OPENROUTER_API_KEY` — OpenRouter API access
  - `ANTHROPIC_API_KEY` — Anthropic API access
  - `HF_TOKEN` — Hugging Face Hub access
  - `MODAL_TOKEN_ID`, `MODAL_TOKEN_SECRET` — Modal CLI/SDK auth (env vars replace `~/.modal.toml`)
- **Adding new secrets**: Use `secrets-edit` to edit the encrypted dotenv file in place. Prefer namespaced repo-specific keys when multiple repos need different credentials for the same provider (for example `AMBASSADOR_TELEGRAM_BOT_TOKEN` vs `SWORDSMITH_TELEGRAM_BOT_TOKEN`). `setup-envrc` then exposes only the selected bindings inside each repo’s `.envrc`.
- Commands: `secrets-init` (fzf picker: bws / sops / project), `secrets-init-bws` (BWS setup — paste access token, test connectivity), `secrets-init-sops` (SOPS+age setup — generate/paste age key), `secrets-edit` (edit encrypted dotenv in place), `secrets-paths` (show resolved private secrets repo paths), `secrets-fix-perms` (manual repair for secret-bearing file modes; normal flows now harden automatically), `setup-envrc` (repo-scoped export bindings + Telegram plugin binding + `.env` drift checks)
- All sops commands use explicit `--config` flag — sops searches from input file's directory by default, which fails when input is in `$TMPDIR`
- Bootstrap encryption uses `--config /dev/null` to bypass creation rules (tmpfile doesn't match `.enc$` regex); on-demand decryption uses `--config "$DOTFILES_SECRETS_DIR/.sops.yaml"`
- Graceful degradation: no errors if sops/age not installed or no encrypted file exists

**Git Config (`deploy_git_config()`)**:
- Reads `config/user.conf` for user-specific settings
- Detects conflicts with existing git config
- Prompts for resolution (keep/use new/merge/skip)
- Deploys split ignore files for git vs search tools:
  - `~/.gitignore_global` — concatenated from `config/ignore/gitignore_base` + `config/ignore/gitignore_research` (copy)
  - `~/.ignore_global` — symlink to `config/ignore/gitignore_base` (universal patterns only, for ripgrep)
  - `~/.config/fd/ignore` — symlink to `config/ignore/gitignore_base` (for fd's own ignore layer)
  - `~/.config/ripgrep/config` — generated (`--no-ignore-global` + `--ignore-file ~/.ignore_global`)
- Result: git ignores everything; rg/Claude Code/Cursor search can see research files (`data/`, `archive/`, etc.)
- fd limitation: no `--no-ignore-global` flag, so fd still respects git's global ignore. Use `fd -I` for research dirs.

**Editor Settings (`deploy_editor_settings()`)**:
- Merges with existing VSCode/Cursor/Antigravity settings (doesn't overwrite)
- Existing settings take precedence
- Auto-installs extensions from `config/vscode_extensions.txt` (38 curated)
- Deploys to VSCode, Cursor, and Antigravity if installed
- Antigravity CLI: uses full path `/Applications/Antigravity.app/Contents/Resources/app/bin/antigravity`

**Zed Deployment**:
- Symlinks `config/zed/settings.json` → `~/.config/zed/settings.json`
- Symlinks `config/zed/keymap.json` → `~/.config/zed/keymap.json`
- Backs up existing files if not already symlinks
- SSH connections: Zed reads hosts from `~/.ssh/config` (managed by gist sync). Project paths are machine-specific, added via Zed UI
- Search includes gitignored files by default (`search.include_ignored: true`)
- Extensions auto-installed via `auto_install_extensions` setting (no CLI needed)
- Cmd+K mapped to inline AI edit (overrides Zed's chord prefix — see keymap.json comments for alternatives)

**Finicky Deployment**:
- Symlinks `config/finicky.js` to `~/.finicky.js`
- Backs up existing file with timestamp if not a symlink

**Ghostty Deployment**:
- Symlinks `config/ghostty.conf` to platform-specific config path:
  - macOS: `~/Library/Application Support/com.mitchellh.ghostty/config`
  - Linux: `~/.config/ghostty/config`
- Backs up existing file with timestamp if not a symlink
- Configures Cmd+C for shell-based copy and Shift+Enter for multiline input

**Plotting Library and Matplotlib Deployment**:
- **Copies** Python modules from `lib/plotting/` to `~/.local/lib/plotting/` (anthro_colors.py, petriplot.py)
- **Symlinks** `*.mplstyle` files to `~/.config/matplotlib/stylelib/` (config files, auto-update)
- Rationale: Styles are config → symlink for live updates; Python modules copied for isolation
- Available styles:
  - `anthropic` - Anthropic brand (white background, PRETTY_CYCLE colors) **← recommended default**
  - `deepmind` - Google/DeepMind colors (white background)
  - `petri` - Petri paper style (ivory background, warm editorial aesthetic)
- Python library usage: `from anthro_colors import use_anthropic_defaults; use_anthropic_defaults()`
- PYTHONPATH auto-configured in zshrc to include `~/.local/lib/plotting/`
- Requires `--matplotlib` flag to deploy
- Note: Python module updates require re-running `deploy.sh --matplotlib`

**File Associations (`deploy --file-apps`)**:
- Reads `config/macos_default_apps.conf` for editor bundle ID and extension list
- Compiles `tools/set-default-app/main.swift` (cached, rebuilds only when source changes)
- Calls `LSSetDefaultRoleHandlerForContentType` per extension (deprecated macOS API, no replacement, works on Sequoia)
- Same config drives `$EDITOR` and `$VISUAL` in zshrc.sh
- macOS only (Linux uses `xdg-mime`, not implemented)

**Claude Code Deployment** (Smart Merge):
- Symlinks `claude/` to `~/.claude`
- If `~/.claude` exists from Claude Code installation:
  - Backs up to `~/.claude.backup.<timestamp>`
  - Creates symlink from `dotfiles/claude/` → `~/.claude`
  - Restores runtime files from backup (preserves your data):
    - `.credentials.json` - authentication
    - `history.jsonl` - conversation history
    - `cache/`, `projects/`, `plans/`, `todos/` - runtime data
    - `mcp_servers.json` - MCP server configuration
- Works seamlessly whether you run `install.sh` or `deploy.sh` first
- Custom config deployed: `CLAUDE.md`, `settings.json`, `agents/`, `hooks/`, `skills/`, `templates/`

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
- General: Add to `config/aliases.sh`
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
- **SOPS + age**: Age private key must exist at `~/.config/sops/age/keys.txt` before decrypt works. Run `secrets-init sops` on new machines (paste age key from Bitwarden)
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
- Plugin reorganization: code-quality → code, added workflow (agent-teams, handover, compact, insights) and viz (tikz-diagrams). Context profiles via `claude-tools context` CLI. Global settings now explicitly disable all non-essential plugins. insights absorbed into workflow. humanize-draft merged into review-draft as 5th critic. Renamed *-toolkit → * for shorter agent prefixes (2026-02-17)
- Rate limit account switching: restarting Claude Code does NOT clear cached usage — must fully logout (`claude auth logout`) then login again. `claude-switch` alias does both. SessionStart hook shows current auth account. `claude-tools` binary (Rust, `tools/claude-tools/`) can be recompiled with `cargo build --release` and copied to `custom_bins/` (2026-03-25)
- Codex CLI `codex exec` crashes inside Claude Code sandbox on macOS with `SCDynamicStoreCreate NULL` panic (`system-configuration` crate v0.6.1). Workaround: use `dangerouslyDisableSandbox: true` on Bash calls to `codex exec`. `codex --version`/`--help` work fine (no HTTP client init). Tracked: openai/codex#15640, #15296. Remove workaround when crate is upgraded (2026-03-26)
- Marketplace auto-update: three config layers — (1) `extraKnownMarketplaces` in settings.json declares sources (portable), (2) `autoUpdate: true` in profiles.yaml is source of truth, (3) `claude-tools context --sync` patches runtime `known_marketplaces.json`. All marketplaces use GitHub repos; local paths opt-in via `CLAUDE_CONTEXT_LOCAL=1`. SessionStart hook warns when no context profile configured (2026-03-26)
- Selective plugin sync: `--sync` only installs plugins referenced in profiles.yaml (`base:` + `profiles:`), prunes orphans by default (`--no-prune` to skip). Prune uses direct JSON manipulation (bypasses CLI bug where `claude plugin uninstall` refuses for cross-referenced plugins, anthropics/claude-code#15791). All installs use `--scope user`; `normalize_scopes()` upgrades stale project/local → user (2026-04-02)
- SOPS secrets format: dotfiles runtime secrets MUST stay dotenv, not JSON. NEVER run bare `sops secrets.env.enc` on the private secrets repo — always use `secrets-edit` or `sops --input-type dotenv --output-type dotenv` (2026-04-03)
- tmux-resurrect: auto-save is on (15 min), auto-restore is OFF. Use `prefix+R` popup or `tmux-restore` CLI to selectively restore windows from any save. Resurrect file format: `pane` lines ($2=session, $3=win_index, $8=path) + `window` lines ($2=session, $3=win_index, $7=win_name) (2026-04-05)
- Secrets backend: added bws (Bitwarden Secrets Manager) as primary backend alongside SOPS+age fallback. Token at `~/.config/bws/token` (chmod 600). Auto-detect: bws if token+CLI exist, else sops, else none. Override with `DOTFILES_SECRETS_BACKEND` env var. Free tier: 1 org, 3 machine accounts, unlimited secrets. bws has no offline cache — direnv caches in shell session. `setup-envrc` emits backend-appropriate `watch_file` directives. Cloud setup prompts for BWS token alongside age key (2026-04-07)
- Dotfiles runtime secrets now live outside the public repo in `DOTFILES_SECRETS_DIR`; `setup-envrc` writes repo-root `.envrc` files with direct exports, `ENV=SECRET` mappings, and optional Telegram plugin bindings. `claude()` materializes `.claude/channels/telegram/.env` from `DOTFILES_TELEGRAM_BOT_SECRET` at launch, `with-secrets` exports only named keys for one command, and Claude hooks inject only `ANTHROPIC_API_KEY` via a dedicated wrapper. `.secrets` / `.env` should be treated as legacy leftovers, not the normal flow (2026-04-06)
- fzf pre-selection in `setup-envrc` requires fzf 0.54+ (`--bind "load:pos(N)+select"`). apt's fzf (0.44) is too old; mise installs 0.71 on Linux. macOS brew is fine. fzf is in both `PACKAGES_CORE` (apt baseline) and `PACKAGES_LINUX_MISE` (modern override) — mise's PATH takes precedence (2026-04-14)
- Sandbox `denyWithinAllow` blocks git pull/merge/stash on `config/` and `claude/settings.json` even though `git` is in `excludedCommands`. `denyWithinAllow` is injected by Claude Code at runtime (not user-configurable). Workaround: use `dangerouslyDisableSandbox: true` on `git pull`, `git merge`, `git stash` commands in this repo. The sync guard hook (`guard_post_rebase.sh`) now warns (not blocks) on remote-ahead and allows merge completion commits (2026-04-10)
