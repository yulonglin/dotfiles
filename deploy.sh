#!/usr/bin/env zsh
# ═══════════════════════════════════════════════════════════════════════════════
# Dotfiles Deployment Script
# ═══════════════════════════════════════════════════════════════════════════════
# Deploys configurations to the system. Configuration is in config.sh.
#
# Usage:
#   ./deploy.sh                       # Deploy with defaults from config.sh
#   ./deploy.sh --profile=server      # Use server profile
#   ./deploy.sh --no-editor           # Skip editor settings
#   ./deploy.sh --aliases=inspect     # Add extra aliases
#
# See config.sh for all available settings.
# ═══════════════════════════════════════════════════════════════════════════════
set -euo pipefail

# Script directory
DOT_DIR="$(cd "$(dirname "$(realpath "$0")")" && pwd)"
export DOT_DIR

# Validate DOT_DIR
if [[ -z "$DOT_DIR" || ! -d "$DOT_DIR/config" ]]; then
    echo "Error: DOT_DIR is empty or invalid: '$DOT_DIR'" >&2
    exit 1
fi

# Load configuration and helpers
source "$DOT_DIR/config.sh"
source "$DOT_DIR/scripts/shared/helpers.sh"

# ─── Help ─────────────────────────────────────────────────────────────────────

show_help() {
    cat <<EOF
Usage: ./deploy.sh [OPTIONS]

Deploy dotfile configurations. Settings are in config.sh.

PROFILES:
    --profile=NAME    Use a profile: personal, server, minimal
    --default         Safe base for shared/new machines (alias for --profile=server)
    --minimal         Suppress ALL components — specify what you want explicitly
    --no-defaults     Same as --minimal (clearer name)
    --server          Server-appropriate subset
    --personal        Full personal setup (default)

SELECTIVE DEPLOYMENT:
    --only COMP...    Deploy ONLY these components, nothing else
                      Examples:
                        --only vim claude         # space-separated
                        --only vim,claude         # comma-separated
                        --only vim --only claude  # repeatable
                      Cannot be mixed with profiles or --component flags.

COMPONENTS:
    --shell           Deploy ZSH/bash shell configuration
    --tmux            Deploy tmux configuration
    --git-config      Deploy gitconfig and global ignore files
    --vim             Deploy vimrc
    --editor          Deploy VSCode/Cursor settings
    --claude          Deploy Claude Code config (~/.claude symlink)
    --codex           Deploy Codex CLI config (~/.codex symlink)
    --serena          Deploy Serena MCP config (~/.serena symlink)
    --mouseless       Deploy Mouseless keyboard mouse control config (macOS only)
    --ghostty         Deploy Ghostty terminal config
    --htop            Deploy htop configuration
    --pdb             Deploy pdb++ debugger config
    --matplotlib      Deploy matplotlib styles
    --git-hooks       Deploy global git hooks
    --secrets         Sync secrets with GitHub gist
    --secrets-env     Decrypt SOPS-encrypted API keys (requires sops + age)
    --cleanup         Install file cleanup: Downloads/Screenshots (macOS only)
    --claude-cleanup  Install Claude Code session cleanup (both platforms)
    --ai-update       Install AI tools auto-update (daily, both platforms)
    --brew-update     Install weekly package upgrade + cleanup (brew/apt/dnf/pacman)
    --keyboard        Install keyboard repeat enforcement at login (macOS only)
    --file-apps       Set default editor for coding file types (macOS only)
    --bedtime         Install bedtime timezone enforcement (macOS only, opt-in)
    --vpn             Install NordVPN+Tailscale split tunnel daemon (macOS only)
    --text-replacements  Sync text replacements: macOS + Alfred (macOS only)
    --aliases=LIST    Additional alias scripts (comma-separated)
    --append          Append to existing configs instead of overwrite
    --ascii=FILE      ASCII art file for shell startup
    --no-<component>  Disable a component (e.g., --no-editor)
    --non-interactive Skip interactive component menu

EXAMPLES:
    ./deploy.sh                           # Use defaults from config.sh
    ./deploy.sh --default                 # Safe base for shared machines
    ./deploy.sh --default --serena        # Default + add-on
    ./deploy.sh --only vim claude         # Only vim and claude, nothing else
    ./deploy.sh --no-defaults --vim       # Empty base + vim
    ./deploy.sh --aliases=inspect         # Add extra aliases
EOF
}

# Parse CLI arguments (overrides config.sh)
parse_args "$@"
show_component_menu deploy

# ─── Main Deployment ──────────────────────────────────────────────────────────

log_section "DEPLOYING DOTFILES"
echo "Platform: $PLATFORM"
echo "Profile: $PROFILE"
echo "Append mode: $DEPLOY_APPEND"
echo ""

# Set operator based on append flag
OP=">"
[[ "$DEPLOY_APPEND" == "true" ]] && OP=">>"

# Default RC_FILE (overwritten by shell block if DEPLOY_SHELL=true)
RC_FILE="$HOME/.zshrc"

# ─── tmux ─────────────────────────────────────────────────────────────────────

if [[ "$DEPLOY_TMUX" == "true" ]]; then
    log_info "Deploying tmux configuration..."
    eval "echo \"source $DOT_DIR/config/tmux.conf\" $OP \"\$HOME/.tmux.conf\""

    # Ensure TPM is installed (idempotent — skips if already present)
    install_tpm

    # Install plugins directly (avoids needing a tmux server running)
    local plugin_dir="$HOME/.tmux/plugins"
    for plugin in tmux-resurrect tmux-continuum; do
        if [[ ! -d "$plugin_dir/$plugin" ]]; then
            log_info "Installing $plugin..."
            git clone --quiet "https://github.com/tmux-plugins/$plugin" "$plugin_dir/$plugin" 2>/dev/null || \
                log_warning "$plugin clone failed"
        fi
    done
