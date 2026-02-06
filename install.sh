#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# Dotfiles Installation Script
# ═══════════════════════════════════════════════════════════════════════════════
# Installs dependencies on macOS or Linux. Configuration is in config.sh.
#
# Usage:
#   ./install.sh                      # Install with defaults from config.sh
#   ./install.sh --profile=server     # Use server profile
#   ./install.sh --no-ai-tools        # Disable AI tools
#   ./install.sh --extras             # Enable extras
#
# See config.sh for all available settings.
# ═══════════════════════════════════════════════════════════════════════════════
set -euo pipefail

# Script directory
DOT_DIR="$(cd "$(dirname "$0")" && pwd)"
export DOT_DIR

# Load configuration and helpers
source "$DOT_DIR/config.sh"
source "$DOT_DIR/scripts/shared/helpers.sh"

# ─── Help ─────────────────────────────────────────────────────────────────────

show_help() {
    cat <<EOF
Usage: ./install.sh [OPTIONS]

Install dotfile dependencies on macOS or Linux.
Configuration is in config.sh - edit it to change defaults.

OPTIONS:
    --profile=NAME    Use a profile: personal, work, server, minimal
    --zsh             Enable ZSH installation
    --tmux            Enable tmux installation
    --ai-tools        Enable AI CLI tools (Claude, Gemini, Codex)
    --extras          Enable extra CLI tools (hyperfine, lazygit, code2prompt)
    --cleanup         Enable automatic cleanup (macOS only)
    --docker          Enable Docker installation (Linux only)
    --experimental    Enable experimental features (ty type checker)
    --create-user     Create non-root dev user (Linux only)
    --no-<component>  Disable a component (e.g., --no-ai-tools)
    --force-reinstall Reinstall tools even if present

PROFILES (set in config.sh or via --profile):
    personal    Full setup with all tools (default)
    work        Personal + work-specific aliases
    server      Minimal server setup (no GUI tools)
    minimal     Nothing enabled - specify what you want

EXAMPLES:
    ./install.sh                        # Use defaults from config.sh
    ./install.sh --profile=server       # Server setup
    ./install.sh --extras --no-cleanup  # Add extras, skip cleanup
EOF
}

# Parse CLI arguments (overrides config.sh)
parse_args "$@"

# ─── Main Installation ────────────────────────────────────────────────────────

log_section "INSTALLING DOTFILES DEPENDENCIES"
echo "Platform: $PLATFORM"
echo "Profile: $PROFILE"
echo ""

# ─── Platform-Specific Package Managers ───────────────────────────────────────

if is_macos; then
    # Ensure Homebrew is installed
    if ! cmd_exists brew; then
        log_info "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        [[ $(uname -m) == "arm64" ]] && eval "$(/opt/homebrew/bin/brew shellenv)"
    fi

    # Modern bash (macOS ships with bash 3.2)
    if ! is_installed bash; then
        log_info "Installing modern bash..."
        brew_install bash
    fi

    # Core packages
    log_info "Installing core packages..."
    install_packages brew "${PACKAGES_CORE[@]}" "${PACKAGES_MACOS[@]}"

elif is_linux; then
    apt update -y 2>/dev/null || log_info "Skipping apt update (no permissions)"

    # Core packages via apt
    log_info "Installing core packages via apt..."
    install_packages apt "${PACKAGES_CORE[@]}" less nano nvtop lsof

    # Install mise for modern CLI tools
    install_mise

    # Modern CLI tools via mise
    log_info "Installing modern CLI tools..."
    for pkg in "${PACKAGES_LINUX_MISE[@]}"; do
        mise_install "$pkg"
    done
fi

# ─── GitHub CLI ───────────────────────────────────────────────────────────────

install_gh_cli

# ─── Gitleaks ─────────────────────────────────────────────────────────────────

