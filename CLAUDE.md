# CLAUDE.md

Project-specific guidance for Claude Code when working with the dotfiles repository.

## Project Overview

Comprehensive dotfiles repository for ZSH, Tmux, Vim, SSH, and development tools. Works across macOS, Linux, and RunPod containers. Uses oh-my-zsh with powerlevel10k theme.

## Key Conventions

### Flag Behavior (Critical)

**Flags are ADDITIVE to defaults unless `--minimal` is used**

- `install.sh` defaults: macOS (`--zsh --tmux --ai-tools --cleanup`), Linux (`--zsh --tmux --ai-tools`)
- `deploy.sh` defaults: `--vim --editor --claude --codex --ghostty --htop --matplotlib --git-hooks --secrets --cleanup --claude-cleanup --ai-update --brew-update` (file cleanup macOS only, rest both platforms)
- Adding flags extends defaults (e.g., `./install.sh --extras` = defaults + extras)
- `--minimal` flag disables all defaults (only installs what you specify)
- Modifiers (`--append`, `--ascii`, `--force`) don't affect defaults

See README.md for detailed usage.

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
| `cwmerge <name>` | Merge worktree branch into current branch (safe: auto-aborts on conflict) |
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
- Secrets sync - Bidirectional sync with GitHub gist (SSH config, git identity), automated daily at 8 AM
- Git config - Smart conflict resolution with user prompts
- VSCode/Cursor settings - Merges with existing settings
- Finicky - Browser routing (macOS only, symlinked)
- Ghostty - Terminal emulator configuration (symlinked to platform-specific path)
- Claude Code - AI assistant configuration (symlinked)
- Codex - CLI tool configuration (symlinked)
- Serena - MCP server configuration (symlinked, dashboard auto-open disabled)
- File cleanup - Downloads/Screenshots cleanup (macOS only, launchd)
- Claude Code cleanup - No-output-for-24h session cleanup (tmux preserved, launchd/cron)
- AI tools auto-update - Daily update of Claude Code, Gemini CLI, Codex CLI (6 AM, launchd/cron)
- Package auto-update - Weekly upgrade + cleanup (Sunday 5 AM, brew/apt/dnf/pacman, launchd/cron)

## Architecture

### Core Scripts

- `install.sh` - Dependency installation (OS-specific, uses feature flags)
- `deploy.sh` - Configuration deployment (uses helper functions, supports --append/--backup)
- `config/macos_settings.sh` - macOS system defaults (run automatically on macOS)
- `scripts/cleanup/` - Automatic cleanup system (launchd/cron scheduled jobs)

### Configuration Structure

