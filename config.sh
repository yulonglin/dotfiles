#!/usr/bin/env zsh
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

# ─── Component Registry (single source of truth) ────────────────────────────
# Format: "name|description|platform|default"
# - name: CLI flag name (dashes OK, auto-converted to UPPER_SNAKE for variables)
# - description: TUI menu display text
# - platform: all, macos, linux (controls TUI visibility; actual code may have its own guards)
# - default: true/false (initial value, overridden by profiles → config.local.sh → CLI flags)
#
# To add a new component: add one line here, then add the implementation block
# in install.sh/deploy.sh. TUI menu, --flag, --no-flag, --only all work automatically.

INSTALL_REGISTRY=(
    "core|Core packages, CLI tools, gh, SOPS/age, uv|all|true"
    "zsh|ZSH + oh-my-zsh + powerlevel10k theme|all|true"
    "tmux|Terminal multiplexer|all|true"
    "ai-tools|Claude Code, Gemini CLI, Codex CLI|all|true"
    "extras|hyperfine, gitui, code2prompt, terminal-notifier|all|true"
    "cleanup|Automatic cleanup (macOS only)|all|true"
    "experimental|ty type checker, zerobrew|all|true"
    "macos-settings|macOS system defaults (Dock, Finder, keyboard)|macos|true"
    "finicky|Finicky browser routing|macos|true"
    "docker|Docker engine + compose|linux|true"
    "pueue|Pueue job scheduler + pueued daemon|linux|true"
    "create-user|Create non-root dev user|linux|true"
)

DEPLOY_REGISTRY=(
    "shell|ZSH config, aliases, key bindings|all|true"
    "tmux|tmux.conf + TPM plugins|all|true"
    "git-config|gitconfig, global gitignore, ripgrep config|all|true"
    "vim|vimrc|all|true"
    "editor|VSCode/Cursor settings + extensions (merges)|all|true"
    "claude|Claude Code config symlink (~/.claude)|all|true"
    "codex|Codex CLI config symlink (~/.codex)|all|true"
    "ghostty|Ghostty terminal config (symlinked)|all|true"
    "zed|Zed editor config (symlinked)|all|true"
    "htop|htop config with dynamic CPU meters|all|true"
    "pdb|pdb++ debugger config (high-contrast)|all|true"
    "matplotlib|Style files: anthropic, deepmind, petri|all|true"
    "git-hooks|Global pre-commit secret detection|all|true"
    "secrets|Sync SSH/git identity via GitHub gist|all|true"
    "secrets-env|Decrypt SOPS-encrypted API keys (age)|all|true"
    "pkg-configs|Package manager security configs (min-release-age)|all|true"
    "dep-audit|Weekly dependency audit (supply chain defense)|all|true"
    "cleanup|Auto-cleanup Downloads/Screenshots (macOS)|all|true"
    "claude-cleanup|Remove idle Claude sessions after 24h|all|true"
    "ai-update|Daily auto-update: Claude, Gemini, Codex|all|true"
    "brew-update|Weekly package upgrade + cleanup|all|true"
    "claude-tools|Build claude-tools Rust binary|all|true"
    "finicky|Browser routing config (symlinked)|macos|true"
    "file-apps|Default editor for coding file types|macos|true"
    "keyboard|Keyboard repeat rate enforcement at login|macos|true"
    "bedtime|Bedtime timezone enforcement|macos|true"
    "text-replacements|Sync macOS + Alfred text replacements|macos|true"
    "mouseless|Keyboard-driven mouse control|macos|true"
    "vpn|NordVPN + Tailscale split tunnel daemon|macos|true"
    "pueue|Pueue + systemd resource slices|linux|true"
    "bws|Bitwarden Secrets Manager CLI|all|false"
    "serena|Serena MCP server config (symlinked)|all|true"
)

# Initialize INSTALL_*/DEPLOY_* variables from registry
_init_component_vars() {
    local entry name var_name default
    for entry in "${INSTALL_REGISTRY[@]}"; do
        name="${entry%%|*}"
        default="${entry##*|}"
        var_name="${(U)name//-/_}"
        typeset -g "INSTALL_${var_name}=${default}"
    done
    for entry in "${DEPLOY_REGISTRY[@]}"; do
        name="${entry%%|*}"
        default="${entry##*|}"
        var_name="${(U)name//-/_}"
        typeset -g "DEPLOY_${var_name}=${default}"
    done
}
_init_component_vars

