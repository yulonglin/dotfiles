#!/usr/bin/env zsh
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

PROFILES:
    --profile=NAME    Use a profile: personal, server, minimal
    --default         Safe base for shared/new machines (alias for --profile=server)
    --minimal         Suppress ALL components — specify what you want explicitly
    --no-defaults     Same as --minimal (clearer name)
    --server          Server-appropriate subset
    --personal        Full personal setup (default)

SELECTIVE INSTALLATION:
    --only COMP...    Install ONLY these components, nothing else
                      Examples:
                        --only zsh tmux           # space-separated
                        --only zsh,tmux           # comma-separated
                        --only zsh --only tmux    # repeatable
                      Cannot be mixed with profiles or --component flags.

COMPONENTS:
    --zsh             Enable ZSH installation
    --tmux            Enable tmux installation
    --ai-tools        Enable AI CLI tools (Claude, Gemini, Codex)
    --extras          Enable extra CLI tools (hyperfine, gitui, code2prompt)
    --cleanup         Enable automatic cleanup (macOS only)
    --docker          Enable Docker installation (Linux only)
    --experimental    Enable experimental features (ty type checker, zerobrew)
    --create-user     Create non-root dev user (Linux only)
    --no-<component>  Disable a component (e.g., --no-ai-tools)
    --force-reinstall Reinstall tools even if present
    --non-interactive Skip interactive component menu

EXAMPLES:
    ./install.sh                        # Use defaults from config.sh
    ./install.sh --default              # Safe base for shared machines
    ./install.sh --only zsh tmux        # Only zsh and tmux, nothing else
    ./install.sh --extras --no-cleanup  # Add extras, skip cleanup
EOF
}

# Parse CLI arguments (overrides config.sh)
parse_args "$@"
show_component_menu install

# ─── Main Installation ────────────────────────────────────────────────────────

log_section "INSTALLING DOTFILES DEPENDENCIES"
echo "Platform: $PLATFORM"
echo "Profile: $PROFILE"
echo ""

# ─── Core Packages & Tools ────────────────────────────────────────────────────

if [[ "$INSTALL_CORE" == "true" ]]; then

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
    # Skip apt update if cache is less than 1 hour old
    apt_cache="/var/lib/apt/lists/partial"
    if [[ ! -d "$apt_cache" ]] || [[ $(( $(date +%s) - $(stat -c %Y "$apt_cache" 2>/dev/null || echo 0) )) -gt 3600 ]]; then
        apt update 2>/dev/null || log_info "Skipping apt update (no permissions)"
    else
        log_info "apt cache fresh (< 1h old) — skipping update"
    fi

    # Core packages via apt
    log_info "Installing core packages via apt..."
    install_packages apt "${PACKAGES_CORE[@]}" less nano nvtop lsof unzip

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

# ─── SOPS + age + direnv (Encrypted Secrets) ─────────────────────────────────

if ! is_installed sops; then
    log_info "Installing sops..."
    if is_macos; then
        brew_install sops
    else
        sops_ver=$(curl -s https://api.github.com/repos/getsops/sops/releases/latest | grep -o '"tag_name": "v[^"]*' | cut -d'v' -f2)
        sops_ver="${sops_ver:-3.9.4}"
        case "$(uname -m)" in
            x86_64)  sops_arch="amd64" ;;
            aarch64) sops_arch="arm64" ;;
        esac
        if [[ -n "${sops_arch:-}" ]]; then
            mkdir -p "$HOME/.local/bin"
            curl -sSL "https://github.com/getsops/sops/releases/download/v${sops_ver}/sops-v${sops_ver}.linux.${sops_arch}" -o "$HOME/.local/bin/sops" && \
                chmod +x "$HOME/.local/bin/sops"
        fi
    fi
fi

