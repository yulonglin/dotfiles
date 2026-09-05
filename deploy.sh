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

# Non-interactive hardening: no hidden prompt below may block an unattended run.
# git must never open a credential prompt (clones here are public repos), apt
# must never open needrestart's ncurses dialog on Ubuntu 22.04+, and services
# apt touches restart automatically. Attended runs lose nothing.
export GIT_TERMINAL_PROMPT=0
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
# GIT_TERMINAL_PROMPT stops the credential prompt but not a stalled TCP
# connection, and DEBIAN_FRONTEND stops needrestart but not the dpkg lock —
# on a fresh box with unattended-upgrades running at boot, apt waits forever.
# These two bound what those variables leave unbounded.
export GIT_HTTP_LOW_SPEED_LIMIT=1000 GIT_HTTP_LOW_SPEED_TIME=30
export APT_LOCK_TIMEOUT="${APT_LOCK_TIMEOUT:-120}"

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
source "$DOT_DIR/scripts/helpers/dotfiles_secrets.sh"

# Abort if DOT_DIR is a worktree rather than the main checkout (--allow-worktree
# overrides). Must run before parse_args so a mistake can't reach any component.
guard_not_worktree "$0" "$@"

# ─── Help ─────────────────────────────────────────────────────────────────────

show_help() {
    cat <<EOF
Usage: ./deploy.sh [OPTIONS]

Deploy dotfile configurations. Settings are in config.sh.

PROFILES (pick by what the machine is FOR):
    (no flag)         'standard' — shell, editor, git, Claude/Codex, supply-chain
                      defenses. Nothing scheduled, nothing GUI. This is the
                      default; it is NOT the full set.
    --devbox          A machine you live on: the full set (was --personal)
    --agent           Ephemeral box you DO code on: standard + per-project secrets
    --bare            Ephemeral box you will NOT code on: shell + uv only
    --server          Shared machine: no GUI, no file cleanup. NOTE: still
                      installs the recurring agent jobs (mcp-sync, usage-ping,
                      tmux-resume, dep-audit, stale-claims) — unchanged from
                      before, so curl|bash provisioning keeps working
    --minimal         Suppress ALL components — specify what you want explicitly
    --no-defaults     Same as --minimal (clearer name)
    --profile=NAME    standard, devbox, agent, bare, server, cloud, minimal
    --default         Alias for --server
    --personal        Synonym for --devbox (kept for existing invocations)

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
    --alfred          Repair Dropbox-synced Alfred prefs: de-quarantine, +x, hotkey (macOS only)
    --ghostty         Deploy Ghostty terminal config
    --zed             Deploy Zed editor config (settings + keymap, symlinked)
    --htop            Deploy htop configuration
    --gitui           Deploy gitui theme (theme-reactive, symlinked)
    --pdb             Deploy pdb++ debugger config
    --matplotlib      Deploy matplotlib styles
    --playwright      Deploy Playwright + Chromium for browser tests (~650MB, opt-in)
    --git-hooks       Deploy global git hooks
    --pkg-configs     Deploy package manager security configs (7-day quarantine)
    --secrets         Sync secrets with GitHub gist
    --secrets-env     Verify BWS secrets are configured
    --dep-audit       Install weekly dependency audit (supply chain defense)
    --stale-claims    Install weekly staleness audit of auto-loaded AI instructions
    --cleanup         Install file cleanup: Downloads/Screenshots (macOS only)
    --claude-cleanup  Install Claude Code session cleanup (both platforms)
    --ai-update       Install AI tools auto-update (daily, both platforms)
    --mcp-sync        Install daily shared MCP sync for Claude and Codex
    --dotfiles-sync   Install daily commit + rebase + push of this repo (08:05, both platforms)
    --brew-update     Install weekly package upgrade + cleanup (brew/apt/dnf/pacman)
    --keyboard        Install keyboard repeat enforcement at login (macOS only)
    --hide-idle-apps  Hide, then close, then quit apps left covered up, per config/app-lifecycle.yaml (macOS only, off by default)
    --file-apps       Set default editor for coding file types (macOS only)
    --bedtime         Install bedtime timezone enforcement (macOS only, opt-in)
    --bearcli         Symlink Bear CLI → /usr/local/bin (macOS only, for cron/scripts)
    --vpn             Install NordVPN+Tailscale split tunnel daemon (macOS only)
    --pueue           Deploy Pueue + systemd resource management (Linux only)
    --storage         Write per-machine data-volume config (Linux only)
    --bws             Install Bitwarden Secrets Manager CLI (bws)
    --text-replacements  Sync text replacements: macOS + Alfred (macOS only)
    --aliases=LIST    Additional alias scripts (comma-separated)
    --append          Append to existing configs instead of overwrite
    --ascii=NAME      Shell-startup art from config/ascii_arts/ (cat, dog, paw, stars);
                      none removes it. Off by default; the choice persists across deploys
    --no-<component>  Disable a component (e.g., --no-editor)
    --allow-worktree  Deploy even though DOT_DIR is a git worktree. Refused by
                      default: it repoints ~/.claude and ~20 other user symlinks
                      at a directory cwrm/cwclean will delete.
    --non-interactive Skip the component menu and deploy the default set. The
                      menu is the script's only prompt; everything after it
                      already runs with safe defaults (git conflicts keep
                      existing values).
    --allow-worktree-deploy
                      Deploy even though this copy of the script lives in a git
                      worktree. Refused by default: DOT_DIR follows the script,
                      so global symlinks (~/.claude, ~/.codex, ...) would be
                      repointed at an ephemeral worktree. ~/.claude would lose
                      its credentials and session backlog in the process.

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

# ─── Worktree guard ───────────────────────────────────────────────────────────
# DOT_DIR is derived from this script's own location (see top of file), and most
# components symlink GLOBAL config at "$DOT_DIR/<thing>" — ~/.claude, ~/.codex,
# ~/.serena, ~/.config/zed, and so on. Run from a git worktree, that repoints
# global config at a directory that is ephemeral by design.
#
# The ~/.claude case is the damaging one. The `-L` branch of the Claude
# component rm's the existing symlink and relinks it, and unlike the `-d`
# branch it restores NO runtime files — so the new target starts with an empty
# projects/, jobs/, and no .credentials.json. That reads as a logout, and the
# entire session backlog goes invisible until the symlink is pointed back.
# Observed 2026-07-27: ~/.claude repointed at a worktree, credentials gone,
# 163 jobs replaced by 7.
#
# Override with --allow-worktree-deploy (or ALLOW_WORKTREE_DEPLOY=1) when you
# genuinely mean to deploy from a worktree.
if [[ "${ALLOW_WORKTREE_DEPLOY:-${DEPLOY_ALLOW_WORKTREE_DEPLOY:-false}}" != "true" \
   && "${ALLOW_WORKTREE_DEPLOY:-0}" != "1" ]]; then
    _git_dir="$(git -C "$DOT_DIR" rev-parse --git-dir 2>/dev/null || true)"
    if [[ "$_git_dir" == */worktrees/* || "$DOT_DIR" == */.claude/worktrees/* ]]; then
        _main_dir="$(git -C "$DOT_DIR" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
        _main_dir="${_main_dir:+$(dirname "$_main_dir")/deploy.sh}"
        cat >&2 <<EOF
Error: refusing to deploy from a git worktree.

  DOT_DIR: $DOT_DIR

Deploying from here would repoint global config (~/.claude, ~/.codex, ~/.serena,
...) at this worktree. ~/.claude in particular would lose its credentials and
its whole session backlog, which presents as being logged out.

Run the main checkout's copy instead:
  ${_main_dir:-<main-checkout>/deploy.sh} $*

Or, if this is deliberate:
  ./deploy.sh --allow-worktree-deploy $*
EOF
        exit 1
    fi
fi

# Make custom_bins (claude-tools) discoverable, then fetch a prebuilt
# claude-tools matching this platform so the component menu works before the
# from-source build below has run.
export PATH="$DOT_DIR/custom_bins:$PATH"
bootstrap_claude_tools || true

show_component_menu deploy

# Cache sudo once up front if a privileged component is selected (VPN daemon,
# Bear CLI symlink into /usr/local/bin, or Linux pueue systemd setup), so the
# password is requested once here rather than blocking mid-deploy.
if [[ "${DEPLOY_VPN:-false}" == "true" || "${DEPLOY_BEARCLI:-false}" == "true" \
    || ( "$(uname -s)" == "Linux" && "${DEPLOY_PUEUE:-false}" == "true" ) ]]; then
    front_load_sudo
fi

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
for _af in "\$DOT_DIR"/config/aliases/*.sh; do
  [ -r "\$_af" ] && source "\$_af"
done
unset _af
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

    # Shell-startup art: config/start.txt is untracked and per machine; only --ascii touches it
    if [[ "$DEPLOY_ASCII_FILE" == "none" ]]; then
        rm -f "$DOT_DIR/config/start.txt"
        log_info "Removed shell-startup art"
    elif [[ -n "$DEPLOY_ASCII_FILE" ]]; then
        ascii_src="$DOT_DIR/config/ascii_arts/${DEPLOY_ASCII_FILE%.txt}.txt"
        if [[ -f "$ascii_src" ]]; then
            command cp -f "$ascii_src" "$DOT_DIR/config/start.txt"
            log_info "Using shell-startup art: ${DEPLOY_ASCII_FILE%.txt}"
        else
            log_warning "No such art '$DEPLOY_ASCII_FILE' — available: $(ls "$DOT_DIR/config/ascii_arts" | sed 's/\.txt$//' | tr '\n' ' ')"
        fi
    fi
fi

# ─── Gist Sync (SSH config, authorized_keys, git identity) ───────────────────

if [[ "$DEPLOY_SECRETS" == "true" ]]; then
    log_section "SYNCING GIST"
    # SSH config (synced from gist) uses ControlPath ~/.ssh/controlmasters/
    mkdir -p "$HOME/.ssh/controlmasters"
    sync_gist || log_warning "Gist sync failed (continuing anyway)"

    # Install automated daily sync
    log_info "Setting up automated daily gist sync..."
    "$DOT_DIR/scripts/cleanup/setup_gist_sync.sh" || log_warning "Failed to setup automated gist sync"
fi

# ─── Secrets (BWS) ───────────────────────────────────────────────────────────

if [[ "${DEPLOY_SECRETS_ENV:-false}" == "true" ]]; then
    log_section "SECRETS (BWS)"

    if ! cmd_exists bws; then
        log_warning "bws not installed — run install.sh"
    else
        local bws_token_file
        bws_token_file="$(dotfiles_secrets_bws_token_file)"
        if [[ -f "$bws_token_file" ]]; then
            log_success "BWS token found at $bws_token_file"
        else
            log_info "No BWS token at $bws_token_file — run: secrets init"
        fi
    fi

    dotfiles_secrets_harden_permissions
    log_info "Hardened private secret file permissions"

    if [[ -e "$DOT_DIR/.secrets" ]]; then
        log_warning "Legacy plaintext secrets still exist at $DOT_DIR/.secrets"
        log_warning "  Safe to delete after confirming your repos use 'secrets envrc'/.envrc"
    fi
    if [[ -e "$DOT_DIR/.env" || -L "$DOT_DIR/.env" ]]; then
        log_warning "Legacy local .env still exists at $DOT_DIR/.env"
        log_warning "  'secrets envrc' can compare it against encrypted secrets and remove it"
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
                ln -sf "$hook" "$HOME/.git-hooks/$(basename "$hook")"
                chmod +x "$hook"
            fi
        done

        git config --global core.hooksPath "$HOME/.git-hooks"
        log_success "Deployed global git hooks to ~/.git-hooks (symlinked — live updates)"
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

# ─── Package Manager Security Configs ────────────────────────────────────────

if [[ "$DEPLOY_PKG_CONFIGS" == "true" ]]; then
    log_info "Deploying package manager security configs..."

    safe_symlink "$DOT_DIR/config/npmrc" "$HOME/.npmrc"
    safe_symlink "$DOT_DIR/config/bunfig.toml" "$HOME/.bunfig.toml"

    # pnpm global rc path is platform-specific
    local pnpm_config_dir
    if is_macos; then
        pnpm_config_dir="$HOME/Library/Preferences/pnpm"
    else
        pnpm_config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/pnpm"
    fi
    mkdir -p "$pnpm_config_dir"
    safe_symlink "$DOT_DIR/config/pnpmrc" "$pnpm_config_dir/rc"

    local uv_config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/uv"
    mkdir -p "$uv_config_dir"
    safe_symlink "$DOT_DIR/config/uv.toml" "$uv_config_dir/uv.toml"

    log_success "Package manager configs deployed — 7-day quarantine active"
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

# ─── Bear CLI (macOS) ─────────────────────────────────────────────────────────
# Symlinks Bear's CLI to /usr/local/bin so it works in cron jobs and scripts
# (shell aliases don't carry into non-interactive shells).

if [[ "$DEPLOY_BEARCLI" == "true" ]] && is_macos; then
    BEAR_APP="/Applications/Bear.app"
    BEAR_SRC="$BEAR_APP/Contents/MacOS/bearcli"
    BEAR_LINK="/usr/local/bin/bearcli"

    if [[ ! -d "$BEAR_APP" ]]; then
        log_warning "Bear not installed — install from the Mac App Store, then re-run with --bearcli."
    elif [[ ! -x "$BEAR_SRC" ]]; then
        log_warning "Bear is installed but bearcli is missing at $BEAR_SRC (requires Bear 2+). Skipping."
    elif [[ -L "$BEAR_LINK" && "$(readlink "$BEAR_LINK")" == "$BEAR_SRC" ]]; then
        log_info "Bear CLI symlink already in place at $BEAR_LINK"
    else
        log_info "Symlinking Bear CLI to $BEAR_LINK..."
        # Try without sudo first; only escalate if /usr/local/bin isn't writable.
        if mkdir -p /usr/local/bin 2>/dev/null && [[ -w /usr/local/bin ]]; then
            ln -sf "$BEAR_SRC" "$BEAR_LINK"
            log_success "Symlinked $BEAR_SRC → $BEAR_LINK"
        else
            log_info "  /usr/local/bin not writable — using sudo (you may be prompted)"
            sudo mkdir -p /usr/local/bin
            sudo ln -sf "$BEAR_SRC" "$BEAR_LINK"
            log_success "Symlinked (via sudo) $BEAR_SRC → $BEAR_LINK"
        fi
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

# ─── Zed ──────────────────────────────────────────────────────────────────────

if [[ "$DEPLOY_ZED" == "true" ]]; then
    log_info "Deploying Zed configuration..."

    ZED_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/zed"

    if [[ -d "$DOT_DIR/config/zed" ]]; then
        mkdir -p "$ZED_DIR"

        # Settings + Keymap (safe_symlink handles backup internally)
        safe_symlink "$DOT_DIR/config/zed/settings.json" "$ZED_DIR/settings.json"

        if [[ -f "$DOT_DIR/config/zed/keymap.json" ]]; then
            safe_symlink "$DOT_DIR/config/zed/keymap.json" "$ZED_DIR/keymap.json"
        fi

        log_info "  Search: gitignored files included"
        log_info "  AI: Cmd+K for inline edit, Anthropic agent"
        log_info "  Theme: One Dark Pro (auto dark/light switching)"
        log_info "  SSH: reads hosts from ~/.ssh/config"
    else
        log_warning "Zed config not found at $DOT_DIR/config/zed/"
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
                local htop_choice=""
                if [[ "${NON_INTERACTIVE:-false}" == "true" ]] || ! [[ -t 0 ]]; then
                    log_info "Non-interactive — skipping htop (use --force to overwrite)"
                    htop_choice="s"
                else
                    echo ""
                    echo "Options:"
                    echo "  [l] Keep local config (update dotfiles)"
                    echo "  [d] Keep dotfiles config (discard local changes)"
                    echo "  [s] Skip htop deployment"
                    echo ""
                    # A TTY is not proof a human is watching it. On no answer,
                    # fall through to the same choice the non-interactive branch
                    # makes — skip — rather than blocking the deploy forever.
                    if ! read -t "${DOTFILES_PROMPT_TIMEOUT:-60}" -r "htop_choice?Choice [l/d/s]: "; then
                        echo ""
                        log_info "No answer in ${DOTFILES_PROMPT_TIMEOUT:-60}s — skipping htop"
                        htop_choice="s"
                    fi
                fi

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

# ─── gitui ────────────────────────────────────────────────────────────────────

if [[ "$DEPLOY_GITUI" == "true" ]]; then
    log_info "Deploying gitui theme..."

    GITUI_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/gitui"
    GITUI_THEME="$GITUI_DIR/theme.ron"
    GITUI_DOTFILES="$DOT_DIR/config/gitui/theme.ron"

    if [[ ! -f "$GITUI_DOTFILES" ]]; then
        log_warning "gitui theme not found at $GITUI_DOTFILES"
    else
        mkdir -p "$GITUI_DIR"

        # Back up an existing real file (gitui only reads theme.ron, never overwrites)
        if [[ -f "$GITUI_THEME" && ! -L "$GITUI_THEME" ]]; then
            backup_file "$GITUI_THEME"
        fi

        safe_symlink "$GITUI_DOTFILES" "$GITUI_THEME"
        log_success "Deployed gitui theme (theme-reactive — tracks active Ghostty theme)"
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

# ─── Playwright Browsers ──────────────────────────────────────────────────────

# Off by default, and it is the download that decides that: Chromium plus its
# headless shell is ~650MB, which is not something to pull onto every throwaway
# pod. Machines that have to run the annotation-layer browser tests opt in with
# --playwright.
#
# The browsers are keyed to the package version that fetched them. A cache
# holding chromium-1228 is invisible to a playwright that wants 1234, and the
# failure surfaces as "Executable doesn't exist at ...", which reads like a
# missing install rather than a version skew. Installing the CLI and running
# its OWN `playwright install` is what keeps the two in step: whatever version
# lands here is the version that chooses the browser build.
if [[ "$DEPLOY_PLAYWRIGHT" == "true" ]]; then
    log_info "Deploying Playwright browsers..."

    if ! cmd_exists uv; then
        log_warning "uv not found — skipping Playwright (install.sh provides uv)"
    else
        # Machine-level on purpose. The browsers live in one shared cache that
        # every checkout reads, so this is not per-repo state; a repo only
        # needs the Python package, which `uv run --with playwright` supplies.
        # PLAYWRIGHT_BROWSERS_PATH is honoured if the environment sets it, so a
        # box that tiers bulky caches onto an attached volume keeps them there.
        pw_browsers="${PLAYWRIGHT_BROWSERS_PATH:-$HOME/.cache/ms-playwright}"

        if uv tool install --quiet playwright 2>/dev/null || cmd_exists playwright; then
            pw_version=$(playwright --version 2>/dev/null | awk '{print $NF}')
            log_info "  playwright ${pw_version:-unknown} → $pw_browsers"

            # Chromium only. Firefox and WebKit triple the download and nothing
            # in this repo drives them.
            if playwright install chromium >/dev/null 2>&1; then
                log_success "Chromium ready for the browser tests"
            else
                # On a bare Linux box the shared libraries are missing too, and
                # that install needs root — which deploy.sh does not assume.
                log_warning "playwright install chromium failed"
                log_info "  On Linux the system libraries may be missing:"
                log_info "    sudo \$(command -v playwright) install-deps chromium"
            fi
        else
            log_warning "Could not install the playwright CLI via uv"
        fi
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
CLAUDE_TOOLS_ASSET="$(_claude_tools_asset)"
if [[ "$DEPLOY_CLAUDE_TOOLS" == "true" ]] && [[ -f "$DOT_DIR/tools/claude-tools/Cargo.toml" ]] && cmd_exists cargo && [[ -n "$CLAUDE_TOOLS_ASSET" ]]; then
    log_info "Building claude-tools (background)..."
    CLAUDE_TOOLS_LOG=$(mktemp)
    (
        # Build to the platform-specific asset (e.g. claude-tools-darwin-arm64),
        # never to custom_bins/claude-tools itself — that path is the
        # cross-platform dispatch wrapper (see custom_bins/claude-tools) and
        # overwriting it with a native binary breaks it on every other platform
        # once committed.
        # Bounded, and not --quiet: this runs in the background with its output
        # captured to a log, so the only thing --quiet bought was an empty log
        # on failure. The deadline is what matters — a bare `wait` below has no
        # timeout of its own, so an unbounded cargo build here hangs the whole
        # deploy at the very last step, silently. This is the same stall class
        # the canary is named for; it just lived in deploy.sh rather than in
        # _build_claude_tools_from_source.
        cd "$DOT_DIR/tools/claude-tools" \
        && run_with_timeout "${DOTFILES_BUILD_TIMEOUT:-900}" cargo build --release 2>&1 && \
        cp "$DOT_DIR/tools/claude-tools/target/release/claude-tools" "$DOT_DIR/custom_bins/$CLAUDE_TOOLS_ASSET" && \
        chmod +x "$DOT_DIR/custom_bins/$CLAUDE_TOOLS_ASSET"
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
            backup_path="$HOME/.claude.backup.$(date -u +%Y-%m-%d_%H-%M-%S)"
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

        # Plugin marketplaces are declared natively in claude/settings.json
        # (extraKnownMarketplaces), which is symlinked into place above — no sync step needed.

        # Clean plugin-created symlinks from skills/ (they cause duplicate entries)
        if [[ -f "$DOT_DIR/scripts/cleanup/clean_plugin_symlinks.sh" ]]; then
            "$DOT_DIR/scripts/cleanup/clean_plugin_symlinks.sh"
        fi

        # Clean stale plugin cache versions (prevents skill shadowing warnings)
        if command -v claude-cache-clean &>/dev/null; then
            claude-cache-clean --apply
        fi

        # Re-apply the remember-plugin handoff patch. Upstream puts the
        # `cat "$REMEMBER_HANDOFF"` OUTSIDE the fingerprint if/else, so a handoff
        # that was already delivered is re-injected in full every session instead
        # of collapsing to its one-line staleness notice (measured: a 14KB file
        # re-delivered 495 times since 2026-08-13). A version bump lands in a NEW
        # cache directory and silently reverts the fix, so it is re-applied on
        # every deploy rather than patched once by hand. Fails soft: a changed
        # upstream shape warns and is left alone, and never aborts the deploy.
        remember_cache="$HOME/.claude/plugins/cache/claude-plugins-official/remember"
        if [[ -d "$remember_cache" ]]; then
            remember_hook=$(find "$remember_cache" -mindepth 3 -maxdepth 3 \
                -path '*/scripts/session-start-hook.sh' 2>/dev/null | sort -V | tail -1)
            if [[ -n "$remember_hook" ]]; then
                remember_result=$(python3 -c '
import io, sys
UNPATCHED = "    fi\n    cat \"$REMEMBER_HANDOFF\"\n"
PATCHED = "        cat \"$REMEMBER_HANDOFF\"\n    fi\n"
path = sys.argv[1]
src = io.open(path, encoding="utf-8").read()
if PATCHED in src:
    print("already-patched")
elif UNPATCHED not in src:
    print("no-match")
    raise SystemExit(3)
else:
    io.open(path, "w", encoding="utf-8").write(src.replace(UNPATCHED, PATCHED, 1))
    print("patched")
' "$remember_hook" 2>/dev/null) || remember_result="error"
                case "$remember_result" in
                    patched)         log_success "Patched remember handoff re-delivery ($remember_hook)" ;;
                    already-patched) log_info "Remember handoff patch already applied" ;;
                    *)               log_warning "Remember handoff patch skipped ($remember_result) — upstream shape changed, re-check $remember_hook" ;;
                esac
            fi
        fi

        log_success "Claude Code configuration deployed"
        log_info "  Config: CLAUDE.md, settings.json, agents/, hooks/, skills/"
        log_info "  Plugins: declared in settings.json enabledPlugins (7 retired ones tombstoned false)"
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
            codex_backup_path="$HOME/.codex.backup.$(date -u +%Y-%m-%d_%H-%M-%S)"
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

# ─── Alfred prefs repair (macOS only) ─────────────────────────────────────────
# Cloud-synced Alfred prefs (Dropbox) acquire quarantine xattrs that block
# workflow scripts ("posix_spawn: error 1"), lose script +x bits, and reset the
# per-machine summon hotkey. alfred-fix repairs all three; safe to re-run.

if [[ "$DEPLOY_ALFRED" == "true" ]] && is_macos; then
    if [[ -f "$HOME/Library/Application Support/Alfred/prefs.json" ]]; then
        log_info "Repairing Alfred preferences (de-quarantine, +x, hotkey)..."
        DOT_DIR="$DOT_DIR" "$DOT_DIR/custom_bins/alfred-fix" || \
            log_warning "alfred-fix reported an issue (see output above)"
    else
        log_info "Alfred not set up (no prefs.json) — skipping alfred-fix"
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

# ─── Storage Tiering Config (Linux) ──────────────────────────────────────────

if [[ "$DEPLOY_STORAGE" == "true" ]] && is_linux; then
    log_section "STORAGE TIERING CONFIG"

    # Records this machine's data volume in config/storage.conf, which
    # config/aliases/storage.sh reads on every interactive shell. Config only —
    # it never moves or deletes data. Idempotent: an existing config is left
    # alone, and a box with no attached volume is a silent success.
    if [[ -x "$DOT_DIR/custom_bins/storage-setup" ]]; then
        "$DOT_DIR/custom_bins/storage-setup" || log_warning "storage-setup failed"
    else
        log_warning "custom_bins/storage-setup not found or not executable"
    fi
fi

# ─── Pueue + Resource Slices (Linux) ─────────────────────────────────────────

if [[ "$DEPLOY_PUEUE" == "true" ]] && is_linux; then
    log_section "PUEUE + RESOURCE MANAGEMENT"

    if ! systemctl --user is-system-running &>/dev/null 2>&1; then
        log_warning "systemd --user not available — skipping resource management"
        log_info "  Try: loginctl enable-linger $(whoami)"
    else
        # Source resource config
        local resources_conf="$DOT_DIR/config/resources.conf"
        if [[ -f "$resources_conf" ]]; then
            source "$resources_conf"
        else
            log_warning "config/resources.conf not found — using defaults"
            EXPERIMENTS_CPU_QUOTA=200%; EXPERIMENTS_MEMORY_MAX=24G; EXPERIMENTS_MEMORY_HIGH=20G; EXPERIMENTS_PARALLEL=1
            AGENTS_CPU_QUOTA=200%; AGENTS_MEMORY_MAX=8G; AGENTS_MEMORY_HIGH=6G; AGENTS_PARALLEL=3
        fi

        # Deploy systemd user units
        local systemd_user_dir="$HOME/.config/systemd/user"
        mkdir -p "$systemd_user_dir"

        # Template slice files with values from resources.conf
        for slice in experiments agents; do
            local src="$DOT_DIR/config/systemd-user/${slice}.slice"
            local dst="$systemd_user_dir/${slice}.slice"
            if [[ -f "$src" ]]; then
                local cpu_var="${(U)slice}_CPU_QUOTA"
                local mem_max_var="${(U)slice}_MEMORY_MAX"
                local mem_high_var="${(U)slice}_MEMORY_HIGH"
                sed -e "s|CPUQuota=.*|CPUQuota=${(P)cpu_var}|" \
                    -e "s|MemoryMax=.*|MemoryMax=${(P)mem_max_var}|" \
                    -e "s|MemoryHigh=.*|MemoryHigh=${(P)mem_high_var}|" \
                    "$src" > "$dst"
                log_info "Deployed ${slice}.slice (CPU=${(P)cpu_var}, Mem=${(P)mem_max_var})"
            fi
        done

        # Deploy pueued.service: template absolute pueued path + XDG_RUNTIME_DIR so the
        # unit works regardless of the default PATH visible to systemd --user.
        local pueued_src="$DOT_DIR/config/systemd-user/pueued.service"
        if [[ -f "$pueued_src" ]]; then
            local pueued_bin
            pueued_bin=$(command -v pueued 2>/dev/null || echo "pueued")
            sed -e "s|ExecStart=pueued|ExecStart=${pueued_bin}|" \
                "$pueued_src" > "$systemd_user_dir/pueued.service"
            # Ensure XDG_RUNTIME_DIR is set (needed for the unix socket path)
            if ! grep -q "XDG_RUNTIME_DIR" "$systemd_user_dir/pueued.service"; then
                sed -i "s|\[Service\]|[Service]\nEnvironment=XDG_RUNTIME_DIR=%t|" \
                    "$systemd_user_dir/pueued.service"
            fi
        fi

        # Deploy remaining service/timer units verbatim.
        #
        # This list is enumerated, not globbed, so a unit added to
        # config/systemd-user/ is NOT installed until its name appears here.
        # openrouter-drift.{service,timer} were added in 2026-08 and never
        # listed, so the "monthly drift check" documented in the council
        # skill had never run on any box -- no unit, no timer, no state
        # directory. Adding a unit file is half the change; this is the other
        # half.
        for unit in reset-failed.service reset-failed.timer \
                    vault-sync-tripwire.service vault-sync-tripwire.timer \
                    openrouter-drift.service openrouter-drift.timer \
                    council-roster.service council-roster.timer \
                    romp-tailnet-proxy.service; do
            local unit_src="$DOT_DIR/config/systemd-user/$unit"
            # -f: installed units are copies, not symlinks into the repo, so a
            # redeploy must overwrite the stale one rather than silently keep it.
            [[ -f "$unit_src" ]] && cp -f "$unit_src" "$systemd_user_dir/$unit"
        done

        systemctl --user daemon-reload
        log_success "systemd user units deployed"

        # EX-9 vault sync tripwire. Enabled here rather than in the pueue branch
        # below: it has no pueue dependency, and gating it there would leave it
        # installed-but-unscheduled on any box without pueue -- a monitor that
        # reports success while never running is worse than no monitor.
        if [[ -f "$systemd_user_dir/vault-sync-tripwire.timer" ]]; then
            if systemctl --user enable --now vault-sync-tripwire.timer 2>/dev/null; then
                log_success "vault-sync tripwire timer enabled"
            else
                log_warning "could not enable vault-sync-tripwire.timer"
            fi
        fi

        # Model-roster timers. Both need no API key and no pueue: they read the
        # public OpenRouter catalogue and the public Epoch index, and write only
        # their own state directories. Enabled unconditionally for the same
        # reason as the tripwire above -- a check that is installed but never
        # scheduled reports nothing while looking healthy.
        for timer in openrouter-drift.timer council-roster.timer; do
            [[ -f "$systemd_user_dir/$timer" ]] || continue
            if systemctl --user enable --now "$timer" 2>/dev/null; then
                log_success "$timer enabled"
            else
                log_warning "could not enable $timer"
            fi
        done

        # Romp tailnet proxy: only where romp is actually installed. Enabling it
        # elsewhere leaves a service retrying a bind forever against a romp kernel
        # that will never answer -- a permanently-failing unit nobody asked for.
        if [[ -d "$HOME/romp" && -f "$systemd_user_dir/romp-tailnet-proxy.service" ]]; then
            if systemctl --user enable --now romp-tailnet-proxy.service 2>/dev/null; then
                log_success "romp tailnet proxy enabled"
            else
                log_warning "could not enable romp-tailnet-proxy.service"
            fi
        fi

        # Check cgroup delegation
        local uid; uid=$(id -u)
        local user_cgroup="/sys/fs/cgroup/user.slice/user-${uid}.slice"
        if [[ -f "$user_cgroup/cgroup.subtree_control" ]]; then
            local controls; controls=$(< "$user_cgroup/cgroup.subtree_control")
            if [[ "$controls" != *"memory"* ]] || [[ "$controls" != *"cpu"* ]]; then
                log_warning "cgroup delegation incomplete: $controls"
                log_info "Run once: sudo systemctl set-property user-${uid}.slice Delegate=yes && sudo systemctl daemon-reload"
            else
                log_success "cgroup delegation OK: $controls"
            fi
        fi

        # Deploy Pueue config and create groups
        if cmd_exists pueue; then
            local pueue_config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/pueue"
            mkdir -p "$pueue_config_dir"
            safe_symlink "$DOT_DIR/config/pueue.yml" "$pueue_config_dir/pueue.yml"

            # Enable and start pueued via systemd
            systemctl --user enable pueued.service 2>/dev/null
            local systemd_err
            systemd_err=$(systemctl --user start pueued.service 2>&1)
            if [[ $? -ne 0 ]]; then
                log_info "systemd start failed (${systemd_err}), falling back to direct pueued..."
                # Ensure XDG_RUNTIME_DIR is set for the unix socket path
                export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
                local pueued_err
                pueued_err=$(pueued --daemonize 2>&1)
                [[ -n "$pueued_err" ]] && log_info "pueued: $pueued_err"
            fi

            # Wait for pueued to be ready (group creation needs running daemon)
            log_info "Waiting for pueued..."
            local retries=0
            while ! pueue status &>/dev/null && (( retries < 10 )); do
                sleep 0.5
                retries=$((retries + 1))
            done

            if (( retries < 10 )); then
                pueue group add experiments 2>/dev/null
                pueue group add agents 2>/dev/null
                pueue parallel "$EXPERIMENTS_PARALLEL" --group experiments
                pueue parallel "$AGENTS_PARALLEL" --group agents
                log_success "Pueue groups: experiments(${EXPERIMENTS_PARALLEL}), agents(${AGENTS_PARALLEL})"
            else
                log_warning "pueued did not become reachable (pueue status still failing after 5s)"
                # Surface recent service log to help diagnose startup failures
                if cmd_exists journalctl; then
                    local svc_log
                    svc_log=$(journalctl --user -u pueued.service -n 10 --no-pager 2>/dev/null || true)
                    [[ -n "$svc_log" ]] && log_info "pueued journal:\n$svc_log"
                fi
                log_info "Pueue groups not configured — re-run deploy.sh --pueue after fixing the daemon"
            fi

            # Enable reset-failed timer (hourly stale unit cleanup)
            systemctl --user enable --now reset-failed.timer 2>/dev/null

            # Enable linger (services persist after logout)
            loginctl enable-linger "$(whoami)" 2>/dev/null
        else
            log_warning "pueue not installed — run: ./install.sh --pueue"
        fi
    fi
fi

# ─── Scheduled Tasks (parallel — independent launchd/cron jobs) ──────────────

# Queue a setup script, warning if it is missing. Every one of these is tracked
# in the repo, so an absent script means a partial checkout or an unmerged
# branch — skipping silently reads as a successful deploy that installed nothing.
queue_scheduled_job() {
    local job_id="$1" script="$2"
    if [[ -f "$script" ]]; then
        scheduled_jobs+=("$job_id|$script")
    else
        log_warning "Scheduled task '$job_id' skipped: $script not found"
    fi
}

{
    local scheduled_jobs=()

    if [[ "$DEPLOY_CLAUDE_CLEANUP" == "true" ]]; then
        queue_scheduled_job claude-cleanup "$DOT_DIR/scripts/cleanup/setup_claude_cleanup.sh"
        queue_scheduled_job tmpdir-cleanup "$DOT_DIR/scripts/cleanup/setup_claude_tmpdir_cleanup.sh"
        queue_scheduled_job cache-clean "$DOT_DIR/scripts/cleanup/setup_cache_clean.sh"
    fi

    if [[ "$DEPLOY_AI_UPDATE" == "true" ]]; then
        queue_scheduled_job ai-update "$DOT_DIR/scripts/cleanup/setup_ai_update.sh"
    fi

    if [[ "$DEPLOY_MCP_SYNC" == "true" ]]; then
        queue_scheduled_job mcp-sync "$DOT_DIR/scripts/cleanup/setup_mcp_sync.sh"
    fi

    if [[ "$DEPLOY_DOTFILES_SYNC" == "true" ]]; then
        queue_scheduled_job dotfiles-sync "$DOT_DIR/scripts/cleanup/setup_dotfiles_sync.sh"
    fi

    if [[ "$DEPLOY_USAGE_PING" == "true" ]]; then
        queue_scheduled_job usage-ping "$DOT_DIR/scripts/cleanup/setup_usage_ping.sh"
    fi

    if [[ "$DEPLOY_TMUX_RESUME" == "true" ]]; then
        queue_scheduled_job tmux-resume "$DOT_DIR/scripts/cleanup/setup_tmux_resume.sh"
    fi

    if [[ "$DEPLOY_BREW_UPDATE" == "true" ]]; then
        queue_scheduled_job brew-update "$DOT_DIR/scripts/cleanup/setup_brew_update.sh"
    fi

    if [[ "$DEPLOY_DEP_AUDIT" == "true" ]]; then
        queue_scheduled_job dep-audit "$DOT_DIR/scripts/security/setup_dep_audit.sh"
    fi

    if [[ "$DEPLOY_STALE_CLAIMS" == "true" ]]; then
        queue_scheduled_job stale-claims "$DOT_DIR/scripts/audit/setup_stale_claims.sh"
    fi

    if [[ "$DEPLOY_KEYBOARD" == "true" ]] && is_macos; then
        queue_scheduled_job keyboard-repeat "$DOT_DIR/scripts/cleanup/setup_keyboard_repeat.sh"
    fi

    if [[ "$DEPLOY_KILL_SKY_CUA" == "true" ]] && is_macos; then
        queue_scheduled_job kill-sky-cua "$DOT_DIR/scripts/cleanup/setup_kill_sky_cua.sh"
    fi

    if [[ "$DEPLOY_HIDE_IDLE_APPS" == "true" ]] && is_macos; then
        # Provenance, not the resolved boolean, decides whether this run may MINT
        # the escalation token. DEPLOY_HIDE_IDLE_APPS=true can come from a CLI
        # flag, a profile, or a config.local.sh line written long ago - and
        # config.local.sh is sourced before parse_args. A host that pinned
        # `DEPLOY_HIDE_IDLE_APPS=true` back in the hide-only era would otherwise
        # be handed close/quit consent by a plain `./deploy.sh --non-interactive`,
        # which is exactly the silent hide->quit upgrade the token exists to stop.
        # The setup script still re-writes an already-present token, so ordinary
        # redeploys of a consenting machine are unaffected.
        # Assigned on BOTH branches, never merely set on one. A sentinel that is
        # only ever written to true is not a gate: run_parallel passes our
        # environment down, so an inherited HIDE_IDLE_APPS_EXPLICIT_CONSENT=true -
        # left by an earlier opt-in deploy in the same shell, or exported by a
        # wrapper - would sail through an if-without-else and be read as fresh
        # consent. Deriving it unconditionally makes this invocation the only
        # thing that can decide.
        if (( ${EXPLICIT_OPT_INS[(Ie)HIDE_IDLE_APPS]} )); then
            export HIDE_IDLE_APPS_EXPLICIT_CONSENT=true
        else
            export HIDE_IDLE_APPS_EXPLICIT_CONSENT=false
        fi
        queue_scheduled_job hide-idle-apps "$DOT_DIR/scripts/cleanup/setup_hide_idle_apps.sh"
    elif is_macos && (( ${EXPLICIT_OPT_OUTS[(Ie)HIDE_IDLE_APPS]} )); then
        # This job used to default to on, and its plist points at the same
        # binary, so an upgrade that flips the default to off would otherwise
        # leave the old schedule running - now with close and quit rungs it
        # never had. Opting out has to actually unload it.
        #
        # Gated on an EXPLICIT --no-hide-idle-apps, not on the flag being false:
        # --only and --minimal set every other component false, so `--only vim`
        # would otherwise tear this job down despite --only promising to touch
        # nothing else. Refusing a component and not selecting it differ.
        #
        # That narrowness leaves a real gap, and it is deliberately NOT closed
        # here: a plain `./deploy.sh` on a machine from the default-on era takes
        # neither branch, so the legacy job stays loaded and runs today's binary.
        # Widening this condition is the one fix that cannot work - it is the
        # `--only vim` bug above. The gap is closed at the other end instead, by
        # an escalation token that only the install path writes: an inherited job
        # keeps hiding and can no longer close or quit. See ESCALATION_TOKEN in
        # custom_bins/hide-idle-apps.
        [[ -f "$DOT_DIR/scripts/cleanup/setup_hide_idle_apps.sh" ]] && \
            "$DOT_DIR/scripts/cleanup/setup_hide_idle_apps.sh" --uninstall >/dev/null 2>&1 || true
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

_vpn_sudo_ready() {
    # A bare `sudo -v` under `set -euo pipefail` aborts the whole deploy when
    # there is no TTY to answer the password prompt ("a terminal is required").
    # Proceed only with cached credentials, or a successful attended prompt.
    sudo -n true 2>/dev/null && return 0
    [[ -t 0 ]] && run_with_timeout "${DOTFILES_PROMPT_TIMEOUT:-60}" sudo -v && return 0
    return 1
}

if [[ "${DEPLOY_VPN:-false}" == "true" ]] && is_macos && ! _vpn_sudo_ready; then
    log_warning "Skipping VPN split tunnel daemon — sudo credentials unavailable (re-run attended or with cached sudo)"
elif [[ "${DEPLOY_VPN:-false}" == "true" ]] && is_macos; then
    log_section "INSTALLING VPN SPLIT TUNNEL DAEMON"

    VPN_PLIST_LABEL="com.dotfiles.tailscale-route-fix"
    VPN_PLIST_PATH="/Library/LaunchDaemons/${VPN_PLIST_LABEL}.plist"
    VPN_SCRIPT_PATH="/usr/local/bin/tailscale-route-fix"

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

if is_macos && [[ -f "$DOT_DIR/custom_bins/safari-web-apps-scan" ]]; then
    "$DOT_DIR/custom_bins/safari-web-apps-scan" || log_warning "Safari web app scan failed (non-critical)"
fi

# ─── File Type Associations (macOS only) ─────────────────────────────────────

if [[ "$DEPLOY_FILE_APPS" == "true" ]] && is_macos; then
    log_section "SETTING DEFAULT FILE ASSOCIATIONS"

    ASSOC_CONF="$DOT_DIR/config/macos_default_apps.conf"
    if [[ ! -f "$ASSOC_CONF" ]]; then
        log_warning "config/macos_default_apps.conf not found, skipping"
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
            log_success "Editor associations set to $EDITOR_BUNDLE_ID"

            if [[ -n "${TERMINAL_BUNDLE_ID:-}" ]] && [[ ${#TERMINAL_EXTENSIONS[@]} -gt 0 ]]; then
                "$tool_bin" "$TERMINAL_BUNDLE_ID" "${TERMINAL_EXTENSIONS[@]}"
                log_success "Terminal associations set to $TERMINAL_BUNDLE_ID"
            fi
        fi
    fi
fi

# ─── Bitwarden Secrets Manager CLI ───────────────────────────────────────────

if [[ "${DEPLOY_BWS:-false}" == "true" ]]; then
    log_section "INSTALLING BITWARDEN SECRETS MANAGER CLI"

    BWS_VERSION="2.0.0"
    BWS_INSTALL_DIR="${HOME}/.local/bin"
    BWS_INSTALLED_VERSION="$(bws --version 2>/dev/null | awk '{print $2}')"

    # ── Install/upgrade binary ──
    if [[ "$BWS_INSTALLED_VERSION" == "$BWS_VERSION" ]]; then
        log_success "bws already at ${BWS_VERSION}"
    else
        [[ -n "$BWS_INSTALLED_VERSION" ]] && log_info "Upgrading bws ${BWS_INSTALLED_VERSION} → ${BWS_VERSION}"
        mkdir -p "$BWS_INSTALL_DIR"

        case "$(uname -s)-$(uname -m)" in
            Darwin-arm64)  BWS_TARGET="bws-macos-universal-${BWS_VERSION}" ;;
            Darwin-x86_64) BWS_TARGET="bws-macos-universal-${BWS_VERSION}" ;;
            Linux-x86_64)  BWS_TARGET="bws-x86_64-unknown-linux-gnu-${BWS_VERSION}" ;;
            Linux-aarch64) BWS_TARGET="bws-aarch64-unknown-linux-gnu-${BWS_VERSION}" ;;
            *) log_warning "Unsupported platform for bws: $(uname -s)-$(uname -m)"; BWS_TARGET="" ;;
        esac

        if [[ -n "$BWS_TARGET" ]]; then
            BWS_URL="https://github.com/bitwarden/sdk-sm/releases/download/bws-v${BWS_VERSION}/${BWS_TARGET}.zip"
            BWS_TMP="$(mktemp -d)"
            trap 'rm -rf "$BWS_TMP"' EXIT
            log_info "Downloading bws ${BWS_VERSION} from GitHub releases..."
            if fetch "$BWS_URL" -o "${BWS_TMP}/bws.zip" && \
               unzip -qo "${BWS_TMP}/bws.zip" -d "${BWS_TMP}" && \
               install -m 755 "${BWS_TMP}/bws" "${BWS_INSTALL_DIR}/bws"; then
                log_success "bws installed to ${BWS_INSTALL_DIR}/bws: $(bws --version 2>/dev/null)"
            else
                log_warning "bws installation failed — try: cargo install bws"
            fi
            rm -rf "$BWS_TMP"
            trap - EXIT
        fi
    fi

    # ── Token setup hint ──
    BWS_TOKEN_FILE="${BWS_TOKEN_FILE:-$HOME/.config/bws/token}"
    if [[ -f "$BWS_TOKEN_FILE" ]]; then
        log_success "BWS token already configured at ${BWS_TOKEN_FILE}"
    else
        log_info "Run 'secrets init' to store your BWS access token"
    fi
