# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a comprehensive dotfiles repository for ZSH, Tmux, Vim, and SSH setup that works across local and remote machines (including RunPod environments). The configuration uses oh-my-zsh with powerlevel10k theme and includes extensive customization for development workflows.

## Core Commands

### Installation and Deployment

**IMPORTANT: Flags are ADDITIVE to defaults unless --minimal is used**

```bash
# install.sh - Install dependencies
# DEFAULTS (applied automatically):
#   macOS:  --zsh --tmux --ai-tools --cleanup
#   Linux:  --zsh --tmux --ai-tools

# Install with defaults (recommended for most users)
./install.sh

# Install defaults + extras
./install.sh --extras

# Install ONLY specific components (no defaults)
./install.sh --minimal --tmux --extras

# Force reinstall of oh-my-zsh and plugins
./install.sh --force

# deploy.sh - Deploy configuration
# DEFAULTS (applied automatically):
#   --claude --vim --editor

# Deploy with defaults (recommended for most users)
./deploy.sh

# Deploy defaults + cleanup
./deploy.sh --cleanup

# Deploy defaults + environment-specific aliases
./deploy.sh --aliases=speechmatics

# Deploy ONLY specific components (no defaults)
./deploy.sh --minimal --vim
./deploy.sh --minimal --claude --aliases=speechmatics
./deploy.sh --minimal --editor          # Only editor settings

# Modifiers (don't affect defaults):
./deploy.sh --append                    # Append instead of overwrite
./deploy.sh --ascii=cat.txt             # Custom ASCII art
```

**Flag Behavior:**
- **Without flags**: Applies sensible defaults for quick setup
- **With flags**: Flags are **additive** to defaults (e.g., `--extras` adds extras to defaults)
- **With --minimal**: Only installs/deploys what you explicitly specify
- **Modifiers** (`--append`, `--ascii`, `--force`): Don't disable defaults

### Git Configuration
```bash
# Git configuration is automatically deployed during ./deploy.sh
# Includes smart conflict detection and resolution

# Customize git user settings (optional):
cp config/user.conf.example config/user.conf
# Edit config/user.conf with your name and email

# The following are automatically configured:
# - user.email and user.name (from user.conf or defaults)
# - push.autoSetupRemote and push.default
# - init.defaultBranch (main)
# - alias.lg (better git log)
# - core.excludesfile (global gitignore)

# If conflicts are detected, you'll be prompted to:
# - Keep existing values
# - Use new values from dotfiles
# - Merge interactively (choose per setting)
# - Skip git config deployment
```

### Editor Settings (VSCode/Cursor)
```bash
# Editor settings are automatically deployed during ./deploy.sh
# Deploys config/vscode_settings.json to both VSCode and Cursor if installed

# Deploy manually:
./deploy.sh --minimal --editor

# Paths (automatically detected):
# macOS:
#   VSCode: ~/Library/Application Support/Code/User/settings.json
#   Cursor: ~/Library/Application Support/Cursor/User/settings.json
# Linux:
#   VSCode: ~/.config/Code/User/settings.json
#   Cursor: ~/.config/Cursor/User/settings.json

# Merge Behavior (Smart Settings Preservation):
# - If settings.json doesn't exist: Copies dotfiles settings (new installation)
# - If settings.json exists: Merges with existing settings
#   - Existing settings take precedence (your preferences are preserved)
#   - New settings from dotfiles are added
#   - Example: If you have "files.autoSave": "onFocusChange" and dotfiles has
#     "afterDelay", your preference is kept
#   - Example: If dotfiles adds new Python/Jupyter settings, they're added to your config

# What's included in config/vscode_settings.json:
# - Python development (Black formatter, isort, Jupyter, package index depths)
# - Editor preferences (font, minimap disabled, multi-cursor modifier)
# - File management (auto-save, exclusions, watchers)
# - Git integration (auto-fetch, SSH remote command)
# - Theme and UI (default: One Dark Pro, VS Icons)
# - Cursor-specific settings (cpp.disabledLanguages, cpp.enablePartialAccepts)

# Extension Auto-Installation:
# Automatically installs extensions listed in config/vscode_extensions.txt
# - Requires 'code' or 'cursor' CLI to be available
# - Current extensions:
#   - One Dark Pro theme (zhuangtongfa.Material-theme)
#   - VSCode Icons (vscode-icons-team.vscode-icons)
#   - Python (ms-python.python)
#   - Black Formatter (ms-python.black-formatter)
#   - Jupyter (ms-toolsai.jupyter)
#   - GitLens (eamodio.gitlens)
# - To add more extensions: Edit config/vscode_extensions.txt (one extension ID per line)

# Customizing dotfiles settings:
# - Edit config/vscode_settings.json to change default theme, font, or other preferences
# - Edit config/vscode_extensions.txt to add/remove extensions
# - Changes will be deployed to new machines or when running ./deploy.sh --editor
```