if ! is_installed gitleaks; then
    log_info "Installing gitleaks..."
    if is_macos; then
        brew_install gitleaks
    else
        apt_install gitleaks || {
            log_info "Installing gitleaks from GitHub releases..."
            version=$(curl -s https://api.github.com/repos/gitleaks/gitleaks/releases/latest | grep -o '"tag_name": "v[^"]*' | cut -d'v' -f2 || echo "8.21.2")
            case "$(uname -m)" in
                x86_64)  arch="x64" ;;
                aarch64) arch="arm64" ;;
                *)       log_warning "Unsupported architecture for gitleaks" ;;
            esac
            if [[ -n "${arch:-}" ]]; then
                mkdir -p "$HOME/.local/bin"
                curl -sSL "https://github.com/gitleaks/gitleaks/releases/download/v${version}/gitleaks_${version}_linux_${arch}.tar.gz" -o /tmp/gitleaks.tar.gz && \
                tar -xzf /tmp/gitleaks.tar.gz -C /tmp && \
                mv /tmp/gitleaks "$HOME/.local/bin/" && \
                rm -f /tmp/gitleaks.tar.gz
            fi
        }
    fi
fi

# ─── Atuin (Shell History) ────────────────────────────────────────────────────

if ! is_installed atuin; then
    log_info "Installing Atuin..."
    if is_macos; then
        brew_install atuin
    else
        curl --proto '=https' --tlsv1.2 -LsSf https://setup.atuin.sh | sh 2>/dev/null || log_warning "Atuin installation failed"
    fi
fi

# ─── uv (Python Package Manager) ──────────────────────────────────────────────

if ! is_installed uv; then
    log_info "Installing uv..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
fi

# ─── ZSH ──────────────────────────────────────────────────────────────────────

if [[ "$INSTALL_ZSH" == "true" ]]; then
    if ! is_installed zsh; then
        log_info "Installing ZSH..."
        if is_macos; then
            brew_install zsh
        else
            apt_install zsh || "$DOT_DIR/scripts/helpers/install_zsh_local.sh"
        fi
    fi
    set_zsh_default
    install_ohmyzsh
fi

# ─── tmux ─────────────────────────────────────────────────────────────────────

if [[ "$INSTALL_TMUX" == "true" ]]; then
    if ! is_installed tmux; then
        log_info "Installing tmux..."
        if is_macos; then
            brew_install tmux
        else
            apt_install tmux
        fi
    fi
fi

# ─── Extras ───────────────────────────────────────────────────────────────────

if [[ "$INSTALL_EXTRAS" == "true" ]]; then
    log_section "INSTALLING EXTRAS"

    if is_macos; then
        install_packages brew "${PACKAGES_EXTRAS_MACOS[@]}"

        # code2prompt requires cargo
        if ! is_installed cargo; then
            log_info "Installing Rust..."
            curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --quiet
            source "$HOME/.cargo/env" 2>/dev/null || true
        fi
        if cmd_exists cargo && ! is_installed code2prompt; then
            log_info "Installing code2prompt..."
            cargo install code2prompt --quiet 2>/dev/null || log_warning "code2prompt failed"
        fi
    else
        for pkg in "${PACKAGES_EXTRAS_LINUX[@]}"; do
            mise_install "$pkg"
        done
    fi

    # shell-ask
    if cmd_exists npm && ! is_installed ask; then
        log_info "Installing shell-ask..."
        npm i -g shell-ask 2>/dev/null || true
    fi
fi

# ─── AI Tools ─────────────────────────────────────────────────────────────────

