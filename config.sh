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
# Available: personal, server, minimal
# - personal: Full setup with all tools (default)
# - server:   Minimal server setup (no GUI tools, no cleanup)
# - minimal:  Nothing enabled by default
PROFILE="${PROFILE:-personal}"

# ─── Install Components ───────────────────────────────────────────────────────
INSTALL_ZSH=true
INSTALL_TMUX=true
INSTALL_AI_TOOLS=true           # Claude Code, Gemini CLI, Codex CLI
INSTALL_CLEANUP=true            # Automatic cleanup (macOS only)
INSTALL_DOCKER=true             # Docker (Linux only)
INSTALL_EXPERIMENTAL=true       # ty type checker
INSTALL_CREATE_USER=true        # Create non-root dev user (Linux only, guarded by is_linux + EUID check)
INSTALL_EXTRAS=false            # hyperfine, lazygit, code2prompt

# ─── Deploy Components ────────────────────────────────────────────────────────
DEPLOY_VIM=true
DEPLOY_EDITOR=true              # VSCode/Cursor settings (merges with existing)
DEPLOY_CLAUDE=true              # Claude Code config (~/.claude symlink)
DEPLOY_CODEX=true               # Codex CLI config (~/.codex symlink)
DEPLOY_GHOSTTY=true             # Ghostty terminal config
DEPLOY_HTOP=true                # htop process viewer config
DEPLOY_PDB=true                 # pdb++ debugger config (high-contrast colors)
DEPLOY_MATPLOTLIB=true          # Matplotlib styles (anthropic, deepmind)
DEPLOY_GIT_HOOKS=true           # Global git hooks (secret detection)
DEPLOY_SECRETS=true             # Sync secrets with GitHub gist
DEPLOY_CLEANUP=true             # File cleanup: Downloads/Screenshots (macOS only)
DEPLOY_CLAUDE_CLEANUP=true      # Claude Code idle session cleanup (both platforms)
DEPLOY_AI_UPDATE=true           # AI tools auto-update daily (both platforms)
DEPLOY_BREW_UPDATE=true         # Weekly package upgrade + cleanup (brew/apt/dnf/pacman)
DEPLOY_KEYBOARD=true            # Keyboard repeat enforcement at login (macOS only)
DEPLOY_ALIASES=()               # Additional alias scripts: ("inspect")
DEPLOY_SERENA=false             # Serena MCP config (~/.serena symlink)

# ─── Deploy Modifiers ─────────────────────────────────────────────────────────
DEPLOY_APPEND=false             # Append to existing configs instead of overwrite
DEPLOY_ASCII_FILE="start.txt"   # ASCII art file for shell startup

# ─── Identity & Secrets ───────────────────────────────────────────────────────
GIT_USER_NAME="yulonglin"
GIT_USER_EMAIL="30549145+yulonglin@users.noreply.github.com"
SECRETS_GIST_ID="3cc239f160a2fe8c9e6a14829d85a371"  # Public identifier (like repo name), not a secret

# ─── AI Tools Configuration ───────────────────────────────────────────────────
# MCP servers to configure for Claude Code
MCP_SERVERS=(
    "context7:https://mcp.context7.com/mcp"
)

# Local MCP servers built from source (require Go)
# Format: "name:repo:binary_name:env_var_for_token"
MCP_SERVERS_LOCAL=(
    "slack:yulonglin/slack-mcp-server:slack-mcp-server:SLACK_MCP_XOXP_TOKEN"
)  # Consider if this is safe to include here, or if it'll break something

# ─── Core Packages ────────────────────────────────────────────────────────────
# Installed on all platforms
PACKAGES_CORE=(
    "jq"
    "fzf"
    "htop"
    "rsync"
    "shellcheck"  # Shell script linter
    "tldr"        # Simplified man pages
)

# macOS-specific packages (via Homebrew)
PACKAGES_MACOS=(
    "coreutils"  # GNU utilities on macOS (gdate, gawk, gsed)
    "bat"
    "eza"
    "zoxide"
    "delta"
    "gitleaks"
    "dust"
    "fd"
    "ripgrep"
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
    "ubi:PaulJuliusMartinez/jless"  # ubi: required — no aarch64-linux binaries in releases
)

# Extra packages (--extras flag)
PACKAGES_EXTRAS_MACOS=(
    "hyperfine"
    "lazygit"
)

PACKAGES_EXTRAS_LINUX=(
    "github:sharkdp/hyperfine"
    "github:jesseduffield/lazygit"
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
        server)
            # Minimal server setup
            INSTALL_AI_TOOLS=false
            INSTALL_CLEANUP=false
            INSTALL_DOCKER=false
            INSTALL_EXTRAS=false
            DEPLOY_EDITOR=false
            DEPLOY_SERENA=false
            DEPLOY_GHOSTTY=false
            DEPLOY_HTOP=false
            DEPLOY_PDB=false
            DEPLOY_MATPLOTLIB=false
            DEPLOY_CLEANUP=false
            DEPLOY_CLAUDE_CLEANUP=false
            DEPLOY_AI_UPDATE=false
            DEPLOY_BREW_UPDATE=false
            DEPLOY_KEYBOARD=false
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
            DEPLOY_SERENA=false
            DEPLOY_GHOSTTY=false
            DEPLOY_HTOP=false
            DEPLOY_PDB=false
            DEPLOY_MATPLOTLIB=false
            DEPLOY_GIT_HOOKS=false
            DEPLOY_SECRETS=false
            DEPLOY_CLEANUP=false
            DEPLOY_CLAUDE_CLEANUP=false
            DEPLOY_AI_UPDATE=false
            DEPLOY_BREW_UPDATE=false
            DEPLOY_KEYBOARD=false
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

# User overrides (gitignored) — create config.local.sh to customize defaults
# Precedence: defaults -> apply_profile() -> config.local.sh -> CLI flags (parse_args)
[[ -n "$DOT_DIR" && -f "$DOT_DIR/config.local.sh" ]] && source "$DOT_DIR/config.local.sh"

# Platform-specific defaults
if is_linux; then
    INSTALL_CLEANUP=false       # File cleanup uses launchd (macOS only)
    DEPLOY_CLEANUP=false        # File cleanup uses launchd (macOS only)
    # DEPLOY_CLAUDE_CLEANUP stays true - works with cron on Linux
    INSTALL_CREATE_USER=true    # Useful for containers
    # INSTALL_DOCKER=true is already default
elif is_macos; then
    INSTALL_DOCKER=false        # Use Docker Desktop on macOS
fi