### macOS System Settings
```bash
# macOS settings are automatically applied during ./install.sh
# Or run manually:
./config/macos_settings.sh

# Configures:
# - Keyboard repeat rates and press-and-hold behavior
# - Finder settings (show hidden files, path bar, status bar, Library folder)
# - Preview settings (disable persistence)
# - Screenshot location (~/Screenshots)
# - Mouse tracking speed
```

### Automatic File Cleanup
```bash
# Test cleanup (dry run) - see what would be deleted
./scripts/cleanup/cleanup_old_files.sh --dry-run

# DRY_RUN supports multiple formats: true, 1, yes, y, TRUE, Yes
DRY_RUN=yes ./scripts/cleanup/cleanup_old_files.sh

# Run manual cleanup (default: 180 days retention)
./scripts/cleanup/cleanup_old_files.sh

# Custom retention period
./scripts/cleanup/cleanup_old_files.sh --days 90

# Install automatic cleanup (runs monthly by default)
./scripts/cleanup/install.sh

# Install with custom settings
./scripts/cleanup/install.sh --days 90 --schedule weekly

# Uninstall automatic cleanup
./scripts/cleanup/uninstall.sh

# For detailed documentation, see:
./scripts/cleanup/README.md
```

### Claude Code Configuration
```bash
# Install Claude Code and AI CLI tools (via install.sh --ai-tools)
./install.sh --ai-tools

# Installation methods:
# - macOS/Linux: Native binary (claude) via curl | bash
# - Additional tools: Homebrew (macOS) or npm (Linux) for gemini-cli, codex

# Check installation status and configuration
claude doctor

# Update Claude Code
# Native binary: Auto-updates enabled by default
# Manual update: claude update

# Configuration file location
~/.claude/settings.json

# Auto-updates
# - Enabled by default for native binary installations
# - Auto-updates work seamlessly on both macOS and Linux

# MCP (Model Context Protocol) Servers
# MCP servers are automatically installed during ./install.sh --ai-tools
# Three servers are configured by default:
#   - context7 (HTTP): Up-to-date library documentation and code examples
#   - inspect_ai (SSE): UK AI Security Institute's LLM evaluation framework
#   - hydra (SSE): Facebook Research's configuration framework
#
# To manage MCP servers:
#   claude mcp list                       # List configured servers
#   claude mcp add <name> <url>           # Add additional MCP server
#   claude mcp remove <name>              # Remove MCP server
#
# See: https://docs.anthropic.com/en/docs/claude-code/mcp
#
# WARNING: Some MCP servers can consume significant context:
# - GitHub MCP: ~34k tokens (49 tools)
# - Consider disabling unused MCP servers to save context

# Deploy Claude Code configuration (sync across machines)
# Use deploy.sh --claude to automatically symlink claude/ to ~/.claude
./deploy.sh --claude

# Or manually:
# ln -sf /path/to/dotfiles/claude ~/.claude

# What's included in claude/:
# - CLAUDE.md: Global instructions for all projects
# - settings.json: Merged config (statusLine, permissions, hooks, notifications)
# - agents/: 13 specialized agents (experiment-designer, research-engineer, etc.)
# - notify.sh: Notification script for task completion
# - .gitignore: Comprehensive patterns (ignores runtime files, tracks config)
# - archive/: Hooks, scripts, docs from previous setups (for review)
```

### Docker/RunPod Commands
```bash
# Build RunPod Docker image
export DOCKER_DEFAULT_PLATFORM=linux/amd64
docker build -f runpod/johnh_dev.Dockerfile -t jplhughes1/runpod-dev .

# Test Docker image
docker run -it -v $PWD/runpod/entrypoint.sh:/dotfiles/runpod/entrypoint.sh -e USE_ZSH=true jplhughes1/runpod-dev /bin/zsh

# Push to Docker Hub
docker push jplhughes1/runpod-dev
```

## Architecture and Structure

### Core Configuration Files
- `config/zshrc.sh` - Main ZSH configuration, sources all other config files
- `config/aliases.sh` - General purpose aliases (git, tmux, file operations, slurm)
- `config/aliases_speechmatics.sh` - Environment-specific aliases
- `config/tmux.conf` - Tmux configuration
- `config/p10k.zsh` - Powerlevel10k theme configuration
- `config/key_bindings.sh` - Custom key bindings
- `config/extras.sh` - Additional shell configurations
- `config/vimrc` - Vim configuration
- `config/vscode_settings.json` - VSCode/Cursor settings (deployed to both editors)
- `config/vscode_extensions.txt` - Recommended VSCode/Cursor extensions (auto-installed)
- `config/macos_settings.sh` - macOS system defaults and preferences
- `config/gitconfig` - Git configuration template (deployed with smart merging)
- `config/gitignore_global` - Global gitignore patterns for Linux, Python, macOS
- `config/user.conf.example` - Template for customizing git user settings (copy to `user.conf`)