if [[ "$INSTALL_AI_TOOLS" == "true" ]]; then
    log_section "INSTALLING AI CLI TOOLS 🤖"

    # Claude Code
    if ! is_installed claude; then
        log_info "Installing Claude Code..."
        curl -fsSL https://claude.ai/install.sh | bash || log_warning "Claude Code installation failed"

        # Alpine Linux dependencies
        if is_linux && cmd_exists apk; then
            log_info "Checking Alpine dependencies..."
            apk add libgcc libstdc++ ripgrep 2>/dev/null || true
            export USE_BUILTIN_RIPGREP=0
        fi
    fi

    # Install bun (preferred package manager for global CLI tools on Linux)
    if is_linux && ! cmd_exists bun; then
        log_info "Installing bun..."
        curl -fsSL https://bun.sh/install | bash
        export BUN_INSTALL="$HOME/.bun"
        export PATH="$BUN_INSTALL/bin:$PATH"
    fi

    # Ensure npm as fallback for global CLI installs
    if ! cmd_exists bun && ! cmd_exists npm; then
        log_info "Installing npm..."
        if is_macos; then
            brew_install node
        else
            apt_install npm
        fi
    fi

    # Gemini CLI
    if ! is_installed gemini; then
        log_info "Installing Gemini CLI..."
        if is_macos; then
            brew_install gemini-cli
        elif cmd_exists bun; then
            bun add -g @google/gemini-cli &>/dev/null || log_warning "Gemini CLI failed"
        elif cmd_exists npm; then
            npm install -g @google/gemini-cli &>/dev/null || log_warning "Gemini CLI failed"
        fi
    fi

    # Codex CLI
    if ! is_installed codex; then
        log_info "Installing Codex CLI..."
        if is_macos; then
            brew_install codex
        elif cmd_exists bun; then
            bun add -g @openai/codex &>/dev/null || log_warning "Codex CLI failed"
        elif cmd_exists npm; then
            npm install -g @openai/codex &>/dev/null || log_warning "Codex CLI failed"
        fi
    fi

    # Configure MCP servers
    if cmd_exists claude; then
        log_info "Configuring MCP servers..."
        for server in "${MCP_SERVERS[@]}"; do
            IFS=':' read -r name url <<< "$server"
            claude mcp remove "$name" &>/dev/null || true
            if [[ "$url" == npx* ]]; then
                # JSON-based config for npx
                args="${url#npx }"
                claude mcp add-json --scope user "$name" "{\"command\":\"npx\",\"args\":[\"${args}\"]}" 2>&1 && \
                    log_success "$name configured" || log_warning "$name failed"
            else
                # HTTP transport
                claude mcp add --scope user --transport http "$name" "$url" 2>&1 && \
                    log_success "$name configured" || log_warning "$name failed"
            fi
        done
    fi

    log_success "AI CLI tools installation complete"
fi

# ─── Docker (Linux) ──────────────────────────────────────────────────────────

if [[ "$INSTALL_DOCKER" == "true" ]] && is_linux; then
    install_docker
fi

# ─── Cleanup Automation ───────────────────────────────────────────────────────

if [[ "$INSTALL_CLEANUP" == "true" ]] && is_macos; then
    log_section "INSTALLING AUTOMATIC CLEANUP 🧹"
    if [[ -f "$DOT_DIR/scripts/cleanup/install.sh" ]]; then
        "$DOT_DIR/scripts/cleanup/install.sh" --non-interactive || log_warning "Cleanup installation failed"
    else
        log_warning "Cleanup install script not found"
    fi
fi

# ─── Experimental Features ────────────────────────────────────────────────────

if [[ "$INSTALL_EXPERIMENTAL" == "true" ]]; then
    log_section "INSTALLING EXPERIMENTAL FEATURES ⚗️"
    log_warning "ty is in alpha/preview - not recommended for production"

    if ! is_installed ty && cmd_exists uv; then
        log_info "Installing ty via uv..."
        uv tool install ty 2>/dev/null || log_warning "ty installation failed"
    fi

    log_success "Experimental features installation complete"
fi

# ─── Create User (Linux) ──────────────────────────────────────────────────────

if [[ "$INSTALL_CREATE_USER" == "true" ]] && is_linux; then
    create_dev_user
fi

# ─── macOS Settings ───────────────────────────────────────────────────────────

if is_macos && [[ -f "$DOT_DIR/config/macos_settings.sh" ]]; then
    log_info "Configuring macOS system defaults..."
    "$DOT_DIR/config/macos_settings.sh" || log_warning "macOS settings had some errors"
fi

# ─── Finicky (macOS) ──────────────────────────────────────────────────────────

if is_macos && ! is_cask_installed finicky; then
    log_info "Installing Finicky..."
    brew_install finicky true
fi

# ─── Done ─────────────────────────────────────────────────────────────────────

echo ""
log_success "Installation complete!"
echo ""
echo "Next steps:"
echo "  1. Run ./deploy.sh to deploy configurations"
echo "  2. Restart your terminal or run: source ~/.zshrc"
