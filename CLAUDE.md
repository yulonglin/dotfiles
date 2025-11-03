# CLAUDE.md

Project-specific guidance for Claude Code when working with the dotfiles repository.

## Project Overview

Comprehensive dotfiles repository for ZSH, Tmux, Vim, SSH, and development tools. Works across macOS, Linux, and RunPod containers. Uses oh-my-zsh with powerlevel10k theme.

## Key Conventions

### Flag Behavior (Critical)

**Flags are ADDITIVE to defaults unless `--minimal` is used**

- `install.sh` defaults: macOS (`--zsh --tmux --ai-tools --cleanup`), Linux (`--zsh --tmux --ai-tools`)
- `deploy.sh` defaults: `--claude --vim --editor`
- Adding flags extends defaults (e.g., `./install.sh --extras` = defaults + extras)
- `--minimal` flag disables all defaults (only installs what you specify)
- Modifiers (`--append`, `--ascii`, `--force`) don't affect defaults

See README.md for detailed usage.

### Deployment Components

Each component in `deploy.sh` uses a `deploy_X()` helper function:
- `deploy_zshrc()` - ZSH configuration
- `deploy_git_config()` - Git config with smart conflict resolution
- `deploy_editor_settings()` - VSCode/Cursor settings with smart merging
- `deploy_finicky()` - Browser routing (macOS only)
- `deploy_aliases()` - Environment-specific aliases

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
├── gitconfig             # Git config template
├── gitignore_global      # Global gitignore
└── user.conf.example     # User-specific git settings template

claude/
├── CLAUDE.md             # Global AI instructions (symlinked to ~/.claude/)
├── settings.json         # Claude Code settings
├── agents/               # Specialized agent definitions (13 total)
└── notify.sh             # Task completion notifications

custom_bins/              # Custom utilities (added to PATH)
```

### Important Behaviors

**Git Config (`deploy_git_config()`)**:
- Reads `config/user.conf` for user-specific settings
- Detects conflicts with existing git config
- Prompts for resolution (keep/use new/merge/skip)

**Editor Settings (`deploy_editor_settings()`)**:
- Merges with existing VSCode/Cursor settings (doesn't overwrite)
- Existing settings take precedence
- Auto-installs extensions from `config/vscode_extensions.txt`
- Deploys to both VSCode and Cursor if installed

**Finicky Deployment**:
- Symlinks `config/finicky.js` to `~/.finicky.js`
- Backs up existing file with timestamp if not a symlink

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
- **Symlinks vs copies**: Some configs are symlinked (Finicky), others copied (ZSH, git)
- **Conditional loading**: ZSH config only sources tools if they exist (pyenv, micromamba, etc.)
- **Tmux environment pollution**: Use `tmux-clean` script to start with minimal env
- **Claude Code directory**: `claude/` is symlinked to `~/.claude/` (not copied)

## Cross-Reference

- User documentation: README.md
- Cleanup system: scripts/cleanup/README.md
- Git config template: config/gitconfig
- Claude agents: claude/agents/*.md