# ─── Non-Registry Variables ──────────────────────────────────────────────────
DEPLOY_ALIASES=()               # Additional alias scripts: ("inspect") — array, not boolean

# ─── Deploy Modifiers ─────────────────────────────────────────────────────────
DEPLOY_APPEND=false             # Append to existing configs instead of overwrite
DEPLOY_ASCII_FILE="start.txt"   # ASCII art file for shell startup

# ─── Identity & Secrets ───────────────────────────────────────────────────────
# Edit these values for your setup. Everything else should work out of the box.
DOTFILES_USERNAME="${DOTFILES_USERNAME:-yulong}"
DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/yulonglin/dotfiles.git}"
GIT_USER_NAME="yulonglin"
GIT_USER_EMAIL="30549145+yulonglin@users.noreply.github.com"
GIST_SYNC_ID="${GIST_SYNC_ID:-3cc239f160a2fe8c9e6a14829d85a371}"  # Gist used for config sync (SSH, git identity)

# ─── AI Tools Configuration ───────────────────────────────────────────────────
# MCP servers to configure for Claude Code
MCP_SERVERS=(
    "context7:https://mcp.context7.com/mcp"
)

# Local MCP servers built from source (require Go)
# Format: "name:repo:binary_name:env_var_for_token"
MCP_SERVERS_LOCAL=()

# Claude Code Plugin Marketplaces
# Format: "name:source" (source = GitHub user/repo)
# Both official and custom marketplaces need explicit registration + plugin install
PLUGIN_MARKETPLACES=(
    "claude-plugins-official:anthropics/claude-plugins-official"
    "ai-safety-plugins:yulonglin/ai-safety-plugins"
)

# Official plugins to auto-install from claude-plugins-official marketplace.
# Matches everything referenced in settings.json enabledPlugins.
OFFICIAL_PLUGINS=(
    # Base profile (always-on)
    "superpowers" "hookify" "plugin-dev" "commit-commands"
    "claude-md-management" "context7"
    # Development
    "code-simplifier" "code-review" "security-guidance" "feature-dev"
    "pr-review-toolkit" "playground" "ralph-loop"
    # Integrations
    "Notion" "vercel" "playwright"
    # Language servers
    "pyright-lsp" "typescript-lsp"
    # Specialized
    "frontend-design"
)

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
    "just"
    "sd"          # sed replacement (preferred over sed)
    "duf"         # df replacement (disk free space)
    "gum"         # interactive shell UI (toggle menus)
    "vivid"       # LS_COLORS theme generator (catppuccin-mocha)
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
    "github:PaulJuliusMartinez/jless"
    "github:casey/just"
    "github:chmln/sd"
    "github:muesli/duf"
    "github:charmbracelet/gum"
    "github:sharkdp/vivid"
)

# Extra packages (--extras flag)
PACKAGES_EXTRAS_MACOS=(
    "hyperfine"
    "gitui"
    "terminal-notifier"
)

PACKAGES_EXTRAS_LINUX=(
    "github:sharkdp/hyperfine"
    "github:extrawurst/gitui"
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
            INSTALL_MACOS_SETTINGS=false
            INSTALL_FINICKY=false
            DEPLOY_EDITOR=false
            DEPLOY_SERENA=false
            DEPLOY_GHOSTTY=false
            DEPLOY_ZED=false
            DEPLOY_HTOP=false
            DEPLOY_PDB=false
            DEPLOY_MATPLOTLIB=false
            DEPLOY_CLEANUP=false
            DEPLOY_CLAUDE_CLEANUP=false
            DEPLOY_AI_UPDATE=false
            DEPLOY_BREW_UPDATE=false
            DEPLOY_KEYBOARD=false
            DEPLOY_BEDTIME=false
            DEPLOY_SECRETS=false
            DEPLOY_SECRETS_ENV=false
            DEPLOY_FINICKY=false
            DEPLOY_FILE_APPS=false
            DEPLOY_CLAUDE_TOOLS=false
            ;;
        minimal)
            # Nothing enabled — derived from registry (no manual list to drift)
            local _entry _name _var
            for _entry in "${INSTALL_REGISTRY[@]}"; do
                _name="${_entry%%|*}"; _var="${(U)_name//-/_}"
                typeset -g "INSTALL_${_var}=false"
            done
            for _entry in "${DEPLOY_REGISTRY[@]}"; do
                _name="${_entry%%|*}"; _var="${(U)_name//-/_}"
                typeset -g "DEPLOY_${_var}=false"
            done
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