### Claude Code Configuration Directory
Located in `claude/` and designed to be symlinked to `~/.claude`:
- `CLAUDE.md` - Global instructions for Claude Code across all projects
- `settings.json` - Merged settings (statusLine, permissions, hooks, notifications)
- `notify.sh` - Notification script (terminal bell, banner, voice alerts)
- `.gitignore` - Comprehensive patterns (tracks config files, ignores runtime files)
- `agents/` - 13 specialized agents:
  - `application-writer.md` - Writing applications and formal documents
  - `code-reviewer.md` - Code review and quality checks
  - `context-summariser.md` - Context summarization for large codebases
  - `data-analyst.md` - Statistical analysis and data interpretation
  - `debugger.md` - Debugging and error investigation
  - `experiment-designer.md` - Experimental design and methodology
  - `literature-scout.md` - Literature review and paper search
  - `paper-writer.md` - Academic writing and paper composition
  - `research-advisor.md` - High-level research strategy
  - `research-engineer.md` - Full experiment implementation
  - `research-skeptic.md` - Critical evaluation and confound identification
  - `tooling-engineer.md` - Tool and utility development
- `archive/` - Previous hooks, scripts, docs (archived for review)

### Custom Binaries
Located in `custom_bins/` and automatically added to PATH:
- `rl` - readlink -f with clipboard copy functionality
- `tsesh` - Tmux session management utility
- `twin` - Tmux window management utility
- `yk` - Clipboard utility
- `tmux-clean` - Start tmux with clean environment (prevents variable pollution)

### ASCII Art System
- ASCII art files stored in `config/ascii_arts/`
- Default art displayed on shell startup from `config/start.txt`
- Can be customized during deployment with `--ascii` flag

### Automatic Cleanup System
Located in `scripts/cleanup/`:
- `cleanup_old_files.sh` - Main cleanup script (runs manually or via scheduled job)
- `install.sh` - Install scheduled cleanup job (macOS launchd or Linux cron)
- `uninstall.sh` - Remove scheduled cleanup job
- `README.md` - Comprehensive documentation

Features:
- Cleans `~/Downloads` and `~/Screenshots` directories
- Configurable retention period (default: 180 days / 6 months)
- Files moved to trash, not permanently deleted
- Dry run mode for safe testing
- Cross-platform (macOS and Linux)
- Scheduled execution (daily, weekly, or monthly)

### Environment Support
The dotfiles support multiple environments:
- **Local Mac/Linux** - Full feature set with Homebrew/apt packages
- **Remote Linux servers** - Streamlined setup for development VMs
- **RunPod containers** - Docker-based development environments with GPU support

### Package Management Integration
- **uv** - Python package manager, automatically sourced
- **Cargo/Rust** - Rust toolchain, conditionally loaded
- **pyenv** - Python version management, conditionally loaded  
- **micromamba** - Conda alternative, conditionally loaded
- **fnm** - Node version manager, conditionally loaded

### Key Features
- **Modular alias system** - Base aliases + environment-specific extensions
- **Conditional loading** - Tools only loaded if installed
- **Cross-platform compatibility** - Works on Mac (Homebrew) and Linux (apt)
- **GPU development support** - Slurm aliases and RunPod integration
- **Shell enhancements** - History substring search, autosuggestions, syntax highlighting
- **Smart git config** - Automatic deployment with conflict detection and resolution
- **Editor settings sync** - Automatic deployment of VSCode/Cursor settings to both editors
- **macOS optimizations** - Keyboard, Finder, and system preferences configured automatically
- **Automatic cleanup** - Optional scheduled cleanup for Downloads and Screenshots directories

## Tmux Environment Management

### Checking and Cleaning Tmux Global Environment
If tmux global environment has accumulated unwanted variables:
```bash
# Check what's in tmux global environment
tmux show-environment -g

# Start fresh tmux with clean environment (only essential vars)
tmux-clean  # Custom script that starts tmux with minimal env

# Nuclear option - restart tmux server (loses all sessions)
tmux kill-server
tmux-clean new
```

The `tmux-clean` script starts tmux with only essential variables (HOME, USER, SHELL, PATH, TERM, SSH_AUTH_SOCK), preventing environment pollution from the parent shell. Useful when you need a clean tmux environment without unwanted variables like API keys or virtual environments.

## Customization Patterns

### Adding New Aliases
Add general aliases to `config/aliases.sh` or create environment-specific files like `config/aliases_<environment>.sh`

### Adding New Dependencies
Add installation commands to `install.sh` with appropriate OS detection and optional flags

### Adding ASCII Art
Place new art files in `config/ascii_arts/` and reference with `--ascii=filename.txt` during deployment

### RunPod Customization
Modify `runpod/runpod_setup.sh` for container-specific setup requirements