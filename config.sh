#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# Dotfiles Configuration
# ═══════════════════════════════════════════════════════════════════════════════
# Single source of truth for all installation and deployment settings.
# Edit this file to customize your setup, then run:
#   ./install.sh                    # Install dependencies
#   ./deploy.sh                     # Deploy configurations
#
# Or override at runtime:
#   ./install.sh --profile=server   # Use server profile
#   ./install.sh --no-ai-tools      # Disable specific component
# ═══════════════════════════════════════════════════════════════════════════════

# ─── Profile ──────────────────────────────────────────────────────────────────
# Available: personal, work, server, minimal
# - personal: Full setup with all tools (default)
# - work:     Personal + work-specific aliases
# - server:   Minimal server setup (no GUI tools, no cleanup)
# - minimal:  Nothing enabled by default
PROFILE="${PROFILE:-personal}"

# ─── Install Components ───────────────────────────────────────────────────────
INSTALL_ZSH=true
INSTALL_TMUX=true
INSTALL_AI_TOOLS=true           # Claude Code, Gemini CLI, Codex CLI
INSTALL_EXTRAS=false            # hyperfine, lazygit, code2prompt
INSTALL_CLEANUP=true            # Automatic cleanup (macOS only)
INSTALL_DOCKER=true             # Docker (Linux only)
INSTALL_EXPERIMENTAL=false      # ty type checker
INSTALL_CREATE_USER=false       # Create non-root dev user (Linux only)

# ─── Deploy Components ────────────────────────────────────────────────────────
DEPLOY_VIM=true
DEPLOY_EDITOR=true              # VSCode/Cursor settings (merges with existing)
DEPLOY_CLAUDE=true              # Claude Code config (~/.claude symlink)
DEPLOY_CODEX=true               # Codex CLI config (~/.codex symlink)
DEPLOY_GHOSTTY=true             # Ghostty terminal config
DEPLOY_HTOP=true                # htop process viewer config
DEPLOY_MATPLOTLIB=true          # Matplotlib styles (anthropic, deepmind)
DEPLOY_GIT_HOOKS=true           # Global git hooks (secret detection)
DEPLOY_SECRETS=true             # Sync secrets with GitHub gist
DEPLOY_CLEANUP=true             # Automatic cleanup (macOS only)
DEPLOY_ALIASES=()               # Additional alias scripts: ("speechmatics" "inspect")

# ─── Deploy Modifiers ─────────────────────────────────────────────────────────
DEPLOY_APPEND=false             # Append to existing configs instead of overwrite
DEPLOY_ASCII_FILE="start.txt"   # ASCII art file for shell startup

# ─── Identity & Secrets ───────────────────────────────────────────────────────
GIT_USER_NAME="yulonglin"
GIT_USER_EMAIL="30549145+yulonglin@users.noreply.github.com"
SECRETS_GIST_ID="3cc239f160a2fe8c9e6a14829d85a371"

# ─── AI Tools Configuration ───────────────────────────────────────────────────
# MCP servers to configure for Claude Code
MCP_SERVERS=(
    "context7:https://mcp.context7.com/mcp"
    "gitmcp:npx mcp-remote https://gitmcp.io/docs"
)

# ─── Core Packages ────────────────────────────────────────────────────────────
# Installed on all platforms
PACKAGES_CORE=(
    "jq"
    "fzf"
    "htop"
    "ncdu"
    "rsync"
    "shellcheck"  # Shell script linter
    "tldr"        # Simplified man pages
)

# macOS-specific packages (via Homebrew)
PACKAGES_MACOS=(
    "coreutils"
    "bat"
    "eza"
    "zoxide"
    "delta"
    "gitleaks"
    "btop"
    "dust"
    "jless"
)

# Linux packages (via mise github: backend)
PACKAGES_LINUX_MISE=(
    "github:sharkdp/bat"
    "github:eza-community/eza"
    "github:sharkdp/fd"
    "github:BurntSushi/ripgrep"
    "github:dandavison/delta"
    "github:bootandy/dust"
    "github:ajeetdsouza/zoxide"
    "ubi:PaulJuliusMartinez/jless"
)

# Extra packages (--extras flag)
PACKAGES_EXTRAS_MACOS=(
    "fd"
    "ripgrep"
    "hyperfine"
    "lazygit"
)

PACKAGES_EXTRAS_LINUX=(
    "ubi:sharkdp/hyperfine"
    "ubi:jesseduffield/lazygit"
    "cargo:code2prompt"
)

# ═══════════════════════════════════════════════════════════════════════════════
# Profile Presets
# ═══════════════════════════════════════════════════════════════════════════════

apply_profile() {
    local profile="${1:-$PROFILE}"

    case "$profile" in
        personal)
            # Default - everything enabled (values above)
            ;;
        work)
            # Personal + work aliases
            DEPLOY_ALIASES=("speechmatics")
            ;;
        server)
            # Minimal server setup
            INSTALL_AI_TOOLS=false
            INSTALL_CLEANUP=false
            INSTALL_DOCKER=false
            INSTALL_EXTRAS=false
            DEPLOY_EDITOR=false
            DEPLOY_GHOSTTY=false
            DEPLOY_HTOP=false
            DEPLOY_MATPLOTLIB=false
            DEPLOY_CLEANUP=false
            DEPLOY_SECRETS=false
            ;;
        minimal)
            # Nothing enabled - specify what you want explicitly
            INSTALL_ZSH=false
            INSTALL_TMUX=false
            INSTALL_AI_TOOLS=false
            INSTALL_DOCKER=false
            INSTALL_EXTRAS=false
            INSTALL_CLEANUP=false
            INSTALL_EXPERIMENTAL=false
            DEPLOY_VIM=false
            DEPLOY_EDITOR=false
            DEPLOY_CLAUDE=false
            DEPLOY_CODEX=false
            DEPLOY_GHOSTTY=false
            DEPLOY_HTOP=false
            DEPLOY_MATPLOTLIB=false
            DEPLOY_GIT_HOOKS=false
            DEPLOY_SECRETS=false
            DEPLOY_CLEANUP=false
            ;;
        *)
            echo "Warning: Unknown profile '$profile', using personal" >&2
            ;;
    esac
}

# ═══════════════════════════════════════════════════════════════════════════════
# Platform Detection (set automatically)
# ═══════════════════════════════════════════════════════════════════════════════

detect_platform() {
    case "$(uname -s)" in
        Darwin*) PLATFORM="macos" ;;
        Linux*)  PLATFORM="linux" ;;
        *)       PLATFORM="unknown" ;;
    esac
    export PLATFORM
}

is_macos() { [[ "$PLATFORM" == "macos" ]]; }
is_linux() { [[ "$PLATFORM" == "linux" ]]; }

# ═══════════════════════════════════════════════════════════════════════════════
# Auto-initialization
# ═══════════════════════════════════════════════════════════════════════════════

# Detect platform on source
detect_platform

# Apply profile if set (can be overridden by CLI)
[[ -n "$PROFILE" ]] && apply_profile "$PROFILE"

# Platform-specific defaults
if is_linux; then
    INSTALL_CLEANUP=false       # launchd not available
    DEPLOY_CLEANUP=false
    INSTALL_CREATE_USER=true    # Useful for containers
    # INSTALL_DOCKER=true is already default
elif is_macos; then
    INSTALL_DOCKER=false        # Use Docker Desktop on macOS
fi