fi

# ─── Vim ──────────────────────────────────────────────────────────────────────

if [[ "$DEPLOY_VIM" == "true" ]]; then
    log_info "Deploying vimrc..."
    safe_symlink "$DOT_DIR/config/vimrc" "$HOME/.vimrc"
fi

# ─── Shell Configuration ──────────────────────────────────────────────────────

if [[ "$DEPLOY_SHELL" != "true" ]] && [[ ${#DEPLOY_ALIASES[@]} -gt 0 ]]; then
    log_warning "DEPLOY_ALIASES set but DEPLOY_SHELL=false — aliases will not be appended"
fi

if [[ "$DEPLOY_SHELL" == "true" ]]; then
    # Install zsh if not present
    if ! cmd_exists zsh; then
        log_info "ZSH not found, installing..."
        if is_macos; then
            brew_install zsh
        else
            apt_install zsh
        fi
    fi

    # Determine shell
    if cmd_exists zsh; then
        CURRENT_SHELL="zsh"
    else
        CURRENT_SHELL="${SHELL##*/}"
    fi

    log_info "Deploying shell configuration for $CURRENT_SHELL..."

    if [[ "$CURRENT_SHELL" == "zsh" ]]; then
        eval "echo \"source $DOT_DIR/config/zshrc.sh\" $OP \"\$HOME/.zshrc\""
        RC_FILE="$HOME/.zshrc"
    elif [[ "$CURRENT_SHELL" == "bash" ]]; then
        # Minimal bashrc that sources essential files
        if [[ "$DEPLOY_APPEND" == "false" ]]; then
            > "$HOME/.bashrc"
        fi

        cat >> "$HOME/.bashrc" <<BASHRC
# Dotfiles configuration
export DOT_DIR=$DOT_DIR
source $DOT_DIR/config/aliases.sh
source $DOT_DIR/config/key_bindings.sh
source $DOT_DIR/config/modern_tools.sh
export PATH="\$DOT_DIR/custom_bins:\$PATH"

# Tool integrations
[ -f ~/.fzf.bash ] && source ~/.fzf.bash
[ -d "\$HOME/.cargo" ] && . "\$HOME/.cargo/env"
[ -d "\$HOME/.local/bin" ] && [ -f "\$HOME/.local/bin/env" ] && source "\$HOME/.local/bin/env"

# ASCII art in interactive shells
[[ \$- == *i* ]] && [ -f $DOT_DIR/config/start.txt ] && cat $DOT_DIR/config/start.txt
BASHRC

        # Update .bash_profile
        if ! grep -q "source.*\.bashrc" ~/.bash_profile 2>/dev/null; then
            cat >> "$HOME/.bash_profile" <<'PROFILE'

# Source .bashrc for login shells
if [ -f "$HOME/.bashrc" ]; then
    . "$HOME/.bashrc"
fi
PROFILE
        fi

        if ! grep -q "bash_zsh_switcher.sh" ~/.bash_profile 2>/dev/null; then
            echo "[ -f $DOT_DIR/config/bash_zsh_switcher.sh ] && source $DOT_DIR/config/bash_zsh_switcher.sh" >> "$HOME/.bash_profile"
        fi

        RC_FILE="$HOME/.bashrc"
    else
        log_warning "Unknown shell '$CURRENT_SHELL', defaulting to zsh"
        eval "echo \"source $DOT_DIR/config/zshrc.sh\" $OP \"\$HOME/.zshrc\""
        RC_FILE="$HOME/.zshrc"
    fi

    # Append additional aliases
    if [[ ${#DEPLOY_ALIASES[@]} -gt 0 ]]; then
        log_info "Adding aliases: ${DEPLOY_ALIASES[*]}"
        for alias_name in "${DEPLOY_ALIASES[@]}"; do
            echo "source $DOT_DIR/config/aliases_${alias_name}.sh" >> "$RC_FILE"
        done
    fi

    # Custom ASCII art
    if [[ "$DEPLOY_ASCII_FILE" != "start.txt" ]]; then
        log_info "Using custom ASCII art: $DEPLOY_ASCII_FILE"
        cp "$DOT_DIR/config/ascii_arts/$DEPLOY_ASCII_FILE" "$DOT_DIR/config/start.txt"
    fi
fi

# ─── Gist Sync (SSH config, authorized_keys, git identity) ───────────────────

if [[ "$DEPLOY_SECRETS" == "true" ]]; then
    log_section "SYNCING GIST"
    sync_gist || log_warning "Gist sync failed (continuing anyway)"

    # Install automated daily sync
    log_info "Setting up automated daily gist sync..."
    "$DOT_DIR/scripts/cleanup/setup_gist_sync.sh" || log_warning "Failed to setup automated gist sync"
fi

# ─── Encrypted Secrets (SOPS + age) ──────────────────────────────────────────

if [[ "${DEPLOY_SECRETS_ENV:-false}" == "true" ]]; then
    log_section "ENCRYPTED SECRETS (SOPS + age)"
    enc="$DOT_DIR/config/secrets.env.enc"
    out="$DOT_DIR/.secrets"
    age_key="$HOME/.config/sops/age/keys.txt"
    sops_yaml="$DOT_DIR/.sops.yaml"

    log_info "enc=$enc"
    log_info "age_key=$age_key"
    log_info "sops_yaml=$sops_yaml"

    if ! cmd_exists sops || ! cmd_exists age-keygen; then
        log_warning "sops/age not installed — run install.sh"
    elif [[ ! -f "$age_key" ]]; then
        log_info "Age key not found at $age_key"
        if [[ -s "$enc" ]]; then
            # Second machine: encrypted secrets exist, need age key to decrypt
            echo ""
            log_info "Encrypted secrets exist but can't be decrypted without age key"
            echo "Paste your age private key (from Bitwarden), then press Enter:"
            echo "(starts with AGE-SECRET-KEY-, leave empty to skip)"
            local age_input=""
            if [[ -e /dev/tty ]]; then
                read -rs age_input </dev/tty
            fi
            if [[ -n "$age_input" ]]; then
                mkdir -p "$(dirname "$age_key")"
                printf '%s\n' "$age_input" > "$age_key"
                chmod 600 "$age_key"
                log_success "Age key saved to $age_key"
            else
                log_warning "Skipping — re-run deploy.sh when you have the key"
            fi
        else
            # First machine: no key, no encrypted secrets — generate everything
            log_info "Setting up SOPS encryption (first time)..."
            mkdir -p "$(dirname "$age_key")"
            age-keygen -o "$age_key" 2>&1
            chmod 600 "$age_key"
            log_success "Generated age keypair at $age_key"
            log_info "IMPORTANT: Store the private key in Bitwarden now!"
            echo "  cat $age_key"
            echo ""
        fi
    else
        log_info "Age key found at $age_key"
    fi

    # Extract public key once for subsequent steps
    local pub_key=""
    if [[ -f "$age_key" ]]; then
        pub_key=$(grep -o 'age1[a-z0-9]*' "$age_key" | head -1)
        if [[ -n "$pub_key" ]]; then
            log_info "Public key: ${pub_key:0:20}..."
        else
            log_warning "Could not extract public key from $age_key"
        fi
    fi

    # Ensure .sops.yaml has real public key (not placeholder)
    if [[ -n "$pub_key" ]]; then
        if [[ ! -f "$sops_yaml" ]] || grep -q 'age1\.\.\.' "$sops_yaml"; then
            cat > "$sops_yaml" <<SOPSYAML
creation_rules:
  - path_regex: \\.enc\$
    age: "$pub_key"
SOPSYAML
            log_success "Wrote $sops_yaml with age public key"
        else
            # Warn if local key doesn't match the key in .sops.yaml
            local config_key
            config_key=$(grep -o 'age1[a-z0-9]*' "$sops_yaml" | head -1)
            if [[ -n "$config_key" && "$config_key" != "$pub_key" ]]; then
                log_warning "Key mismatch! Local age key does not match .sops.yaml"
                log_warning "  Local key:      ${pub_key:0:30}..."
                log_warning "  .sops.yaml key: ${config_key:0:30}..."
                log_warning "  You won't be able to decrypt existing secrets with this key"
                log_warning "  To fix: paste the original age key from Bitwarden into $age_key"
            else
                log_info ".sops.yaml already configured at $sops_yaml"
            fi
        fi
    fi

    # Create template encrypted file if missing
    if [[ ! -s "$enc" ]] && [[ -n "$pub_key" ]] && cmd_exists sops; then
        log_info "Creating template encrypted secrets..."
        local tmpfile="${TMPDIR:-/tmp}/secrets_template.env"
        printf '%s\n' \
            "# Encrypted API keys (edit with: secrets-edit)" \
            "PLACEHOLDER=replace_me" \
            "# ANTHROPIC_API_KEY=" \
            "# OPENAI_API_KEY=" \
            "# HF_TOKEN=" \
            "# GITHUB_TOKEN=" \
            > "$tmpfile"
        # Use --config /dev/null to skip creation rule matching — the repo
        # .sops.yaml path_regex matches .enc files, but the tmpfile is .env.
        # With /dev/null config, sops uses --age from CLI directly.
        log_info "Running: sops -e --config /dev/null --age <key> $tmpfile"
        local sops_err
        if sops_err=$( (sops -e --config /dev/null --age "$pub_key" "$tmpfile" > "${enc}.tmp") 2>&1); then
            mv "${enc}.tmp" "$enc"
            log_success "Created $enc — edit with: secrets-edit"
        else
            rm -f "${enc}.tmp"
            log_warning "Failed to create encrypted secrets"
            log_error "sops error: $sops_err"
        fi
        rm -f "$tmpfile"
    elif [[ -s "$enc" ]]; then
        log_info "Encrypted secrets already exist at $enc"
    fi

    # Decrypt if key and encrypted file both exist
    if [[ -s "$enc" ]] && cmd_exists sops && [[ -f "$age_key" ]]; then
        log_info "Decrypting $enc → $out"
        export SOPS_AGE_KEY_FILE="$age_key"
        sops_dotenv() { sops --input-type dotenv --output-type dotenv "$@"; }
        local sops_err
        if sops_err=$( (umask 077 && sops_dotenv -d --config "$sops_yaml" "$enc" > "${out}.tmp") 2>&1); then
            mv "${out}.tmp" "$out"
            log_success "Decrypted secrets to $out"
            # Symlink .env → .secrets so tools expecting .env read SOPS-managed secrets
            ln -sf .secrets "$DOT_DIR/.env"
            log_success "Symlinked .env → .secrets"
        else
            rm -f "${out}.tmp"
            log_warning "Failed to decrypt secrets"
            log_error "sops error: $sops_err"
        fi
    fi
fi

# ─── Git Configuration ────────────────────────────────────────────────────────

if [[ "$DEPLOY_GIT_CONFIG" == "true" ]]; then
    log_section "DEPLOYING GIT CONFIGURATION"
    deploy_git_config

    # Global gitattributes
    safe_symlink "$DOT_DIR/config/gitattributes_global" "$HOME/.gitattributes"
    git config --global core.attributesFile "$HOME/.gitattributes"
fi

# ─── Git Hooks ────────────────────────────────────────────────────────────────

if [[ "$DEPLOY_GIT_HOOKS" == "true" ]]; then
    log_info "Deploying global git hooks..."

    if [[ -d "$DOT_DIR/config/git-hooks" ]]; then
        mkdir -p "$HOME/.git-hooks"

        for hook in "$DOT_DIR/config/git-hooks"/*; do
            if [[ -f "$hook" ]]; then
                cp "$hook" "$HOME/.git-hooks/"
                chmod +x "$HOME/.git-hooks/$(basename "$hook")"
            fi
        done

        git config --global core.hooksPath "$HOME/.git-hooks"
        log_success "Deployed global git hooks to ~/.git-hooks"
        log_info "  Features: Secret detection, layered with repo hooks"

        if ! cmd_exists gitleaks; then
            log_warning "gitleaks not installed - using regex fallback"
        fi
    else
        log_warning "Git hooks directory not found"
    fi

    # Set up dotfiles-specific pre-commit hook (auto-updates SKILL.md deny list)
    if [[ -d "$DOT_DIR/.git" ]] && [[ -f "$DOT_DIR/scripts/hooks/dotfiles-pre-commit.sh" ]]; then
        chmod +x "$DOT_DIR/scripts/hooks/dotfiles-pre-commit.sh"
        ln -sf "../../scripts/hooks/dotfiles-pre-commit.sh" "$DOT_DIR/.git/hooks/pre-commit.local"
        log_success "Deployed dotfiles pre-commit hook (.git/hooks/pre-commit.local)"
    fi
fi

# ─── Editor Settings ──────────────────────────────────────────────────────────

if [[ "$DEPLOY_EDITOR" == "true" ]]; then
    log_section "DEPLOYING EDITOR SETTINGS"
    deploy_editor_settings || log_warning "Editor settings deployment failed"
fi

# ─── Developer Config Files ──────────────────────────────────────────────────

if [[ "$DEPLOY_EDITOR" == "true" ]]; then
    log_info "Deploying developer config files..."

    # EditorConfig — universal editor formatting
    safe_symlink "$DOT_DIR/config/editorconfig" "$HOME/.editorconfig"

    # curl defaults
    safe_symlink "$DOT_DIR/config/curlrc" "$HOME/.curlrc"

    # Readline config (bash, python3 REPL, node REPL, psql — not ZSH)
    safe_symlink "$DOT_DIR/config/inputrc" "$HOME/.inputrc"

    # .hushlogin — suppress "Last login" message
    touch "$HOME/.hushlogin"
fi

# ─── Finicky (macOS) ──────────────────────────────────────────────────────────

if [[ "$DEPLOY_FINICKY" == "true" ]] && is_macos && [[ -f "$DOT_DIR/config/finicky.js" ]]; then
    log_info "Deploying Finicky configuration..."
    safe_symlink "$DOT_DIR/config/finicky.js" "$HOME/.finicky.js"
    log_info "  Safari default, Chrome for Google apps, Zoom for meetings"

    if [[ ! -d "/Applications/Finicky.app" ]]; then
        log_warning "Finicky not installed. Run './install.sh' to install."
    fi
fi

# ─── Ghostty ──────────────────────────────────────────────────────────────────

if [[ "$DEPLOY_GHOSTTY" == "true" ]]; then
    log_info "Deploying Ghostty configuration..."

    if is_macos; then
        GHOSTTY_DIR="$HOME/Library/Application Support/com.mitchellh.ghostty"
    else
        GHOSTTY_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/ghostty"
    fi

    if [[ -f "$DOT_DIR/config/ghostty.conf" ]]; then
        mkdir -p "$GHOSTTY_DIR"
        safe_symlink "$DOT_DIR/config/ghostty.conf" "$GHOSTTY_DIR/config"
        log_info "  Key bindings: Shift+Enter (newline), Cmd+C (copy)"
    else
        log_warning "Ghostty config not found"
    fi
fi

# ─── htop ─────────────────────────────────────────────────────────────────────

if [[ "$DEPLOY_HTOP" == "true" ]]; then
    log_info "Deploying htop configuration..."

    HTOP_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/htop"
    HTOP_LOCAL="$HTOP_DIR/htoprc"
    HTOP_DOTFILES="$DOT_DIR/config/htop/htoprc"

    if [[ ! -f "$HTOP_DOTFILES" ]]; then
        log_warning "htop config not found at $HTOP_DOTFILES"
    else
        mkdir -p "$HTOP_DIR"

        # Check if local config exists and is NOT a symlink (htop overwrote it)
        if [[ -f "$HTOP_LOCAL" && ! -L "$HTOP_LOCAL" ]]; then
            if ! diff -q "$HTOP_LOCAL" "$HTOP_DOTFILES" >/dev/null 2>&1; then
                log_warning "Local htop config differs from dotfiles (htop overwrites symlinks)"
                echo ""
                echo "Options:"
                echo "  [l] Keep local config (update dotfiles)"
                echo "  [d] Keep dotfiles config (discard local changes)"
                echo "  [s] Skip htop deployment"
                echo ""
                read -r "htop_choice?Choice [l/d/s]: "

                case "$htop_choice" in
                    l|L)
                        cp "$HTOP_LOCAL" "$HTOP_DOTFILES"
                        log_success "Updated dotfiles with local htop config"
                        ;;
                    d|D)
                        log_info "Using dotfiles config"
                        ;;
                    *)
                        log_info "Skipping htop deployment"
                        HTOP_DOTFILES=""  # Skip symlink creation
                        ;;
                esac
            fi
        fi

        if [[ -n "$HTOP_DOTFILES" ]]; then
            safe_symlink "$HTOP_DOTFILES" "$HTOP_LOCAL"
            log_info "  Uses dynamic CPU meters (adapts to any CPU count)"
        fi
    fi
fi

# ─── pdb++ ────────────────────────────────────────────────────────────────────

if [[ "$DEPLOY_PDB" == "true" ]]; then
    log_info "Deploying pdb++ configuration..."

    PDB_LOCAL="$HOME/.pdbrc.py"
    PDB_DOTFILES="$DOT_DIR/config/pdbrc.py"

    if [[ ! -f "$PDB_DOTFILES" ]]; then
        log_warning "pdb++ config not found at $PDB_DOTFILES"
    else
        safe_symlink "$PDB_DOTFILES" "$PDB_LOCAL"
        log_info "  High-contrast color scheme for better readability"
    fi
fi

# ─── Plotting Library ─────────────────────────────────────────────────────────

if [[ "$DEPLOY_MATPLOTLIB" == "true" ]]; then
    log_info "Deploying plotting library..."

    PLOTLIB="$HOME/.local/lib/plotting"
    if [[ -d "$DOT_DIR/lib/plotting" ]]; then
        mkdir -p "$PLOTLIB"
        for pyfile in "$DOT_DIR/lib/plotting"/*.py; do
            [[ -f "$pyfile" ]] && cp "$pyfile" "$PLOTLIB/$(basename "$pyfile")"
        done
        log_info "  Deployed plotting library to ~/.local/lib/plotting/"
    fi

    log_info "Deploying matplotlib styles..."

    STYLELIB="$HOME/.config/matplotlib/stylelib"

    if [[ -d "$DOT_DIR/config/matplotlib" ]]; then
        mkdir -p "$STYLELIB"

        # Deploy .mplstyle files (symlink for live updates)
        for style in "$DOT_DIR/config/matplotlib"/*.mplstyle; do
            if [[ -f "$style" ]]; then
                safe_symlink "$style" "$STYLELIB/$(basename "$style")"
            fi
        done

        log_success "Deployed plotting library and matplotlib styles"
        log_info "  Styles: plt.style.use('anthropic'), plt.style.use('petri'), plt.style.use('deepmind')"
        log_info "  Python library: PYTHONPATH includes ~/.local/lib/plotting/"
        log_info "  Usage: from anthro_colors import use_anthropic_defaults; use_anthropic_defaults()"
    else
        log_warning "Matplotlib config directory not found"
    fi
fi

# ─── claude-tools (Rust binary, backgrounded) ───────────────────────────────

CLAUDE_TOOLS_PID=""
CLAUDE_TOOLS_LOG=""
if [[ "$DEPLOY_CLAUDE_TOOLS" == "true" ]] && [[ -f "$DOT_DIR/tools/claude-tools/Cargo.toml" ]] && cmd_exists cargo; then
    log_info "Building claude-tools (background)..."
    CLAUDE_TOOLS_LOG=$(mktemp)
    (
        cd "$DOT_DIR/tools/claude-tools" && cargo build --release --quiet 2>&1 && \
        cp "$DOT_DIR/tools/claude-tools/target/release/claude-tools" "$DOT_DIR/custom_bins/claude-tools" && \
        chmod +x "$DOT_DIR/custom_bins/claude-tools"
    ) &>"$CLAUDE_TOOLS_LOG" &
    CLAUDE_TOOLS_PID=$!
fi

# ─── Claude Code ──────────────────────────────────────────────────────────────

if [[ "$DEPLOY_CLAUDE" == "true" ]]; then
    log_section "DEPLOYING CLAUDE CODE CONFIGURATION"

    if [[ -d "$DOT_DIR/claude" ]]; then
        # Runtime files to preserve
        runtime_files=(
            ".credentials.json" "history.jsonl" "cache" "projects"
            "plans" "todos" "session-env" "shell-snapshots" "statsig"
            ".cl" "debug" "mcp_servers.json" "plugins/installed_plugins.json"
            "plugins/known_marketplaces.json"
        )

        if [[ -L "$HOME/.claude" ]]; then
            # Already a symlink - refresh it
            rm "$HOME/.claude"
            log_info "Refreshed existing symlink"
        elif [[ -d "$HOME/.claude" ]]; then
            # Directory exists - smart merge
            log_info "Smart merge: preserving runtime files from existing ~/.claude"
            backup_path="$HOME/.claude.backup.$(date -u +%d-%m-%Y_%H-%M-%S)"
            mv "$HOME/.claude" "$backup_path"

            ln -sf "$DOT_DIR/claude" "$HOME/.claude"

            # Restore runtime files
            restored=0
            for file in "${runtime_files[@]}"; do
                if [[ -e "$backup_path/$file" ]]; then
                    cp -r "$backup_path/$file" "$HOME/.claude/" 2>/dev/null && ((restored++))
                fi
            done

            if [[ $restored -gt 0 ]]; then
                log_success "Restored $restored runtime file(s)"
                log_info "Backup at: $backup_path"
            fi
        fi

        # Create symlink if it doesn't exist
        if [[ ! -e "$HOME/.claude" ]]; then
            ln -sf "$DOT_DIR/claude" "$HOME/.claude"
        fi

        # Sync plugin marketplaces (declarative, from profiles.yaml)
        if command -v claude-tools &>/dev/null; then
            log_info "Syncing plugin marketplaces..."
            claude-tools context --sync -v || \
                log_warning "Marketplace sync had issues — run manually: claude-tools context --sync"
        else
            log_warning "claude-tools not found — skipping marketplace sync"
        fi

        # Clean plugin-created symlinks from skills/ (they cause duplicate entries)
        if [[ -f "$DOT_DIR/scripts/cleanup/clean_plugin_symlinks.sh" ]]; then
            "$DOT_DIR/scripts/cleanup/clean_plugin_symlinks.sh"
        fi

        # Clean stale plugin cache versions (prevents skill shadowing warnings)
        if command -v claude-cache-clean &>/dev/null; then
            claude-cache-clean --apply
        fi

        # Deploy context templates (skip if ~/.claude already points here)
        local ctx_src="$DOT_DIR/claude/templates/contexts"
        local ctx_dst="$HOME/.claude/templates/contexts"
        if [[ -d "$ctx_src" ]]; then
            mkdir -p "$ctx_dst"
            local tmpl_count=0
            for tmpl in "$ctx_src"/*.json(N) "$ctx_src"/*.yaml(N); do
                [[ -f "$tmpl" ]] || continue
                local dst="$ctx_dst/$(basename "$tmpl")"
                # Skip if source and destination resolve to the same file (symlinked ~/.claude)
                [[ "$(realpath "$tmpl")" == "$(realpath "$dst" 2>/dev/null)" ]] && { tmpl_count=$((tmpl_count + 1)); continue; }
                ln -sf "$tmpl" "$dst"
                tmpl_count=$((tmpl_count + 1))
            done
            log_success "Context templates deployed ($tmpl_count files)"
        fi

        log_success "Claude Code configuration deployed"
        log_info "  Config: CLAUDE.md, settings.json, agents/, hooks/, skills/"
        log_info "  Plugins: claude-plugins-official (27), ai-safety-plugins (core, research, writing, code, workflow, viz)"
    else
        log_warning "Claude directory not found at $DOT_DIR/claude"
    fi
fi

# ─── Codex ────────────────────────────────────────────────────────────────────

if [[ "$DEPLOY_CODEX" == "true" ]]; then
    log_section "DEPLOYING CODEX CLI CONFIGURATION"

    if [[ -d "$DOT_DIR/codex" ]]; then
        # Runtime files to preserve (from .gitignore)
        codex_runtime_files=(
            "auth.json" "config.toml" "history.jsonl"
            "tmp" "sessions" "log"
            "models_cache" "models_cache.json"
            "version" "version.json"
        )

        if [[ -L "$HOME/.codex" ]]; then
            # Already a symlink - refresh it
            rm "$HOME/.codex"
            log_info "Refreshed existing symlink"
        elif [[ -d "$HOME/.codex" ]]; then
            # Directory exists - smart merge
            log_info "Smart merge: preserving runtime files from existing ~/.codex"
            codex_backup_path="$HOME/.codex.backup.$(date -u +%d-%m-%Y_%H-%M-%S)"
            mv "$HOME/.codex" "$codex_backup_path"

            ln -sf "$DOT_DIR/codex" "$HOME/.codex"

            # Restore runtime files
            codex_restored=0
            for file in "${codex_runtime_files[@]}"; do
                if [[ -e "$codex_backup_path/$file" ]]; then
                    cp -r "$codex_backup_path/$file" "$HOME/.codex/" 2>/dev/null && ((codex_restored++))
                fi
            done

            if [[ $codex_restored -gt 0 ]]; then
                log_success "Restored $codex_restored runtime file(s)"
                log_info "Backup at: $codex_backup_path"
            fi
        fi

        # Create symlink if it doesn't exist
        if [[ ! -e "$HOME/.codex" ]]; then
            ln -sf "$DOT_DIR/codex" "$HOME/.codex"
        fi

        codex_sync_script="$DOT_DIR/scripts/sync_claude_to_codex.sh"
        codex_sync_script_display="${codex_sync_script/#$HOME/~}"

        if [[ -f "$codex_sync_script" ]]; then
            log_info "Syncing Claude permissions to Codex rules..."
            "$codex_sync_script" || log_warning "Codex permissions sync failed"
        else
            log_warning "Codex permissions sync script not found at $codex_sync_script_display"
        fi

        log_success "Codex CLI configuration deployed"
        log_info "  Config: AGENTS.md, skills/"
    else
        log_warning "Codex directory not found at $DOT_DIR/codex"
    fi
fi

# ─── Serena MCP ──────────────────────────────────────────────────────────────

if [[ "$DEPLOY_SERENA" == "true" ]]; then
    log_info "Deploying Serena MCP configuration..."

    SERENA_DIR="$HOME/.serena"
    SERENA_CONFIG="$SERENA_DIR/serena_config.yml"
    SERENA_DOTFILES="$DOT_DIR/config/serena/serena_config.yml"

    if [[ ! -f "$SERENA_DOTFILES" ]]; then
        log_warning "Serena config not found at $SERENA_DOTFILES"
    else
        mkdir -p "$SERENA_DIR"

        # Backup existing config if it's not a symlink
        if [[ -f "$SERENA_CONFIG" && ! -L "$SERENA_CONFIG" ]]; then
            backup_file "$SERENA_CONFIG"
        fi

        safe_symlink "$SERENA_DOTFILES" "$SERENA_CONFIG"
        log_success "Deployed Serena configuration"
        log_info "  Dashboard auto-open: disabled (open manually at http://localhost:24282/dashboard/)"
    fi
fi

# ─── Mouseless ────────────────────────────────────────────────────────────────

if [[ "$DEPLOY_MOUSELESS" == "true" ]]; then
    if is_macos; then
        log_info "Deploying Mouseless configuration..."

        MOUSELESS_DIR="$HOME/Library/Containers/net.sonuscape.mouseless/Data/.mouseless/configs"
        MOUSELESS_CONFIG="$MOUSELESS_DIR/config.yaml"
        MOUSELESS_DOTFILES="$DOT_DIR/config/mouseless/config.yaml"

        if [[ ! -f "$MOUSELESS_DOTFILES" ]]; then
            log_warning "Mouseless config not found at $MOUSELESS_DOTFILES"
        elif [[ ! -d "$MOUSELESS_DIR" ]]; then
            log_warning "Mouseless container not found — open Mouseless.app once to initialize it, then re-run ./deploy.sh --mouseless"
        else
            if [[ -f "$MOUSELESS_CONFIG" && ! -L "$MOUSELESS_CONFIG" ]]; then
                backup_file "$MOUSELESS_CONFIG"
            fi
            cp "$MOUSELESS_DOTFILES" "$MOUSELESS_CONFIG" && \
                log_success "Deployed Mouseless configuration" && \
                log_info "  keyboard_layout and app_version regenerated by Mouseless on first launch" && \
                log_info "  To sync UI changes back: sync-mouseless"
        fi
    else
        log_info "Mouseless is macOS-only, skipping"
    fi
fi

# ─── File Cleanup (macOS only) ────────────────────────────────────────────────

if [[ "$DEPLOY_CLEANUP" == "true" ]] && is_macos; then
    log_section "INSTALLING FILE CLEANUP (Downloads/Screenshots)"
    if [[ -f "$DOT_DIR/scripts/cleanup/install.sh" ]]; then
        "$DOT_DIR/scripts/cleanup/install.sh" --non-interactive || log_warning "File cleanup installation failed"
    else
        log_warning "File cleanup install script not found"
    fi
fi

# ─── Scheduled Tasks (parallel — independent launchd/cron jobs) ──────────────

{
    local scheduled_jobs=()

    if [[ "$DEPLOY_CLAUDE_CLEANUP" == "true" ]]; then
        [[ -f "$DOT_DIR/scripts/cleanup/setup_claude_cleanup.sh" ]] && \
            scheduled_jobs+=("claude-cleanup|$DOT_DIR/scripts/cleanup/setup_claude_cleanup.sh")
        [[ -f "$DOT_DIR/scripts/cleanup/setup_claude_tmpdir_cleanup.sh" ]] && \
            scheduled_jobs+=("tmpdir-cleanup|$DOT_DIR/scripts/cleanup/setup_claude_tmpdir_cleanup.sh")
    fi

    if [[ "$DEPLOY_AI_UPDATE" == "true" ]]; then
        [[ -f "$DOT_DIR/scripts/cleanup/setup_ai_update.sh" ]] && \
            scheduled_jobs+=("ai-update|$DOT_DIR/scripts/cleanup/setup_ai_update.sh")
    fi

    if [[ "$DEPLOY_BREW_UPDATE" == "true" ]]; then
        [[ -f "$DOT_DIR/scripts/cleanup/setup_brew_update.sh" ]] && \
            scheduled_jobs+=("brew-update|$DOT_DIR/scripts/cleanup/setup_brew_update.sh")
    fi

    if [[ "$DEPLOY_KEYBOARD" == "true" ]] && is_macos; then
        [[ -f "$DOT_DIR/scripts/cleanup/setup_keyboard_repeat.sh" ]] && \
            scheduled_jobs+=("keyboard-repeat|$DOT_DIR/scripts/cleanup/setup_keyboard_repeat.sh")
    fi

    if (( ${#scheduled_jobs[@]} > 0 )); then
        log_section "INSTALLING SCHEDULED TASKS"
        run_parallel "Setting up scheduled tasks" "${scheduled_jobs[@]}"
    fi
}

# ─── Bedtime Timezone Enforcement (macOS only) ───────────────────────────────

if [[ "$DEPLOY_BEDTIME" == "true" ]] && is_macos; then
    log_info "Setting up bedtime timezone enforcement..."
    if [[ -f "$DOT_DIR/scripts/cleanup/setup_bedtime_enforce.sh" ]]; then
        "$DOT_DIR/scripts/cleanup/setup_bedtime_enforce.sh" || log_warning "Bedtime enforcement setup failed"
    else
        log_warning "Bedtime enforcement setup script not found"
    fi
fi


# ─── Text Replacements Sync (macOS only) ─────────────────────────────────

if [[ "${DEPLOY_TEXT_REPLACEMENTS:-false}" == "true" ]] && is_macos; then
    log_info "Syncing text replacements..."
    if command -v uv &>/dev/null; then
        uv run --with ruamel.yaml "$DOT_DIR/scripts/sync_text_replacements.py" sync || \
            log_warning "Text replacements sync failed"

        # Install automated daily sync
        if [[ -f "$DOT_DIR/scripts/cleanup/setup_text_replacements_sync.sh" ]]; then
            "$DOT_DIR/scripts/cleanup/setup_text_replacements_sync.sh" || \
                log_warning "Failed to setup automated text replacements sync"
        fi
    else
        log_warning "uv not found — skipping text replacements sync"
    fi
fi

# ─── VPN Split Tunneling (macOS only) ────────────────────────────────────────

if [[ "${DEPLOY_VPN:-false}" == "true" ]] && is_macos; then
    log_section "INSTALLING VPN SPLIT TUNNEL DAEMON"

    VPN_PLIST_LABEL="com.dotfiles.tailscale-route-fix"
    VPN_PLIST_PATH="/Library/LaunchDaemons/${VPN_PLIST_LABEL}.plist"
    VPN_SCRIPT_PATH="/usr/local/bin/tailscale-route-fix"

    sudo -v  # Acquire sudo upfront

    # Idempotent: unload existing before loading new
    sudo launchctl bootout "system/${VPN_PLIST_LABEL}" 2>/dev/null || true

    # Install script
    sudo mkdir -p /usr/local/bin
    sudo cp "$DOT_DIR/scripts/vpn/tailscale_route_fix.sh" "$VPN_SCRIPT_PATH"
    sudo chmod 755 "$VPN_SCRIPT_PATH"
    sudo chown root:wheel "$VPN_SCRIPT_PATH"

    # Install plist
    sudo cp "$DOT_DIR/scripts/vpn/${VPN_PLIST_LABEL}.plist" "$VPN_PLIST_PATH"
    sudo chmod 644 "$VPN_PLIST_PATH"
    sudo chown root:wheel "$VPN_PLIST_PATH"

    # Log rotation: 5 files, 1MB max, compressed
    echo "/var/log/tailscale-route-fix.log 640 5 1000 * J" | \
        sudo tee /etc/newsyslog.d/tailscale-route-fix.conf > /dev/null

    # Load daemon
    sudo launchctl bootstrap system "$VPN_PLIST_PATH"
    sudo launchctl enable "system/${VPN_PLIST_LABEL}"
    sudo launchctl kickstart -k "system/${VPN_PLIST_LABEL}"

    # Verify
    if sudo launchctl print "system/${VPN_PLIST_LABEL}" &>/dev/null; then
        log_success "VPN split tunnel daemon installed and running"
    else
        log_warning "VPN daemon installed but may not be running — check: sudo launchctl print system/${VPN_PLIST_LABEL}"
    fi
fi

# ─── Safari Web App Registry (macOS only) ────────────────────────────────────

if [[ "$DEPLOY_EDITOR" == "true" ]] && is_macos && [[ -f "$DOT_DIR/custom_bins/safari-web-apps-scan" ]]; then
    "$DOT_DIR/custom_bins/safari-web-apps-scan" || log_warning "Safari web app scan failed (non-critical)"
fi

# ─── File Type Associations (macOS only) ─────────────────────────────────────

if [[ "$DEPLOY_FILE_APPS" == "true" ]] && is_macos; then
    log_section "SETTING DEFAULT FILE ASSOCIATIONS"

    ASSOC_CONF="$DOT_DIR/config/file_associations.conf"
    if [[ ! -f "$ASSOC_CONF" ]]; then
        log_warning "config/file_associations.conf not found, skipping"
    else
        source "$ASSOC_CONF"

        # Compile Swift tool if needed (binary missing or source newer)
        tool_dir="$DOT_DIR/tools/set-default-app"
        tool_bin="$tool_dir/set-default-app"
        if [[ ! -x "$tool_bin" ]] || [[ "$tool_dir/main.swift" -nt "$tool_bin" ]]; then
            log_info "Compiling set-default-app..."
            if swiftc -O -o "$tool_bin" "$tool_dir/main.swift" 2>/dev/null; then
                log_success "Compiled set-default-app"
            else
                log_warning "Swift compilation failed — skipping file associations"
                DEPLOY_FILE_APPS=false
            fi
        fi

        if [[ "$DEPLOY_FILE_APPS" == "true" ]]; then
            "$tool_bin" "$EDITOR_BUNDLE_ID" "${EXTENSIONS[@]}"
            log_success "File associations set to $EDITOR_BUNDLE_ID"
        fi
    fi
fi

# ─── Wait for background builds ─────────────────────────────────────────────

if [[ -n "${CLAUDE_TOOLS_PID:-}" ]]; then
    if wait "$CLAUDE_TOOLS_PID" 2>/dev/null; then
        log_success "claude-tools built and deployed to custom_bins/"
    else
        log_warning "claude-tools build failed (bash fallback will be used)"
    fi
    [[ -f "$CLAUDE_TOOLS_LOG" ]] && cat "$CLAUDE_TOOLS_LOG" && rm -f "$CLAUDE_TOOLS_LOG"
fi

# ─── Done ─────────────────────────────────────────────────────────────────────

echo ""
log_success "Deployment complete!"
echo ""
echo "Next steps:"
echo "  Restart your terminal or run: source $RC_FILE"