if ! is_installed age; then
    log_info "Installing age..."
    if is_macos; then
        brew_install age
    else
        age_ver=$(curl -s https://api.github.com/repos/FiloSottile/age/releases/latest | grep -o '"tag_name": "v[^"]*' | cut -d'v' -f2)
        age_ver="${age_ver:-1.2.1}"
        case "$(uname -m)" in
            x86_64)  age_arch="amd64" ;;
            aarch64) age_arch="arm64" ;;
        esac
        if [[ -n "${age_arch:-}" ]]; then
            mkdir -p "$HOME/.local/bin"
            curl -sSL "https://github.com/FiloSottile/age/releases/download/v${age_ver}/age-v${age_ver}-linux-${age_arch}.tar.gz" -o /tmp/age.tar.gz && \
                tar -xzf /tmp/age.tar.gz -C /tmp && \
                mv /tmp/age/age /tmp/age/age-keygen "$HOME/.local/bin/" && \
                rm -rf /tmp/age.tar.gz /tmp/age
        fi
    fi
fi

if ! is_installed direnv; then
    log_info "Installing direnv..."
    if is_macos; then
        brew_install direnv
    else
        curl -sfL https://direnv.net/install.sh | bash 2>/dev/null || log_warning "direnv installation failed"
    fi
fi

# Ensure ~/.local/bin is in PATH for this session (Linux binary installs)
[[ -d "$HOME/.local/bin" ]] && export PATH="$HOME/.local/bin:$PATH"

# ─── uv (Python Package Manager) ──────────────────────────────────────────────

if ! is_installed uv; then
    log_info "Installing uv..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
fi

fi  # INSTALL_CORE

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

    # Rust toolchain (needed for code2prompt)
    if ! is_installed cargo; then
        log_info "Installing Rust..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --quiet
    fi
    source "$HOME/.cargo/env" 2>/dev/null || true

    if is_macos; then
        install_packages brew "${PACKAGES_EXTRAS_MACOS[@]}"

        if cmd_exists cargo && ! is_installed code2prompt; then
            log_info "Installing code2prompt..."
            cargo install code2prompt --quiet 2>/dev/null || log_warning "code2prompt failed"
        fi
    else
        for pkg in "${PACKAGES_EXTRAS_LINUX[@]}"; do
            mise_install "$pkg"
        done
    fi
fi

# ─── AI Tools ─────────────────────────────────────────────────────────────────

