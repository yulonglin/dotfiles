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
#   ./deploy.sh --aliases=work,custom # Add extra aliases
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

OPTIONS:
    --profile=NAME    Use a profile: personal, work, server, minimal
    --vim             Deploy vimrc
    --editor          Deploy VSCode/Cursor settings
    --claude          Deploy Claude Code config (~/.claude symlink)
    --codex           Deploy Codex CLI config (~/.codex symlink)
    --serena          Deploy Serena MCP config (~/.serena symlink)
    --ghostty         Deploy Ghostty terminal config
    --htop            Deploy htop configuration
    --pdb             Deploy pdb++ debugger config
    --matplotlib      Deploy matplotlib styles
    --git-hooks       Deploy global git hooks
    --secrets         Sync secrets with GitHub gist
    --cleanup         Install file cleanup: Downloads/Screenshots (macOS only)
    --claude-cleanup  Install Claude Code session cleanup (both platforms)
    --ai-update       Install AI tools auto-update (daily, both platforms)
    --brew-update     Install weekly package upgrade + cleanup (brew/apt/dnf/pacman)
    --aliases=LIST    Additional alias scripts (comma-separated)
    --append          Append to existing configs instead of overwrite
    --ascii=FILE      ASCII art file for shell startup
    --no-<component>  Disable a component (e.g., --no-editor)

EXAMPLES:
    ./deploy.sh                           # Use defaults from config.sh
    ./deploy.sh --profile=server          # Server profile
    ./deploy.sh --aliases=speechmatics    # Add work aliases

Git configuration is always deployed.
EOF
}

# Parse CLI arguments (overrides config.sh)
parse_args "$@"

# ─── Main Deployment ──────────────────────────────────────────────────────────

log_section "DEPLOYING DOTFILES"
echo "Platform: $PLATFORM"
echo "Profile: $PROFILE"
echo "Append mode: $DEPLOY_APPEND"
echo ""

# Install zsh if not present
if ! cmd_exists zsh; then
    log_info "ZSH not found, installing..."
    if is_macos; then
        brew_install zsh
    else
        apt_install zsh
    fi
fi

# Set operator based on append flag
OP=">"
[[ "$DEPLOY_APPEND" == "true" ]] && OP=">>"

# ─── tmux ─────────────────────────────────────────────────────────────────────

log_info "Deploying tmux configuration..."
eval "echo \"source $DOT_DIR/config/tmux.conf\" $OP \"\$HOME/.tmux.conf\""

# ─── Vim ──────────────────────────────────────────────────────────────────────

if [[ "$DEPLOY_VIM" == "true" ]]; then
    log_info "Deploying vimrc..."
    safe_symlink "$DOT_DIR/config/vimrc" "$HOME/.vimrc"
fi

# ─── Shell Configuration ──────────────────────────────────────────────────────

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

# Atuin - unified shell history
if [ -f "\$HOME/.atuin/bin/env" ]; then
    source "\$HOME/.atuin/bin/env"
    eval "\$(atuin init bash --disable-up-arrow)"
elif command -v atuin &> /dev/null; then
    eval "\$(atuin init bash --disable-up-arrow)"
fi

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

# Deploy Atuin config if exists
if [[ -f "$DOT_DIR/config/atuin.toml" ]]; then
    mkdir -p "$HOME/.config/atuin"
    cp "$DOT_DIR/config/atuin.toml" "$HOME/.config/atuin/config.toml"
    log_success "Deployed Atuin configuration"
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

# ─── Secrets Sync ─────────────────────────────────────────────────────────────

if [[ "$DEPLOY_SECRETS" == "true" ]]; then
    log_section "SYNCING SECRETS"
    sync_secrets || log_warning "Secrets sync failed (continuing anyway)"

    # Install automated daily sync
    log_info "Setting up automated daily secrets sync..."
    "$DOT_DIR/scripts/cleanup/setup_secrets_sync.sh" || log_warning "Failed to setup automated sync"
fi

# ─── Git Configuration ────────────────────────────────────────────────────────

log_section "DEPLOYING GIT CONFIGURATION"
deploy_git_config

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

# ─── Finicky (macOS) ──────────────────────────────────────────────────────────

