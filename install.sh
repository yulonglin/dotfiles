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
    --ai-tools        Enable AI CLI tools (Claude, Codex, OpenCode, Antigravity)
    --extras          Enable extra CLI tools (hyperfine, gitui, code2prompt, ty)
    --cleanup         Enable automatic cleanup (macOS only)
    --docker          Enable Docker installation (Linux only)
    --pueue           Enable Pueue job scheduler (Linux only)
    --experimental    Enable experimental features (zotero MCP)
    --apps            Install GUI + App Store apps via Brewfile picker (macOS)
    --create-user     Create non-root dev user (Linux only)
    --no-<component>  Disable a component (e.g., --no-ai-tools)
    --force-reinstall Reinstall tools even if present
    --non-interactive Skip the component menu AND all later prompts (use defaults)
    --unattended, -y  Show the component menu, then run everything else with safe
                      defaults: no per-package prompts, gh auth deferred, git
                      conflicts keep existing values, sudo cached once up front

EXAMPLES:
    ./install.sh                        # Use defaults from config.sh
    ./install.sh --default              # Safe base for shared machines
    ./install.sh --only zsh tmux        # Only zsh and tmux, nothing else
    ./install.sh --extras --no-cleanup  # Add extras, skip cleanup
    ./install.sh --unattended           # Menu is the only prompt; rest runs hands-off
EOF
}

# Parse CLI arguments (overrides config.sh)
parse_args "$@"

# Make custom_bins (claude-tools) discoverable, then fetch a prebuilt
# claude-tools matching this platform so the component menu works on a fresh
# machine before the from-source build in deploy.sh has run.
export PATH="$DOT_DIR/custom_bins:$PATH"
bootstrap_claude_tools || true

show_component_menu install

# On Linux, package installs go through `sudo apt`. Cache sudo once now so the
# rest of the run is unattended (macOS uses Homebrew, which must NOT run as root).
if is_linux; then
    front_load_sudo
fi

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
        # NONINTERACTIVE=1 skips the installer's "Press RETURN to continue" prompt.
        # Without it the installer blocks waiting for Enter — a silent-looking stall
        # on a fresh Mac, since this script keeps stdin on the TTY (for the component
        # menu) so Homebrew never auto-detects non-interactive mode. Pre-warm sudo so
        # the installer's privileged steps don't stall on a mid-run password prompt.
        front_load_sudo
        NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
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
    install_packages apt "${PACKAGES_CORE[@]}" less nano nvtop lsof unzip bubblewrap socat

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

# ─── Security & Secrets Tools ────────────────────────────────────────────────

# Pre-set PATH so subshells and subsequent commands can find installed binaries
mkdir -p "$HOME/.local/bin"
mkdir -p "$HOME/.ssh/controlmasters"  # required by ControlPath in ~/.ssh/config
export PATH="$HOME/.local/bin:$PATH"

if is_linux; then
    run_parallel "Installing security tools" \
        "gitleaks|install_gitleaks" \
        "direnv|install_direnv"
else
    # macOS: brew has a global lock, must run sequentially
    install_gitleaks
    install_direnv
fi

# ─── uv (Python Package Manager) ──────────────────────────────────────────────

if ! is_installed uv; then
    log_info "Installing uv..."
    # Prefer the official Homebrew formula on macOS: sha-pinned + reviewed, unlike
    # the upstream curl|bash installer (authentic over HTTPS but not tamper-evident).
    if is_macos && cmd_exists brew; then
        brew_install uv
    else
        curl -LsSf https://astral.sh/uv/install.sh | sh
    fi
fi

# ─── Node.js 24 LTS (global runtime — see install_node in helpers.sh) ─────────

install_node

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
    install_tpm
fi

# ─── Extras ───────────────────────────────────────────────────────────────────

if [[ "$INSTALL_EXTRAS" == "true" ]]; then
    log_section "INSTALLING EXTRAS"

    # Rust toolchain (needed for code2prompt)
    install_rust_toolchain

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

    # ty — fast Python type checker (Astral/uv ecosystem)
    if ! is_installed ty && cmd_exists uv; then
        log_info "Installing ty..."
        uv tool install ty 2>/dev/null || log_warning "ty installation failed"
    fi
fi

# ─── AI Tools ─────────────────────────────────────────────────────────────────