fi

# ─── Obsidian-Headless Vault Sync ────────────────────────────────────────────
# Secrets (auth_token, encryptionKey/Salt) come from BWS, never from the repo.
# Pull-only is force-enforced ONLY for vaults with no completed sync pass yet
# (no "Fully synced" in sync.log) — this is the exact incident precondition
# (2026-06/07: bidirectional sync against an incomplete local copy misread
# "never downloaded" as "deleted" and propagated deletions upstream). Vaults
# that have already synced at least once are left alone, so a later manual
# promotion to bidirectional (ob sync-config --mode bidirectional) is never
# reverted by a subsequent deploy.sh run.

if [[ "${DEPLOY_OBSIDIAN_SYNC:-false}" == "true" ]]; then
    log_section "OBSIDIAN SYNC (obsidian-headless)"

    if ! cmd_exists ob; then
        log_info "obsidian-headless (ob) not installed — skipping"
    else
        OB_CONFIG_DIR="$HOME/.config/obsidian-headless"
        mkdir -p "$OB_CONFIG_DIR"
        chmod 700 "$OB_CONFIG_DIR"

        # ── auth_token (account-level secret, no trailing newline) ──
        OB_AUTH_TOKEN_FILE="$OB_CONFIG_DIR/auth_token"
        if OB_AUTH_TOKEN="$(dotfiles-secrets get-value OBSIDIAN_AUTH_TOKEN 2>/dev/null)"; then
            if [[ ! -f "$OB_AUTH_TOKEN_FILE" ]] || [[ "$(cat "$OB_AUTH_TOKEN_FILE" 2>/dev/null)" != "$OB_AUTH_TOKEN" ]]; then
                OB_AUTH_TMP="${OB_AUTH_TOKEN_FILE}.tmp.$$"
                printf '%s' "$OB_AUTH_TOKEN" > "$OB_AUTH_TMP"
                chmod 600 "$OB_AUTH_TMP"
                mv "$OB_AUTH_TMP" "$OB_AUTH_TOKEN_FILE"
                log_success "Wrote auth_token from BWS"
            else
                chmod 600 "$OB_AUTH_TOKEN_FILE"
                log_success "auth_token already up to date"
            fi
        elif [[ -f "$OB_AUTH_TOKEN_FILE" ]]; then
            log_info "auth_token present locally but not in BWS — back it up: dotfiles-secrets set OBSIDIAN_AUTH_TOKEN"
        else
            log_info "No auth_token (local or BWS) — run 'ob login', then 'dotfiles-secrets set OBSIDIAN_AUTH_TOKEN' to seed other machines"
        fi

        # ── Per-vault: inject encryption key/salt, enforce pull-only for never-synced vaults ──
        # NOTE: "never-synced" is detected by grepping sync.log for "Fully synced" — there's no
        # structured state API from `ob`. custom_bins/obsidian-sync-check independently greps the
        # same log for a different, current-state question ("safe to promote right now"), which is
        # deliberately NOT the same check (this one is a one-way ratchet: once synced, stay hands-off
        # forever; that one reflects transient in-progress/disconnected state). If `ob` ever changes
        # its log wording, both places need updating together.
        OB_SYNC_DIR="$OB_CONFIG_DIR/sync"
        if [[ -d "$OB_SYNC_DIR" ]] && ! cmd_exists jq; then
            log_warning "jq not found — skipping vault config injection/pull-only enforcement"
        elif [[ -d "$OB_SYNC_DIR" ]]; then
            # Encryption key/salt are account-level secrets shared by every vault — fetch once.
            OB_HAVE_ENC_SECRETS=false
            if OB_ENC_KEY="$(dotfiles-secrets get-value OBSIDIAN_ENCRYPTION_KEY 2>/dev/null)" \
                && OB_ENC_SALT="$(dotfiles-secrets get-value OBSIDIAN_ENCRYPTION_SALT 2>/dev/null)"; then
                OB_HAVE_ENC_SECRETS=true
            fi

            for OB_VAULT_CONF in "$OB_SYNC_DIR"/*/config.json; do
                [[ -f "$OB_VAULT_CONF" ]] || continue
                OB_VAULT_DIR="$(dirname "$OB_VAULT_CONF")"
                OB_VAULT_PATH="$(jq -r '.vaultPath // empty' "$OB_VAULT_CONF")"
                OB_VAULT_LOG="$OB_VAULT_DIR/sync.log"

                if [[ -z "$OB_VAULT_PATH" ]]; then
                    log_warning "Vault config at $OB_VAULT_CONF has no vaultPath — skipping"
                    continue
                fi

                if [[ "$OB_HAVE_ENC_SECRETS" == "true" ]]; then
                    OB_CURRENT_KEY="$(jq -r '.encryptionKey // empty' "$OB_VAULT_CONF")"
                    if [[ "$OB_CURRENT_KEY" != "$OB_ENC_KEY" ]]; then
                        OB_CONF_TMP="${OB_VAULT_CONF}.tmp.$$"
                        jq --arg k "$OB_ENC_KEY" --arg s "$OB_ENC_SALT" \
                            '.encryptionKey = $k | .encryptionSalt = $s' \
                            "$OB_VAULT_CONF" > "$OB_CONF_TMP"
                        chmod 600 "$OB_CONF_TMP"
                        mv "$OB_CONF_TMP" "$OB_VAULT_CONF"
                        log_success "Injected encryption key/salt for vault at $OB_VAULT_PATH"
                    else
                        chmod 600 "$OB_VAULT_CONF"
                    fi
                fi

                if ! grep -q "Fully synced" "$OB_VAULT_LOG" 2>/dev/null; then
                    if ob sync-config --path "$OB_VAULT_PATH" --mode pull-only >/dev/null 2>&1; then
                        log_success "Never-synced vault at $OB_VAULT_PATH forced to pull-only (promote manually once fully synced: ob sync-config --path \"$OB_VAULT_PATH\" --mode bidirectional)"
                    else
                        log_warning "Failed to enforce pull-only for never-synced vault at $OB_VAULT_PATH — check: ob sync-status --path \"$OB_VAULT_PATH\""
                    fi
                fi
            done
        fi

        cmd_exists obsidian-sync-check && log_info "Check promotion readiness anytime with: obsidian-sync-check"
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

# ssh-agent: sandboxed Claude Code sessions authenticate over the agent socket, so
# the key never has to be read from disk (~/.ssh/id_* stays deny-read). If nothing
# is loaded, every sandboxed `git push` falls back to the key file and fails.
if cmd_exists ssh-add; then
    ssh_add_status=0
    ssh-add -l >/dev/null 2>&1 || ssh_add_status=$?
    if [[ "$ssh_add_status" -eq 1 ]]; then
        echo "  ssh-agent has no keys loaded — run: ssh-add ~/.ssh/id_ed25519"
        echo "    (without this, git push from a sandboxed Claude Code session fails)"
    elif [[ "$ssh_add_status" -ne 0 ]]; then
        echo "  Cannot reach ssh-agent — run: eval \"\$(ssh-agent -s)\" && ssh-add ~/.ssh/id_ed25519"
        echo "    (without this, git push from a sandboxed Claude Code session fails)"
    fi
fi