if is_macos && [[ -f "$DOT_DIR/config/finicky.js" ]]; then
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
                read -rp "Choice [l/d/s]: " htop_choice

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

        # Register ai-safety-plugins marketplace
        if command -v claude &>/dev/null; then
            MARKETPLACE_REPO="${CODE_DIR:-$HOME/code}/ai-safety-plugins"
            if [[ -d "$MARKETPLACE_REPO/.claude-plugin" ]]; then
                # Local development — register local path (zero-friction edits)
                if ! claude plugin marketplace list 2>/dev/null | grep -q "ai-safety-plugins"; then
                    log_info "Registering ai-safety-plugins marketplace (local)..."
                    claude plugin marketplace add "$MARKETPLACE_REPO" 2>/dev/null || \
                        log_warning "Failed to register marketplace — run manually: claude plugin marketplace add $MARKETPLACE_REPO"
                fi
            else
                # Other machines — register GitHub URL
                if ! claude plugin marketplace list 2>/dev/null | grep -q "ai-safety-plugins"; then
                    log_info "Registering ai-safety-plugins marketplace (GitHub)..."
                    claude plugin marketplace add yulonglin/ai-safety-plugins 2>/dev/null || \
                        log_warning "Failed to register marketplace — run manually: /plugin marketplace add yulonglin/ai-safety-plugins"
                fi
            fi
            # Install/update all plugins from the marketplace
            claude plugin marketplace update ai-safety-plugins 2>/dev/null || true
        else
            log_info "Claude CLI not found — run after install: /plugin marketplace add yulonglin/ai-safety-plugins"
        fi

        # Clean plugin-created symlinks from skills/ (they cause duplicate entries)
        if [[ -f "$DOT_DIR/scripts/cleanup/clean_plugin_symlinks.sh" ]]; then
            "$DOT_DIR/scripts/cleanup/clean_plugin_symlinks.sh"
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
        log_info "  Plugins: ai-safety-plugins (core-toolkit, research-toolkit, writing-toolkit, code-toolkit, workflow-toolkit, viz-toolkit)"
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

# ─── File Cleanup (macOS only) ────────────────────────────────────────────────

if [[ "$DEPLOY_CLEANUP" == "true" ]] && is_macos; then
    log_section "INSTALLING FILE CLEANUP (Downloads/Screenshots)"
    if [[ -f "$DOT_DIR/scripts/cleanup/install.sh" ]]; then
        "$DOT_DIR/scripts/cleanup/install.sh" --non-interactive || log_warning "File cleanup installation failed"
    else
        log_warning "File cleanup install script not found"
    fi
fi

# ─── Claude Code Cleanup (both platforms) ─────────────────────────────────────

if [[ "$DEPLOY_CLAUDE_CLEANUP" == "true" ]]; then
    log_section "INSTALLING CLAUDE CODE SESSION CLEANUP"
    if [[ -f "$DOT_DIR/scripts/cleanup/setup_claude_cleanup.sh" ]]; then
        "$DOT_DIR/scripts/cleanup/setup_claude_cleanup.sh" || log_warning "Claude cleanup installation failed"
    else
        log_warning "Claude cleanup script not found"
    fi

    # Weekly tmpdir cleanup (deletes files >7 days old)
    if [[ -f "$DOT_DIR/scripts/cleanup/setup_claude_tmpdir_cleanup.sh" ]]; then
        "$DOT_DIR/scripts/cleanup/setup_claude_tmpdir_cleanup.sh" || log_warning "Claude tmpdir cleanup installation failed"
    fi
fi

# ─── AI Tools Auto-Update (both platforms) ──────────────────────────────────

if [[ "$DEPLOY_AI_UPDATE" == "true" ]]; then
    log_section "INSTALLING AI TOOLS AUTO-UPDATE"
    if [[ -f "$DOT_DIR/scripts/cleanup/setup_ai_update.sh" ]]; then
        "$DOT_DIR/scripts/cleanup/setup_ai_update.sh" || log_warning "AI update setup failed"
    else
        log_warning "AI update setup script not found"
    fi
fi

# ─── Package Auto-Update (both platforms) ────────────────────────────────────

if [[ "$DEPLOY_BREW_UPDATE" == "true" ]]; then
    log_section "INSTALLING PACKAGE AUTO-UPDATE"
    if [[ -f "$DOT_DIR/scripts/cleanup/setup_brew_update.sh" ]]; then
        "$DOT_DIR/scripts/cleanup/setup_brew_update.sh" || log_warning "Package update setup failed"
    else
        log_warning "Brew update setup script not found"
    fi
fi

# ─── Done ─────────────────────────────────────────────────────────────────────

echo ""
log_success "Deployment complete!"
echo ""
echo "Next steps:"
echo "  Restart your terminal or run: source $RC_FILE"
