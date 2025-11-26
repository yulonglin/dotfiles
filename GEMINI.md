# GEMINI.md

Project-specific guidance for Gemini when working with the dotfiles repository.
Refer to `gemini/GEMINI.md` for global agent guidelines and AI safety protocols.

## Project Overview

Comprehensive dotfiles repository for ZSH, Tmux, Vim, SSH, and development tools. Works across macOS, Linux, and RunPod containers. Uses oh-my-zsh with powerlevel10k theme.

## Key Conventions

### Flag Behavior (Critical)

**Flags are ADDITIVE to defaults unless `--minimal` is used**

- `install.sh` defaults: macOS (`--zsh --tmux --ai-tools --cleanup`), Linux (`--zsh --tmux --ai-tools`)
- `deploy.sh` defaults: `--claude --codex --vim --editor --experimental --cleanup` (cleanup macOS only)
- Adding flags extends defaults (e.g., `./install.sh --extras` = defaults + extras)
- `--minimal` flag disables all defaults (only installs what you specify)
- Modifiers (`--append`, `--ascii`, `--force`) don't affect defaults

See README.md for detailed usage.

### Deployment Components

Each component in `deploy.sh` is deployed with inline logic or helper functions:
- ZSH configuration - Main shell setup
- Git config - Smart conflict resolution with user prompts
- VSCode/Cursor settings - Merges with existing settings
- Finicky - Browser routing (macOS only, symlinked)
- Ghostty - Terminal emulator configuration (symlinked to platform-specific path)
- Claude Code - AI assistant configuration (symlinked)
- Codex - CLI tool configuration (symlinked)
- Cleanup automation - Scheduled cleanup jobs (macOS only)

## Architecture

### Core Scripts

- `install.sh` - Dependency installation (OS-specific, uses feature flags)
- `deploy.sh` - Configuration deployment (uses helper functions, supports --append/--backup)
- `config/macos_settings.sh` - macOS system defaults (run automatically on macOS)
- `scripts/cleanup/` - Automatic cleanup system (launchd/cron scheduled jobs)
- `runpod/` - Container or remote assets (notably `johnh_dev.Dockerfile` and `entrypoint.sh`)

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
├── key_bindings.sh       # ZSH key bindings (sourced by zshrc.sh)
├── gitconfig             # Git config template
├── gitignore_global      # Global gitignore
└── user.conf.example     # User-specific git settings template

claude/                   # Claude Code configuration (symlinked to ~/.claude/)
gemini/                   # Gemini configuration (global guidelines)
codex/                    # Codex CLI configuration (symlinked to ~/.codex/)

custom_bins/              # Custom utilities (added to PATH)
```

## Development Workflows

### Build, Test, and Development Commands
- `./install.sh --minimal --tmux --zsh` installs the requested components only; drop `--minimal` to accept the platform defaults.
- `./deploy.sh --aliases=speechmatics --vim` applies the ZSH/Tmux/Vim configs and optional alias packs; rerun after editing `config/*.sh`.
- `runpod/runpod_setup.sh` mirrors the dotfiles inside new RunPod machines; execute it immediately after cloning in remote shells.
- `docker build -f runpod/johnh_dev.Dockerfile -t <tag> .` builds the reference dev image.
- `docker run -it -v $PWD/runpod/entrypoint.sh:/dotfiles/runpod/entrypoint.sh <tag> /bin/zsh` smoke-tests it.

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

## Guidelines & Standards

### Code Style & Naming
- **Scripts**: Use `#!/bin/bash` plus `set -euo pipefail`.
- **Naming**: Lowercase with hyphens for files (`custom_bins/tmux-clean`).
- **Functions**: Use for reusability; keep helpers close to callers.
- **Indentation**: 2 spaces for shell scripts.
- **Platform Checks**: Guard host-specific logic with `if [[ "$OSTYPE" == ... ]]`.
- **Feedback**: Provide clear user feedback for important operations.
- **Safety**: Use `backup_file()` helper for destructive operations.

### Testing
- Run `shellcheck path/to/script.sh` and `zsh -n config/zshrc.sh` before shipping.
- Validate terminal assets locally with `tmux -f config/tmux.conf new-session` and `p10k configure`.
- Rerun `./deploy.sh` to ensure reentrancy.
- For RunPod, rebuild the Docker image and smoke-test.

### Security
- Copy `config/user.conf.example` to `config/user.conf` for local Git identity (untracked).
- Never hardcode tokens in scripts.
- Respect `config/gitignore_global` so caches, fonts, and secrets remain outside Git.

## Important Gotchas

- **macOS vs Linux paths**: VSCode settings location differs by OS.
- **Symlinks vs copies**: Some configs are symlinked (Finicky, Ghostty, Claude, Codex), others copied (ZSH, git).
- **Conditional loading**: ZSH config only sources tools if they exist (pyenv, micromamba, etc.).
- **Tmux environment pollution**: Use `tmux-clean` script to start with minimal env.
- **Ghostty config**: Symlinked to platform-specific path, requires reload after changes (Cmd+Shift+Comma).

## Cross-Reference

- User documentation: README.md
- Global Gemini guidance: gemini/GEMINI.md
- Cleanup system: scripts/cleanup/README.md
- Git config template: config/gitconfig