```
config/
├── zshrc.sh              # Main ZSH config, sources all other configs
├── aliases.sh            # General aliases
├── aliases_*.sh          # Environment-specific aliases (optional)
├── tmux.conf             # Tmux configuration
├── p10k.zsh              # Powerlevel10k theme
├── vimrc                 # Vim configuration
├── vscode_settings.json  # VSCode/Cursor settings (merged, not overwritten)
├── vscode_extensions.txt # Auto-installed extensions
├── finicky.js            # Browser routing (macOS, symlinked)
├── ghostty               # Ghostty terminal config (symlinked to platform-specific path)
├── htop/htoprc           # htop config (symlinked, uses dynamic CPU meters)
├── serena/serena_config.yml  # Serena MCP config (symlinked, dashboard auto-open disabled)
├── key_bindings.sh       # ZSH key bindings (sourced by zshrc.sh)
├── gitconfig             # Git config template
├── ignore_global         # Universal ignore patterns (OS, editors, Python, LaTeX, Claude Code)
├── ignore_research       # Research-only ignore patterns (archive/, data/, experiments/, etc.)
├── ignore_template       # Per-project .ignore template (negation patterns for search tools)
└── user.conf.example     # User-specific git settings template

claude/                   # Symlinked to ~/.claude/
├── CLAUDE.md             # Global AI instructions (slim ~120 lines, identity + pointers)
├── settings.json         # Claude Code settings
├── output-styles/        # Custom output styles (10x-mentor: 4-track growth coaching)
├── rules/                # Auto-loaded behavioral rules (safety, workflow, conventions)
├── agents/               # Personal agents (llm-billing)
├── skills/               # Personal skills (commit, anthropic-style, etc.)
├── ai-safety-plugins -> ~/code/ai-safety-plugins  # Symlink to marketplace repo
├── plugins/              # Plugin runtime (cache, installed_plugins.json)
├── docs/                 # On-demand knowledge (research, async, tmux, agent teams, etc.)
├── ai_docs -> docs       # Permanent backwards-compat symlink
├── hooks/                # Personal hook scripts (agent_spawned.sh, pre_session_start.sh)
├── templates/            # Templates for specs, reports, context profiles
│   └── contexts/         # profiles.yaml (plugin registry + profile definitions)
├── projects/             # Project-specific settings overrides
└── (runtime dirs)        # cache/, logs/, history.jsonl, todos/, etc.

codex/                    # Codex CLI configuration (symlinked to ~/.codex/)

custom_bins/              # Custom utilities (added to PATH)
├── utc_date              # Outputs DD-MM-YYYY in UTC
├── utc_timestamp         # Outputs DD-MM-YYYY_HH-MM-SS in UTC
├── claude-context        # YAML-driven plugin profiles + marketplace sync (--sync)
└── claude-cache-clean    # Remove stale plugin cache versions

lib/plotting/             # Python plotting library (deployed to ~/.local/lib/plotting/)
├── anthro_colors.py      # Anthropic brand colors (ground truth)
└── petriplot.py          # Petri helpers (imports anthro_colors)

config/matplotlib/        # Matplotlib style files (.mplstyle only)
├── anthropic.mplstyle    # Anthropic brand (white bg, PRETTY_CYCLE)
├── deepmind.mplstyle     # DeepMind (Google colors, white bg)
└── petri.mplstyle        # Petri (ivory bg, editorial aesthetic)
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

**Customization:**
```bash
# In ~/.zshenv (loaded before zshrc, recommended)
export CODE_DIR="$HOME/work/projects"
export WRITING_DIR="$HOME/Documents/writing"
```

**Cloud environments:** The standard directory structure works transparently on RunPod/cloud via symlinks created by `scripts/cloud/setup.sh`.

**Related aliases:** `code`, `writing`, `scratch`, `projects`, `dotfiles`

### Important Behaviors

**Secrets Sync (`deploy_secrets()`)**:
- Bidirectional sync with GitHub gist (ID: `3cc239f160a2fe8c9e6a14829d85a371`)
- Syncs: `~/.ssh/config`, `~/.ssh/authorized_keys`, `config/user.conf` (git identity)
- Auto-adds local public key to `authorized_keys` before sync (enables SSH between your machines)
- Last-modified wins: compares local mtime vs gist updated_at
- Requires `gh auth login` (browser OAuth, no extra keys needed)
- Runs before git config (user.conf provides git identity)
- Automated: Runs daily at 8:00 AM (launchd/cron), uninstall with `scripts/cleanup/setup_secrets_sync.sh --uninstall`
- Manual: `sync-secrets` (alias) or `scripts/sync_secrets.sh`

**Git Config (`deploy_git_config()`)**:
- Reads `config/user.conf` for user-specific settings
- Detects conflicts with existing git config
- Prompts for resolution (keep/use new/merge/skip)
- Deploys split ignore files for git vs search tools:
  - `~/.gitignore_global` — concatenated from `config/ignore_global` + `config/ignore_research` (copy)
  - `~/.ignore_global` — symlink to `config/ignore_global` (universal patterns only, for ripgrep)
  - `~/.config/fd/ignore` — symlink to `config/ignore_global` (for fd's own ignore layer)
  - `~/.config/ripgrep/config` — generated (`--no-ignore-global` + `--ignore-file ~/.ignore_global`)
- Result: git ignores everything; rg/Claude Code/Cursor search can see research files (`data/`, `archive/`, etc.)
- fd limitation: no `--no-ignore-global` flag, so fd still respects git's global ignore. Use `fd -I` for research dirs.

**Editor Settings (`deploy_editor_settings()`)**:
- Merges with existing VSCode/Cursor settings (doesn't overwrite)
- Existing settings take precedence
- Auto-installs extensions from `config/vscode_extensions.txt`
- Deploys to both VSCode and Cursor if installed

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
- **Symlinks vs copies**: Some configs are symlinked (Finicky, Ghostty, Claude, Codex, Serena, `~/.ignore_global`, `~/.config/fd/ignore`), others copied (ZSH, git). `~/.gitignore_global` is composed (concatenated from `config/ignore_global` + `config/ignore_research`)
- **Conditional loading**: ZSH config only sources tools if they exist (pyenv, micromamba, etc.)
- **Tmux environment pollution**: Use `tmux-clean` script to start with minimal env
- **Claude Code directory**: `claude/` is symlinked to `~/.claude/` (not copied)
- **Codex CLI directory**: `codex/` is symlinked to `~/.codex/` (not copied)
- **Serena MCP config**: `config/serena/serena_config.yml` symlinked to `~/.serena/serena_config.yml` (dashboard auto-open disabled)
- **Ghostty config**: Symlinked to platform-specific path, requires reload after changes (Cmd+Shift+Comma)

## Cross-Reference

- User documentation: README.md
- Cleanup system: scripts/cleanup/README.md
- Git config template: config/gitconfig
- Claude agents: claude/agents/*.md

## Learnings
<!-- Claude: add project-specific discoveries below. Prune entries >2 weeks old. Keep under 20 entries. -->
- Auto MEMORY.md paths are machine-specific (encodes full filesystem path) — not portable across macOS/Linux/RunPod. Use CLAUDE.md Learnings section for durable cross-machine memory instead (2026-02-05)
- Global CLAUDE.md restructured: slim core (~120 lines) + rules/ (auto-loaded behavioral rules) + docs/ (on-demand knowledge). ai_docs/ renamed to docs/ with permanent symlink for backwards-compat. Serena, feature-dev, ralph-loop, pyright-lsp plugins disabled (2026-02-05)
- Claude Code plugin system creates symlinks in `~/.claude/skills/` → `plugins/cache/`, causing every plugin skill to appear twice in slash command picker (once as "(user)", once as plugin name). Workaround: `clean-skill-dupes` alias or `deploy.sh` auto-cleans. Symlinks are recreated on startup/plugin-sync. Related: anthropics/claude-code#14549, #21891 (2026-02-06)
- Plugin reorganization: code-quality → code, added workflow (agent-teams, handover, compact, insights) and viz (tikz-diagrams). Context profiles via `claude-context` CLI. Global settings now explicitly disable all non-essential plugins. insights absorbed into workflow. humanize-draft merged into review-draft as 5th critic. Renamed *-toolkit → * for shorter agent prefixes (2026-02-17)