if [[ "$INSTALL_AI_TOOLS" == "true" ]]; then
    log_section "INSTALLING AI CLI TOOLS"

    # Rust toolchain (needed for claude-tools build in deploy.sh)
    if ! is_installed cargo; then
        log_info "Installing Rust toolchain (user-level, no root needed)..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --quiet
    fi
    source "$HOME/.cargo/env" 2>/dev/null || true

    # Pre-set PATH for subshells
    [[ -d "$HOME/.claude/bin" ]] && export PATH="$HOME/.claude/bin:$PATH"

    # Bun must install before Codex/OpenCode on Linux (they need `bun add -g`)
    if is_linux && ! cmd_exists bun; then
        log_info "Installing bun..."
        curl -fsSL https://bun.sh/install | bash
        export BUN_INSTALL="$HOME/.bun"
        export PATH="$BUN_INSTALL/bin:$PATH"
    fi

    if is_macos; then
        # brew has a global lock — sequential
        install_claude_code
        install_codex_cli
        install_opencode
        install_antigravity_cli   # official Gemini CLI successor (cask, macOS)
    else
        run_parallel "Installing AI CLI tools" \
            "claude|install_claude_code" \
            "codex|install_codex_cli" \
            "opencode|install_opencode" \
            "antigravity|install_antigravity_cli"
    fi

    # MCP servers (sequential — unclear if concurrent-safe)
    if cmd_exists claude; then
        log_info "Configuring MCP servers..."
        for server in "${MCP_SERVERS[@]}"; do
            IFS=':' read -r name url <<< "$server"
            claude mcp remove "$name" &>/dev/null || true
            if [[ "$url" == npx* ]]; then
                args="${url#npx }"
                claude mcp add-json --scope user "$name" "{\"command\":\"npx\",\"args\":[\"${args}\"]}" 2>&1 && \
                    log_success "$name configured" || log_warning "$name failed"
            else
                claude mcp add --scope user --transport http "$name" "$url" 2>&1 && \
                    log_success "$name configured" || log_warning "$name failed"
            fi
        done
    fi

    # Local MCP servers (sequential — clone + build + register)
    if cmd_exists go && cmd_exists claude && [[ ${#MCP_SERVERS_LOCAL[@]} -gt 0 ]]; then
        log_info "Building local MCP servers..."
        mcp_base="$HOME/code/marketplaces"
        mkdir -p "$mcp_base"

        for entry in "${MCP_SERVERS_LOCAL[@]}"; do
            IFS=':' read -r name repo binary token_var <<< "$entry"
            repo_dir="$mcp_base/$(basename "$repo")"
            binary_path="$repo_dir/$binary"

            if [[ -d "$repo_dir/.git" ]]; then
                log_info "  Updating $name..."
                git -C "$repo_dir" pull --rebase --quiet 2>/dev/null || true
            else
                log_info "  Cloning $name..."
                git clone --quiet "https://github.com/$repo.git" "$repo_dir" 2>/dev/null || {
                    log_warning "$name: clone failed"; continue
                }
            fi

            log_info "  Building $name..."
            (cd "$repo_dir" && go build -o "$binary" ./cmd/"$binary") 2>/dev/null || {
                log_warning "$name: build failed"; continue
            }

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

    # Supply chain defense tools
    # Socket CLI — wraps npm/npx with supply chain scanning
    if ! cmd_exists socket; then
        log_info "Installing Socket CLI..."
        npm install -g @socketsecurity/cli 2>/dev/null || log_warning "Socket CLI install failed (npm required)"
    fi

    # pip-audit — vulnerability scanner for Python dependencies
    if ! cmd_exists pip-audit; then
        log_info "Installing pip-audit..."
        uv tool install pip-audit 2>/dev/null || log_warning "pip-audit install failed"
    fi

    # markitdown
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
    install_docker || log_warning "Docker installation failed — continuing"
fi

# ─── Pueue (Linux) ───────────────────────────────────────────────────────────

if [[ "$INSTALL_PUEUE" == "true" ]] && is_linux; then
    log_section "INSTALLING PUEUE"
    if ! cmd_exists pueue; then
        if cmd_exists cargo; then
            log_info "Installing pueue + pueued via cargo..."
            cargo install pueue pueued --quiet 2>/dev/null || log_warning "pueue install failed"
        else
            log_warning "cargo not found — install Rust first, then: cargo install pueue pueued"
        fi
    else
        log_info "pueue already installed ($(pueue --version 2>/dev/null || echo 'unknown'))"
    fi
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

    # zotero-mcp-server: Zotero MCP for citation management (see config/experimental.yaml)
    if ! is_installed zotero-mcp && cmd_exists uv; then
        log_info "Installing zotero-mcp-server (citation library management)..."
        uv tool install 'zotero-mcp-server[all]' 2>/dev/null || log_warning "zotero-mcp-server installation failed"
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

# ─── GUI + App Store Apps (macOS, via Brewfile) ───────────────────────────────
# Pick apps in a TUI (app-picker reads config/apps.conf → generates config/Brewfile),
# then install via `brew bundle`. Official casks + Mac App Store only; never
# --no-quarantine (Gatekeeper/notarization must stay on). Finicky now lives here too.

if [[ "$INSTALL_APPS" == "true" ]] && is_macos; then
    log_section "INSTALLING APPS (Brewfile) 📦"

    if ! cmd_exists brew; then
        log_warning "Homebrew required for apps — skipping"
    else
        # gum drives app-picker; bootstrap it (tiny formula) if missing.
        # Note: the component selection menu uses claude-tools select, not gum.
        cmd_exists gum || brew_install gum

        brewfile="$DOT_DIR/config/Brewfile"
        if [[ "${NON_INTERACTIVE:-false}" == "true" ]] || ! [[ -t 0 ]]; then
            log_info "Non-interactive: using committed Brewfile (run 'app-picker' to customise)"
        else
            # Interactive: let the user toggle apps, regenerating the Brewfile.
            "$DOT_DIR/custom_bins/app-picker" || log_warning "app-picker cancelled — using existing Brewfile"
        fi

        if [[ -f "$brewfile" ]]; then
            # Step 1: Install App Store apps via `mas get` (acquire+install).
            # `brew bundle` uses `mas install` which only re-downloads — it fails with
            # "Redownload Unavailable" for apps not yet on this machine even when owned.
            # `mas get` acquires+installs, making brew bundle's mas lines no-ops after.
            # Ref: https://github.com/Homebrew/brew/issues/21559
            if is_macos && command -v mas &>/dev/null; then
                log_info "Installing App Store apps via mas get..."
                "$DOT_DIR/custom_bins/mas-get" || log_warning "Some App Store apps failed (check mas-get output above)"
            fi

            # Step 2: mas 7.0.0 self-escalates via sudo; brew bundle </dev/null gives its
            # internal sudo no way to read a password. Pre-warm the credential (interactive
            # TTY only) for any mas lines that remain (belt-and-suspenders after mas-get).
            sudo_keepalive_pid=""
            if [[ -t 0 ]] && grep -q '^mas ' "$brewfile" 2>/dev/null; then
                log_info "App Store installs (mas) need sudo — caching your credential…"
                if sudo -v; then
                    # Capture parent PID before subshell so $$ resolves correctly in both
                    # zsh (where $$ is the parent in subshells) and bash (where it is not).
                    _mas_parent_pid=$$
                    ( while true; do sudo -n true; sleep 60; kill -0 "$_mas_parent_pid" 2>/dev/null || exit; done ) 2>/dev/null &
                    sudo_keepalive_pid=$!
                else
                    log_warning "sudo not authorized — App Store (mas) apps may be skipped"
                fi
            fi

            log_info "Installing remaining apps from Brewfile (this can take a while)..."
            env "${BREW_NONINTERACTIVE_ENV[@]}" brew bundle --file="$brewfile" </dev/null || true

            [[ -n "$sudo_keepalive_pid" ]] && kill "$sudo_keepalive_pid" 2>/dev/null

            # Step 3: Detect any mas apps that didn't land and tell the user what to do.
            if grep -q '^mas ' "$brewfile" 2>/dev/null; then
                installed_ids=$(mas list 2>/dev/null | awk '{print $1}')
                if [[ -z "$installed_ids" ]]; then
                    log_warning "Could not query installed App Store apps (mas list failed) — skipping post-install check"
                else
                    missing_apps=()
                    while IFS= read -r line; do
                        # Use -n .../p so sed prints nothing (not the raw line) on a non-match.
                        app_name=$(echo "$line" | sed -n 's/^mas "\(.*\)", id:.*/\1/p')
                        app_id=$(echo "$line"   | sed -n 's/.*id: \([0-9][0-9]*\).*/\1/p')
                        [[ -z "$app_id" ]] && continue  # skip malformed lines
                        # -x: full-line match so "123" doesn't accidentally match "1234"
                        if ! echo "$installed_ids" | grep -qx "$app_id"; then
                            missing_apps+=("$app_name (ID: $app_id)")
                        fi
                    done < <(grep '^mas ' "$brewfile")

                    if [[ ${#missing_apps[@]} -gt 0 ]]; then
                        echo ""
                        log_warning "The following App Store apps were NOT installed:"
                        for app in "${missing_apps[@]}"; do
                            echo "    ✗ $app"
                        done
                        echo ""
                        echo "  To install them manually:"
                        echo "    1. Open the App Store app"
                        echo "    2. Click your name (bottom-left) → Purchased"
                        echo "    3. Find each app above and click the ⊕ download button"
                        echo ""
                        echo "  Common causes:"
                        echo "    • App Store account mismatch (check: App Store → your name)"
                        echo "    • App purchased under a different Apple ID"
                        echo "    • sudo not authorized (mas 7.0.0 requires root)"
                        echo ""
                    fi
                fi  # mas list succeeded
            fi  # Brewfile has mas entries

            log_info "Next: run scripts/setup/auth-setup for logins + signature audit"
        else
            log_warning "No Brewfile at $brewfile — run 'app-picker' first"
        fi
    fi
fi

# ─── Done ─────────────────────────────────────────────────────────────────────

echo ""
log_success "Installation complete!"
echo ""
echo "Next steps:"
echo "  1. Run ./deploy.sh to deploy configurations"
echo "  2. Restart your terminal or run: source ~/.zshrc"