if [[ "$INSTALL_AI_TOOLS" == "true" ]]; then
    log_section "INSTALLING AI CLI TOOLS 🤖"

    # Rust toolchain (needed for claude-tools build in deploy.sh)
    if ! is_installed cargo; then
        log_info "Installing Rust toolchain (user-level, no root needed)..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --quiet
    fi
    # Ensure cargo is in PATH for this session (installer modifies shell profile, not current env)
    source "$HOME/.cargo/env" 2>/dev/null || true

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
    # Ensure claude is in PATH for this session
    [[ -d "$HOME/.claude/bin" ]] && export PATH="$HOME/.claude/bin:$PATH"

    # Install bun (preferred package manager for global CLI tools on Linux)
    if is_linux && ! cmd_exists bun; then
        log_info "Installing bun..."
        curl -fsSL https://bun.sh/install | bash
        export BUN_INSTALL="$HOME/.bun"
        export PATH="$BUN_INSTALL/bin:$PATH"
    fi

    # Gemini CLI
    if ! is_installed gemini; then
        log_info "Installing Gemini CLI..."
        if is_macos; then
            brew_install gemini-cli
        elif cmd_exists bun; then
            bun add -g @google/gemini-cli &>/dev/null || log_warning "Gemini CLI failed"
        else
            log_warning "bun is required to install Gemini CLI on Linux; skipping"
        fi
    fi

    # Codex CLI
    if ! is_installed codex; then
        log_info "Installing Codex CLI..."
        if is_macos; then
            brew_install codex
        elif cmd_exists bun; then
            bun add -g @openai/codex &>/dev/null || log_warning "Codex CLI failed"
        else
            log_warning "bun is required to install Codex CLI on Linux; skipping"
        fi
    fi

    # Coven (lightweight Claude interface with better display than raw `claude -p`)
    if is_macos && ! is_installed coven; then
        log_info "Installing Coven..."
        brew tap Crazytieguy/tap 2>/dev/null && brew_install coven || log_warning "Coven installation failed"
    fi

    # Configure MCP servers (HTTP/npx)
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

    # Build and configure local MCP servers (stdio, built from source)
    if cmd_exists go && cmd_exists claude && [[ ${#MCP_SERVERS_LOCAL[@]} -gt 0 ]]; then
        log_info "Building local MCP servers..."
        mcp_base="$HOME/code/marketplaces"
        mkdir -p "$mcp_base"

        for entry in "${MCP_SERVERS_LOCAL[@]}"; do
            IFS=':' read -r name repo binary token_var <<< "$entry"
            repo_dir="$mcp_base/$(basename "$repo")"
            binary_path="$repo_dir/$binary"

            # Clone or update
            if [[ -d "$repo_dir/.git" ]]; then
                log_info "  Updating $name..."
                git -C "$repo_dir" pull --rebase --quiet 2>/dev/null || true
            else
                log_info "  Cloning $name..."
                git clone --quiet "https://github.com/$repo.git" "$repo_dir" 2>/dev/null || {
                    log_warning "$name: clone failed"; continue
                }
            fi

            # Build
            log_info "  Building $name..."
            (cd "$repo_dir" && go build -o "$binary" ./cmd/"$binary") 2>/dev/null || {
                log_warning "$name: build failed"; continue
            }

            # Configure MCP server with token from environment
            token_value="${!token_var:-}"
            claude mcp remove "$name" &>/dev/null || true
            if [[ -n "$token_value" ]]; then
                claude mcp add-json --scope user "$name" \
                    "{\"command\":\"$binary_path\",\"args\":[\"--transport\",\"stdio\"],\"env\":{\"$token_var\":\"$token_value\"}}" 2>&1 && \
                    log_success "$name configured" || log_warning "$name MCP registration failed"
            else
                log_warning "$name: $token_var not set — skipping MCP registration (build complete)"
            fi
        done
    elif [[ ${#MCP_SERVERS_LOCAL[@]} -gt 0 ]]; then
        log_warning "Go not installed — skipping local MCP servers"
    fi

    # markitdown (universal document-to-markdown converter, used by any2md)
    if ! is_installed markitdown; then
        log_info "Installing markitdown..."
        if cmd_exists uv; then
            uv tool install 'markitdown[pdf,docx,pptx,xlsx,youtube-transcription]' 2>/dev/null
        elif cmd_exists pipx; then
            pipx install 'markitdown[pdf,docx,pptx,xlsx,youtube-transcription]' 2>/dev/null
        else
            pip install 'markitdown[pdf,docx,pptx,xlsx,youtube-transcription]' 2>/dev/null
        fi || log_warning "markitdown installation failed"
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

    # zerobrew: fast Rust-based Homebrew client (installs to /opt/zerobrew, won't touch /opt/homebrew)
    if ! is_installed zb; then
        log_info "Installing zerobrew (experimental Homebrew alternative)..."
        curl --proto '=https' --tlsv1.2 -fsSL https://zerobrew.rs/install | bash 2>/dev/null || log_warning "zerobrew installation failed"
    fi

    log_success "Experimental features installation complete"
fi

# ─── Create User (Linux) ──────────────────────────────────────────────────────

if [[ "$INSTALL_CREATE_USER" == "true" ]] && is_linux; then
    create_dev_user
fi

# ─── macOS Settings ───────────────────────────────────────────────────────────

if [[ "$INSTALL_MACOS_SETTINGS" == "true" ]] && is_macos && [[ -f "$DOT_DIR/config/macos_settings.sh" ]]; then
    log_info "Configuring macOS system defaults..."
    "$DOT_DIR/config/macos_settings.sh" || log_warning "macOS settings had some errors"
fi

# ─── Finicky (macOS) ──────────────────────────────────────────────────────────

if [[ "$INSTALL_FINICKY" == "true" ]] && is_macos && ! is_cask_installed finicky; then
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
