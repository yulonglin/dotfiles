#!/usr/bin/env zsh
# ═══════════════════════════════════════════════════════════════════════════════
# Shared Helper Functions
# ═══════════════════════════════════════════════════════════════════════════════
# Common utilities used by install.sh and deploy.sh
# Source this after config.sh
# ═══════════════════════════════════════════════════════════════════════════════

# Ensure config is loaded
if [[ -z "${PLATFORM:-}" ]]; then
    echo "Error: config.sh must be sourced before helpers.sh" >&2
    exit 1
fi

# ─── Logging ──────────────────────────────────────────────────────────────────

log_info()    { echo "  $*"; }
log_success() { echo "✓ $*"; }
log_warning() { echo "⚠️  $*"; }
log_error()   { echo "✗ $*" >&2; }
log_section() { echo ""; echo "───────── $* ─────────"; }

# ─── Interactive Component Menu ──────────────────────────────────────────────

# Show interactive toggle menu for component selection
# Usage: show_component_menu install|deploy
# Requires: gum (graceful fallback to defaults if unavailable)
show_component_menu() {
    local mode="$1"

    # Skip if non-interactive
    if [[ "${NON_INTERACTIVE:-false}" == "true" ]] || ! [[ -t 0 ]] || ! cmd_exists gum; then
        return 0
    fi

    # Define components with descriptions and current state
    # Format: "name|description|variable_value"
    typeset -a comp_defs
    if [[ "$mode" == "install" ]]; then
        comp_defs=(
            "core|Core packages, CLI tools, gh, SOPS/age, uv|$INSTALL_CORE"
            "zsh|ZSH + oh-my-zsh + powerlevel10k theme|$INSTALL_ZSH"
            "tmux|Terminal multiplexer|$INSTALL_TMUX"
            "ai-tools|Claude Code, Gemini CLI, Codex CLI, MCP servers|$INSTALL_AI_TOOLS"
            "extras|hyperfine, gitui, code2prompt|$INSTALL_EXTRAS"
            "cleanup|Auto-cleanup Downloads/Screenshots (macOS)|$INSTALL_CLEANUP"
            "experimental|ty type checker (alpha)|$INSTALL_EXPERIMENTAL"
        )
        if is_macos; then
            comp_defs+=(
                "macos-settings|Dock, Finder, keyboard system defaults|$INSTALL_MACOS_SETTINGS"
                "finicky|Browser routing (Safari/Chrome/Zoom)|$INSTALL_FINICKY"
            )
        fi
        if is_linux; then
            comp_defs+=(
                "docker|Docker engine + compose|$INSTALL_DOCKER"
                "create-user|Create non-root dev user|$INSTALL_CREATE_USER"
            )
        fi
    elif [[ "$mode" == "deploy" ]]; then
        comp_defs=(
            "shell|ZSH config, aliases, key bindings|$DEPLOY_SHELL"
            "tmux|tmux.conf + TPM plugins|$DEPLOY_TMUX"
            "git-config|gitconfig, global gitignore, ripgrep config|$DEPLOY_GIT_CONFIG"
            "vim|vimrc|$DEPLOY_VIM"
            "editor|VSCode/Cursor settings + extensions (merges)|$DEPLOY_EDITOR"
            "claude|Claude Code config symlink (~/.claude)|$DEPLOY_CLAUDE"
            "codex|Codex CLI config symlink (~/.codex)|$DEPLOY_CODEX"
            "ghostty|Ghostty terminal config (symlinked)|$DEPLOY_GHOSTTY"
            "htop|htop config with dynamic CPU meters|$DEPLOY_HTOP"
            "pdb|pdb++ debugger config (high-contrast)|$DEPLOY_PDB"
            "matplotlib|Style files: anthropic, deepmind, petri|$DEPLOY_MATPLOTLIB"
            "git-hooks|Global pre-commit secret detection|$DEPLOY_GIT_HOOKS"
            "secrets|Sync SSH/git identity via GitHub gist|$DEPLOY_SECRETS"
            "secrets-env|Decrypt SOPS-encrypted API keys (age)|$DEPLOY_SECRETS_ENV"
            "cleanup|Auto-cleanup Downloads/Screenshots (macOS)|$DEPLOY_CLEANUP"
            "claude-cleanup|Remove idle Claude sessions after 24h|$DEPLOY_CLAUDE_CLEANUP"
            "ai-update|Daily auto-update: Claude, Gemini, Codex|$DEPLOY_AI_UPDATE"
            "brew-update|Weekly package upgrade + cleanup|$DEPLOY_BREW_UPDATE"
            "claude-tools|Build claude-tools Rust binary|$DEPLOY_CLAUDE_TOOLS"
        )
        if is_macos; then
            comp_defs+=(
                "finicky|Browser routing config (symlinked)|$DEPLOY_FINICKY"
                "keyboard|Keyboard repeat rate enforcement at login|$DEPLOY_KEYBOARD"
                "bedtime|Bedtime timezone enforcement|$DEPLOY_BEDTIME"
                "text-replacements|Sync macOS + Alfred text replacements|${DEPLOY_TEXT_REPLACEMENTS:-false}"
                "mouseless|Keyboard-driven mouse control|$DEPLOY_MOUSELESS"
                "vpn|NordVPN + Tailscale split tunnel daemon|$DEPLOY_VPN"
            )
        fi
        comp_defs+=("serena|Serena MCP server config (symlinked)|$DEPLOY_SERENA")
    fi

    # Build display items (with descriptions) and selected list
    typeset -a items
    local selected_csv=""
    for def in "${comp_defs[@]}"; do
        local name="${def%%|*}"
        local rest="${def#*|}"
        local desc="${rest%%|*}"
        local value="${rest##*|}"
        items+=("${name} — ${desc}")
        if [[ "$value" == "true" ]]; then
            [[ -n "$selected_csv" ]] && selected_csv+=","
            selected_csv+="${name} — ${desc}"
        fi
    done

    # Calculate height: all items + 2 for header/padding, capped at terminal height - 4
    local menu_height=$(( ${#items[@]} + 2 ))
    local term_height
    term_height=$(tput lines 2>/dev/null || echo 40)
    (( menu_height > term_height - 4 )) && menu_height=$(( term_height - 4 ))

    # Show gum menu
    local result
    local gum_args=(choose --no-limit --ordered
        --height "$menu_height"
        --header "Select ${mode} components (space=toggle, enter=confirm):"
        --cursor-prefix "• " --selected-prefix "✓ " --unselected-prefix "• ")
    [[ -n "$selected_csv" ]] && gum_args+=(--selected "$selected_csv")

    result=$(gum "${gum_args[@]}" -- "${items[@]}") || return 0  # user cancelled (ctrl-c)

    # Disable all components in this mode, then re-enable selected
    for def in "${comp_defs[@]}"; do
        local name="${def%%|*}"
        local var_name="${(U)name//-/_}"
        if [[ "$mode" == "install" ]]; then
            typeset -g "INSTALL_${var_name}=false"
        else
            typeset -g "DEPLOY_${var_name}=false"
        fi
    done

    # Parse selected items: extract name before " — "
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local name="${line%% — *}"
        local var_name="${(U)name//-/_}"
        if [[ "$mode" == "install" ]]; then
            typeset -g "INSTALL_${var_name}=true"
        else
            typeset -g "DEPLOY_${var_name}=true"
        fi
    done <<< "$result"
}

# ─── Command Checking ─────────────────────────────────────────────────────────

# Check if command exists
cmd_exists() {
    command -v "$1" &>/dev/null
}

# Check if command is installed, print version if so
# Usage: is_installed <cmd> [version_flag]
# Returns 0 if installed, 1 if not
is_installed() {
    local cmd="$1"
    local version_flag="${2:---version}"

    if [[ "${FORCE_REINSTALL:-false}" == "true" ]]; then
        return 1
    fi

    if cmd_exists "$cmd"; then
        local version
        version=$("$cmd" $version_flag 2>/dev/null | head -1 || echo "")
        if [[ -n "$version" ]]; then
            log_info "$cmd already installed ($version)"
        else
            log_info "$cmd already installed"
        fi
        return 0
    fi
    return 1
}

# Check if brew cask is installed (macOS)
is_cask_installed() {
    local cask="$1"
    if [[ "${FORCE_REINSTALL:-false}" == "true" ]]; then
        return 1
    fi
    cmd_exists brew && brew list --cask "$cask" &>/dev/null
}

# ─── File Operations ──────────────────────────────────────────────────────────

# Backup a file with timestamp
# Usage: backup_file <path>
backup_file() {
    local filepath="$1"
    if [[ -e "$filepath" && ! -L "$filepath" ]]; then
        local backup="${filepath}.backup.$(date -u +%d-%m-%Y_%H-%M-%S)"
        mv "$filepath" "$backup"
        log_info "Backed up to $backup"
        echo "$backup"  # Return backup path
    fi
}

# Create symlink, backing up existing file if needed
# Usage: safe_symlink <source> <target>
safe_symlink() {
    local source="$1"
    local target="$2"

    if [[ ! -e "$source" ]]; then
        log_error "Source does not exist: $source"
        return 1
    fi

    # Remove existing symlink
    if [[ -L "$target" ]]; then
        rm "$target"
    # Backup existing file/directory
    elif [[ -e "$target" ]]; then
        backup_file "$target"
    fi

    # Create parent directory if needed
    mkdir -p "$(dirname "$target")"

    ln -sf "$source" "$target"
    log_success "Symlinked $source → $target"
}

# Get file modification time (cross-platform)
get_mtime() {
    local file="$1"
    if is_macos; then
        stat -f %m "$file" 2>/dev/null || echo "0"
    else
        stat -c %Y "$file" 2>/dev/null || echo "0"
    fi
}

# ─── Package Installation ─────────────────────────────────────────────────────

# Install package via Homebrew (macOS)
brew_install() {
    local pkg="$1"
    local cask="${2:-false}"

    if ! cmd_exists brew; then
        log_error "Homebrew not installed"
        return 1
    fi

    if [[ "$cask" == "true" ]]; then
        if ! is_cask_installed "$pkg"; then
            brew install --quiet --cask "$pkg" 2>/dev/null || log_warning "$pkg installation failed"
        fi
    else
        brew install --quiet "$pkg" 2>/dev/null || log_warning "$pkg installation failed"
    fi
}

# Check if apt package is installed
apt_is_installed() {
    dpkg -s "$1" &>/dev/null
}

# Install package via apt (Linux)
apt_install() {
    local pkg="$1"
    if apt_is_installed "$pkg"; then
        return 0
    fi
    sudo apt install -y "$pkg" 2>/dev/null || log_warning "$pkg installation via apt failed"
}

# Install package via mise (Linux)
mise_install() {
    local pkg="$1"
    if ! cmd_exists mise; then
        log_warning "mise not available for $pkg"
        return 1
    fi
    if mise where "$pkg" &>/dev/null; then
        return 0
    fi
    mise use -g "$pkg" || log_warning "$pkg installation via mise failed"
}

# Install multiple packages
# Usage: install_packages <manager> <pkg1> <pkg2> ...
# For apt: filters already-installed packages, installs remaining in one call
install_packages() {
    local manager="$1"
    shift

    if [[ "$manager" == "apt" ]]; then
        local missing=()
        for pkg in "$@"; do
            if ! apt_is_installed "$pkg"; then
                missing+=("$pkg")
            fi
        done
        if (( ${#missing[@]} == 0 )); then
            log_info "All packages already installed"
            return 0
        fi
        log_info "Installing ${#missing[@]} missing package(s): ${missing[*]}"
        sudo apt install -y "${missing[@]}" 2>/dev/null || log_warning "Some apt packages failed to install"
        return
    fi

    for pkg in "$@"; do
        case "$manager" in
            brew) brew_install "$pkg" ;;
            mise) mise_install "$pkg" ;;
        esac
    done
}

# ─── ZSH Setup ────────────────────────────────────────────────────────────────

# Set ZSH as default shell if possible
set_zsh_default() {
    [[ "$SHELL" == *"zsh"* ]] && return 0

    local zsh_path
    zsh_path=$(which zsh 2>/dev/null)

    if [[ -x "$zsh_path" ]] && sudo -n true 2>/dev/null; then
        log_info "Setting ZSH as default shell..."
        grep -qxF "$zsh_path" /etc/shells 2>/dev/null || \
            echo "$zsh_path" | sudo tee -a /etc/shells >/dev/null
        chsh -s "$zsh_path"
        log_success "Default shell changed to ZSH"
    fi
}

# Clone a ZSH plugin
clone_zsh_plugin() {
    local repo="$1"
    local name="${2:-$(basename "$repo" .git)}"
    local target="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/$name"

    if [[ -d "$target" ]]; then
        log_info "$name already installed"
        return 0
    fi

    git clone --quiet "$repo" "$target" 2>/dev/null || log_warning "$name clone failed"
}

# Install oh-my-zsh and plugins
install_ohmyzsh() {
    local zsh_dir="$HOME/.oh-my-zsh"
    local zsh_custom="$zsh_dir/custom"

    if [[ -d "$zsh_dir" && "${FORCE_REINSTALL:-false}" != "true" ]]; then
        log_info "oh-my-zsh already installed (use FORCE_REINSTALL=true to reinstall)"
        return 0
    fi

    log_info "Installing oh-my-zsh..."
    rm -rf "$zsh_dir"
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

    log_info "Installing powerlevel10k theme..."
    git clone --quiet https://github.com/romkatv/powerlevel10k.git \
        "${zsh_custom}/themes/powerlevel10k" 2>/dev/null || log_warning "powerlevel10k failed"

    log_info "Installing zsh plugins..."
    clone_zsh_plugin "https://github.com/zsh-users/zsh-syntax-highlighting.git"
    clone_zsh_plugin "https://github.com/zsh-users/zsh-autosuggestions"
    clone_zsh_plugin "https://github.com/zsh-users/zsh-completions"
    clone_zsh_plugin "https://github.com/zsh-users/zsh-history-substring-search"
    clone_zsh_plugin "https://github.com/jirutka/zsh-shift-select.git" "zsh-shift-select"

    log_info "Installing tmux theme pack..."
    git clone --quiet https://github.com/jimeh/tmux-themepack.git ~/.tmux-themepack 2>/dev/null || true

    log_success "oh-my-zsh installation complete"
}

# ─── GitHub CLI ───────────────────────────────────────────────────────────────

# Install and authenticate GitHub CLI
install_gh_cli() {
    if is_installed gh; then
        # Check authentication
        if gh auth status &>/dev/null; then
            log_info "gh already authenticated"
            return 0
        fi
    else
        log_info "Installing GitHub CLI..."
        if is_macos; then
            brew_install gh
        else
            apt_install gh || install_gh_from_release
        fi
    fi

    # Authenticate if not already
    if cmd_exists gh && ! gh auth status &>/dev/null; then
        echo ""
        echo "GitHub CLI needs authentication for secrets sync."
        echo "This will open a browser for OAuth login (no tokens needed)."
        echo ""
        gh auth login --web --git-protocol https || log_warning "gh auth failed - run 'gh auth login' manually"
    fi

    # Prefer SSH for git operations via gh
    if cmd_exists gh; then
        gh config set git_protocol ssh
    fi
}

# Fallback: Install gh from GitHub releases
install_gh_from_release() {
    log_info "Installing gh from GitHub releases..."
    local version arch

    version=$(curl -s https://api.github.com/repos/cli/cli/releases/latest | grep -o '"tag_name": "v[^"]*' | cut -d'v' -f2 || echo "2.62.0")

    case "$(uname -m)" in
        x86_64)  arch="amd64" ;;
        aarch64) arch="arm64" ;;
        *)       log_warning "Unsupported architecture for gh"; return 1 ;;
    esac

    mkdir -p "$HOME/.local/bin"
    curl -sSL "https://github.com/cli/cli/releases/download/v${version}/gh_${version}_linux_${arch}.tar.gz" -o /tmp/gh.tar.gz && \
    tar -xzf /tmp/gh.tar.gz -C /tmp && \
    mv "/tmp/gh_${version}_linux_${arch}/bin/gh" "$HOME/.local/bin/" && \
    rm -rf /tmp/gh.tar.gz "/tmp/gh_${version}_linux_${arch}"
}

# ─── Mise (Universal Version Manager) ─────────────────────────────────────────

install_mise() {
    if is_installed mise; then
        return 0
    fi

    log_info "Installing mise..."
    mkdir -p "$HOME/.local/bin"
    curl https://mise.run | sh
    export PATH="$HOME/.local/bin:$PATH"

    if cmd_exists mise; then
        eval "$(mise activate bash)"
        return 0
    fi

    log_warning "mise installation failed"
    return 1
}

# ─── User Management (Linux) ──────────────────────────────────────────────────

# Create non-root development user
create_dev_user() {
    if [[ $EUID -ne 0 ]]; then
        log_info "Skipping --create-user: not running as root"
        return 0
    fi

    local username="${DEV_USERNAME:-${DOTFILES_USERNAME:-$GIT_USER_NAME}}"
    username="${username:-yulong}"

    if id "$username" &>/dev/null; then
        log_info "User $username already exists"
        return 0
    fi

    log_info "Creating user: $username"
    local shell
    shell=$(command -v zsh || command -v bash)
    useradd -m -s "$shell" "$username"

    # Add to sudo group
    if getent group sudo &>/dev/null; then
        usermod -aG sudo "$username"
    elif getent group wheel &>/dev/null; then
        usermod -aG wheel "$username"
    fi

    # Enable passwordless sudo
    echo "$username ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$username"

    # Copy SSH keys if present
    if [[ -d /root/.ssh ]]; then
        cp -r /root/.ssh "/home/$username/"
        chown -R "$username:$username" "/home/$username/.ssh"
    fi

    log_success "User $username created. Switch with: su - $username"
}

# ─── Docker Installation (Linux) ─────────────────────────────────────────────

install_docker() {
    local docker_just_installed=false

    if ! is_installed docker; then
        docker_just_installed=true
        log_section "INSTALLING DOCKER 🐳"

        # Install prerequisites
        apt-get install -y ca-certificates curl gnupg 2>/dev/null || {
            log_warning "Could not install Docker prerequisites"
            return 1
        }

        # Add Docker's official GPG key
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null || {
            # Try Debian if Ubuntu fails
            curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null || {
                log_warning "Could not add Docker GPG key"
                return 1
            }
        }
        chmod a+r /etc/apt/keyrings/docker.gpg

        # Detect distro and add repository
        local distro version_codename
        if [[ -f /etc/os-release ]]; then
            # shellcheck source=/dev/null
            source /etc/os-release
            distro="${ID:-ubuntu}"
            version_codename="${VERSION_CODENAME:-$(lsb_release -cs 2>/dev/null || echo 'jammy')}"
        else
            distro="ubuntu"
            version_codename="jammy"
        fi

        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${distro} ${version_codename} stable" | \
            tee /etc/apt/sources.list.d/docker.list > /dev/null

        # Install Docker
        apt-get update -y 2>/dev/null
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>/dev/null || {
            log_warning "Docker installation failed"
            return 1
        }

        log_success "Docker installed successfully"
    fi

    # Add current user to docker group (avoids needing sudo)
    # This runs even if Docker was already installed, in case user wasn't added to group
    local current_user="${SUDO_USER:-$USER}"
    if [[ -n "$current_user" ]] && [[ "$current_user" != "root" ]]; then
        if ! groups "$current_user" 2>/dev/null | grep -q '\bdocker\b'; then
            usermod -aG docker "$current_user" 2>/dev/null || true
            log_success "Added $current_user to docker group"
            echo ""
            echo "  ⚠️  IMPORTANT: To use Docker without sudo, either:"
            echo "      • Log out and back in, OR"
            echo "      • Run: newgrp docker"
            echo ""
        fi
    fi

    if [[ "$docker_just_installed" == "true" ]]; then
        echo "  Start Docker daemon: sudo systemctl start docker"
        echo "  Verify installation:  docker run hello-world"
        echo ""
    fi
}

# ─── Secrets Sync ─────────────────────────────────────────────────────────────

# Ensure local public key is in authorized_keys (auto-add for convenience)
ensure_local_key_in_authorized_keys() {
    local auth_keys="$HOME/.ssh/authorized_keys"
    local pub_key=""
    local pub_key_file=""

    # Find first available public key
    for key_type in ed25519 ecdsa rsa; do
        if [[ -f "$HOME/.ssh/id_${key_type}.pub" ]]; then
            pub_key_file="$HOME/.ssh/id_${key_type}.pub"
            pub_key=$(cat "$pub_key_file")
            break
        fi
    done

    if [[ -z "$pub_key" ]]; then
        log_info "No local public key found - skipping auto-add"
        return 0
    fi

    # Extract just the key part (without comment) for comparison
    local key_data
    key_data=$(echo "$pub_key" | awk '{print $1" "$2}')

    # Create authorized_keys if missing (avoid touch to preserve mtime for sync)
    mkdir -p "$HOME/.ssh"
    if [[ ! -f "$auth_keys" ]]; then
        touch "$auth_keys"
        chmod 600 "$auth_keys"
    fi

    # Check if key already present
    if grep -qF "$key_data" "$auth_keys" 2>/dev/null; then
        return 0
    fi

    # Add key with hostname comment
    local hostname
    hostname=$(hostname -s 2>/dev/null || echo "unknown")
    local key_with_comment="${key_data} # ${hostname}"

    echo "$key_with_comment" >> "$auth_keys"
    log_info "  + Added local key ($hostname) to authorized_keys"
}

# Sync secrets bidirectionally with GitHub gist
# Bidirectional sync with GitHub gist (SSH config, authorized_keys, git identity)
# WARNING: Secret gists are unlisted, not encrypted — anyone with the URL can read them.
# Do NOT add secrets (API keys, private keys, tokens) to this sync.
sync_gist() {
    local gist_id="${GIST_SYNC_ID:-3cc239f160a2fe8c9e6a14829d85a371}"

    if ! gh auth status &>/dev/null 2>&1; then
        log_warning "gh not authenticated - run 'gh auth login' to sync gist"
        return 1
    fi

    local gist_data
    gist_data=$(gh api "/gists/$gist_id" 2>/dev/null) || {
        log_warning "Failed to fetch gist - check network or gist ID"
        return 1
    }

    # Get gist updated_at timestamp
    # Note: Use printf or here-string, NOT echo - echo interprets \n in JSON content
    local gist_updated_at
    gist_updated_at=$(python3 -c "
import sys, json
from datetime import datetime
data = json.load(sys.stdin)
ts = datetime.fromisoformat(data['updated_at'].replace('Z', '+00:00'))
print(int(ts.timestamp()))
" <<< "$gist_data" 2>/dev/null)

    # Helper functions
    get_gist_file() {
        python3 -c "
import sys, json
data = json.load(sys.stdin)
print(data['files'].get('$1', {}).get('content', ''))
" <<< "$gist_data" 2>/dev/null
    }

    gist_has_file() {
        python3 -c "
import sys, json
data = json.load(sys.stdin)
print('yes' if '$1' in data['files'] else 'no')
" <<< "$gist_data" 2>/dev/null
    }

    local changes_made=false

    # Ensure local key is in authorized_keys before syncing
    ensure_local_key_in_authorized_keys

    # Sync SSH config
    log_info "Syncing SSH config..."
    sync_file "$HOME/.ssh/config" "config" "$gist_id" "$gist_updated_at" && changes_made=true

    # Sync authorized_keys
    log_info "Syncing authorized_keys..."
    sync_file "$HOME/.ssh/authorized_keys" "authorized_keys" "$gist_id" "$gist_updated_at" && changes_made=true

    # Sync user.conf (git identity)
    log_info "Syncing git identity..."
    sync_file "$DOT_DIR/config/user.conf" "user.conf" "$gist_id" "$gist_updated_at" && changes_made=true

    if [[ "$changes_made" == "true" ]]; then
        log_success "Gist sync complete"
    else
        log_success "Gist already in sync"
    fi
}

# Sync a single file with gist
# Usage: sync_file <local_path> <gist_filename> <gist_id> <gist_updated_at>
sync_file() {
    local local_path="$1"
    local gist_filename="$2"
    local gist_id="$3"
    local gist_updated_at="$4"

    local gist_exists
    gist_exists=$(gist_has_file "$gist_filename")

    if [[ ! -f "$local_path" ]]; then
        if [[ "$gist_exists" == "yes" ]]; then
            mkdir -p "$(dirname "$local_path")"
            get_gist_file "$gist_filename" > "$local_path"
            [[ "$gist_filename" == "config" || "$gist_filename" == "authorized_keys" ]] && chmod 600 "$local_path"
            # Preserve mtime to match gist's updated_at
            if is_macos; then
                touch -t "$(date -r "$gist_updated_at" +%Y%m%d%H%M.%S)" "$local_path"
            else
                touch -d "@$gist_updated_at" "$local_path"
            fi
            log_info "  ↓ Pulled $gist_filename from gist (local was missing)"
            return 0
        fi
        return 1
    fi

    if [[ "$gist_exists" == "no" ]]; then
        gh gist edit "$gist_id" --add "$local_path" --filename "$gist_filename" &>/dev/null
        log_info "  ↑ Pushed $gist_filename to gist (gist was missing)"
        return 0
    fi

    # Both exist - compare
    local local_mtime gist_content local_content
    local_mtime=$(get_mtime "$local_path")
    gist_content=$(get_gist_file "$gist_filename")
    local_content=$(cat "$local_path")

    if [[ "$local_content" != "$gist_content" ]]; then
        if [[ "$local_mtime" -gt "$gist_updated_at" ]]; then
            gh gist edit "$gist_id" --add "$local_path" --filename "$gist_filename" &>/dev/null
            log_info "  ↑ Pushed $gist_filename to gist (local newer)"
        else
            echo "$gist_content" > "$local_path"
            [[ "$gist_filename" == "config" || "$gist_filename" == "authorized_keys" ]] && chmod 600 "$local_path"
            # Preserve mtime to match gist's updated_at (prevents false "local newer" on next sync)
            if is_macos; then
                touch -t "$(date -r "$gist_updated_at" +%Y%m%d%H%M.%S)" "$local_path"
            else
                touch -d "@$gist_updated_at" "$local_path"
            fi
            log_info "  ↓ Pulled $gist_filename from gist (gist newer)"
        fi
        return 0
    fi

    log_info "  ✓ $gist_filename in sync"
    return 1
}

# ─── Git Configuration ────────────────────────────────────────────────────────

# Deploy git configuration with conflict resolution
deploy_git_config() {
    log_info "Deploying git configuration..."

    # Deploy global gitignore (composed from universal + research patterns)
    # Git sees both; search tools (rg, fd, Claude Code) see only universal.
    if [[ -f "$DOT_DIR/config/ignore_global" ]] && [[ -f "$DOT_DIR/config/ignore_research" ]]; then
        cat "$DOT_DIR/config/ignore_global" "$DOT_DIR/config/ignore_research" > "$HOME/.gitignore_global"
        log_success "Deployed ~/.gitignore_global (universal + research)"
    elif [[ -f "$DOT_DIR/config/ignore_global" ]]; then
        cp "$DOT_DIR/config/ignore_global" "$HOME/.gitignore_global"
        log_success "Deployed ~/.gitignore_global (universal only)"
    fi

    # Deploy search tool ignore files (universal only, symlinked for auto-update)
    if [[ -f "$DOT_DIR/config/ignore_global" ]]; then
        # ripgrep + Claude Code: symlink universal ignore
        ln -sf "$DOT_DIR/config/ignore_global" "$HOME/.ignore_global"
        log_success "Symlinked ~/.ignore_global"

        # fd: symlink to same file
        local fd_config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/fd"
        mkdir -p "$fd_config_dir"
        ln -sf "$DOT_DIR/config/ignore_global" "$fd_config_dir/ignore"
        log_success "Symlinked $fd_config_dir/ignore"

        # ripgrep config: skip git's global ignore, use universal-only ignore file
        if cmd_exists rg; then
            local rg_config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/ripgrep"
            mkdir -p "$rg_config_dir"
            printf '%s\n' "--no-ignore-global" "--ignore-file" "$HOME/.ignore_global" > "$rg_config_dir/config"
            log_success "Deployed $rg_config_dir/config"
        fi
    fi

    # Load user config if exists
    if [[ -f "$DOT_DIR/config/user.conf" ]]; then
        source "$DOT_DIR/config/user.conf"
        GIT_USER_EMAIL="${GIT_USER_EMAIL:-$GIT_USER_EMAIL}"
        GIT_USER_NAME="${GIT_USER_NAME:-$GIT_USER_NAME}"
        log_info "Using git identity from config/user.conf"
    fi

    # Git settings to apply
    typeset -A git_settings=(
        ["user.email"]="$GIT_USER_EMAIL"
        ["user.name"]="$GIT_USER_NAME"
        ["push.autoSetupRemote"]="true"
        ["push.default"]="simple"
        ["init.defaultBranch"]="main"
        ["core.excludesfile"]="~/.gitignore_global"
        ["merge.conflictstyle"]="zdiff3"
        ["rerere.enabled"]="true"
        ["rerere.autoUpdate"]="true"
        ["pull.rebase"]="true"
        ["rebase.autoStash"]="true"
        ["rebase.autoSquash"]="true"
        ["fetch.prune"]="true"
        ["fetch.pruneTags"]="true"
        ["alias.lg"]="log --color --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit"
    )

    # Check for conflicts
    local conflicts=()
    for key in "${(k)git_settings[@]}"; do
        local existing=$(git config --global "$key" 2>/dev/null || echo "")
        local new="${git_settings[$key]}"
        if [[ -n "$existing" && "$existing" != "$new" ]]; then
            conflicts+=("$key|$existing|$new")
        fi
    done

    # Handle conflicts
    if [[ ${#conflicts[@]} -gt 0 ]]; then
        echo ""
        log_warning "Git config conflicts detected:"
        echo ""
        for conflict in "${conflicts[@]}"; do
            IFS='|' read -r key existing new <<< "$conflict"
            echo "  [$key]"
            echo "    Current:  $existing"
            echo "    New:      $new"
            echo ""
        done

        echo "Options:"
        echo "  [K]eep all existing values"
        echo "  [U]se all new values from dotfiles"
        echo "  [S]kip git config deployment"
        echo ""
        read -p "Choose [K/U/S]: " -n 1 -r choice
        echo ""

        case "$choice" in
            [Kk])
                log_info "Keeping existing values, applying non-conflicting..."
                apply_nonconflicting_git_settings "${conflicts[@]}"
                ;;
            [Uu])
                log_info "Using all new values..."
                apply_all_git_settings
                ;;
            *)
                log_info "Skipping git config deployment"
                return 0
                ;;
        esac
    else
        log_info "No conflicts, applying all settings..."
        apply_all_git_settings
    fi

    log_success "Git configuration deployed"
}

apply_all_git_settings() {
    git config --global user.email "$GIT_USER_EMAIL"
    git config --global user.name "$GIT_USER_NAME"
    git config --global push.autoSetupRemote true
    git config --global push.default simple
    git config --global init.defaultBranch main
    git config --global core.excludesfile "~/.gitignore_global"
    git config --global alias.lg "log --color --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit"
}

apply_nonconflicting_git_settings() {
    local conflicts=("$@")
    local conflict_keys=()

    for conflict in "${conflicts[@]}"; do
        IFS='|' read -r key _ _ <<< "$conflict"
        conflict_keys+=("$key")
    done

    # Apply settings not in conflict list
    for key in user.email user.name push.autoSetupRemote push.default init.defaultBranch core.excludesfile alias.lg; do
        local is_conflict=false
        for ck in "${conflict_keys[@]}"; do
            [[ "$key" == "$ck" ]] && is_conflict=true && break
        done
        if ! $is_conflict; then
            local existing
            existing=$(git config --global "$key" 2>/dev/null || echo "")
            [[ -z "$existing" ]] && git config --global "$key" "${git_settings[$key]}"
        fi
    done
}

# ─── Editor Settings ──────────────────────────────────────────────────────────

# Deploy VSCode/Cursor settings
deploy_editor_settings() {
    local settings_file="$DOT_DIR/config/vscode_settings.json"

    if [[ ! -f "$settings_file" ]]; then
        log_warning "VSCode settings not found at $settings_file"
        return 1
    fi

    # Determine paths
    local vscode_dir cursor_dir
    if is_macos; then
        vscode_dir="$HOME/Library/Application Support/Code/User"
        cursor_dir="$HOME/Library/Application Support/Cursor/User"
    else
        vscode_dir="$HOME/.config/Code/User"
        cursor_dir="$HOME/.config/Cursor/User"
    fi

    local deployed=false

    # Deploy to VSCode
    if [[ -d "$vscode_dir" ]]; then
        merge_json_settings "$settings_file" "$vscode_dir/settings.json" "VSCode"
        install_editor_extensions "code" "$DOT_DIR/config/vscode_extensions.txt"
        deployed=true
    fi

    # Deploy to Cursor
    if [[ -d "$cursor_dir" ]]; then
        merge_json_settings "$settings_file" "$cursor_dir/settings.json" "Cursor"
        install_editor_extensions "cursor" "$DOT_DIR/config/vscode_extensions.txt"
        deployed=true
    fi

    if ! $deployed; then
        log_warning "Neither VSCode nor Cursor found"
        return 1
    fi
}

# Merge JSON settings (existing takes precedence)
merge_json_settings() {
    local source="$1"
    local target="$2"
    local name="$3"

    if [[ ! -f "$target" ]]; then
        cp "$source" "$target"
        log_success "Deployed $name settings (new)"
        return 0
    fi

    python3 - "$source" "$target" <<'MERGE'
import json, sys
with open(sys.argv[1]) as f: dotfiles = json.load(f)
with open(sys.argv[2]) as f: existing = json.load(f)
# Deep merge: scalars/objects → existing wins; arrays → dotfiles wins (dotfiles is source of truth)
merged = {}
all_keys = set(dotfiles) | set(existing)
for k in all_keys:
    if k not in dotfiles:
        merged[k] = existing[k]
    elif k not in existing:
        merged[k] = dotfiles[k]
    elif isinstance(dotfiles[k], list):
        merged[k] = dotfiles[k]  # dotfiles wins for arrays
    else:
        merged[k] = existing[k]  # existing wins for scalars/objects
with open(sys.argv[2], 'w') as f: json.dump(merged, f, indent=4); f.write('\n')
MERGE

    log_success "Merged $name settings (existing preserved, arrays from dotfiles)"
}

# Install editor extensions
install_editor_extensions() {
    local cli="$1"
    local extensions_file="$2"

    if ! cmd_exists "$cli"; then
        log_info "$cli CLI not found, skipping extensions"
        return 0
    fi

    if [[ ! -f "$extensions_file" ]]; then
        return 0
    fi

    log_info "Installing extensions..."
    local count=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        local ext_id
        ext_id=$(echo "$line" | xargs)
        $cli --install-extension "$ext_id" --force &>/dev/null && ((count++))
    done < "$extensions_file"

    [[ $count -gt 0 ]] && log_success "Installed $count extension(s)"
}

# ─── CLI Argument Parsing ─────────────────────────────────────────────────────

# Parse CLI arguments and override config
# Usage: parse_args "$@"
parse_args() {
    # --only accumulator (deferred two-pass parsing)
    typeset -a _only_components
    _only_components=()
    local _only_mode=false

    while (( $# )); do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            --profile=*)
                if [[ "$_only_mode" == true ]]; then
                    echo "Error: --only cannot be mixed with profile or component flags" >&2
                    exit 1
                fi
                apply_profile "${1#*=}"
                ;;
            --force|--force-reinstall)
                FORCE_REINSTALL=true
                ;;
            --append)
                DEPLOY_APPEND=true
                ;;
            --ascii=*)
                DEPLOY_ASCII_FILE="${1#*=}"
                ;;
            --aliases=*)
                IFS=',' read -r -a DEPLOY_ALIASES <<< "${1#*=}"
                ;;
            --minimal)
                if [[ "$_only_mode" == true ]]; then
                    echo "Error: --only cannot be mixed with profile or component flags" >&2
                    exit 1
                fi
                apply_profile "minimal"
                ;;
            --server)
                if [[ "$_only_mode" == true ]]; then
                    echo "Error: --only cannot be mixed with profile or component flags" >&2
                    exit 1
                fi
                apply_profile "server"
                ;;
            --personal)
                if [[ "$_only_mode" == true ]]; then
                    echo "Error: --only cannot be mixed with profile or component flags" >&2
                    exit 1
                fi
                apply_profile "personal"
                ;;
            --default)
                if [[ "$_only_mode" == true ]]; then
                    echo "Error: --only cannot be mixed with profile or component flags" >&2
                    exit 1
                fi
                apply_profile "server"
                ;;
            --no-defaults)
                if [[ "$_only_mode" == true ]]; then
                    echo "Error: --only cannot be mixed with profile or component flags" >&2
                    exit 1
                fi
                apply_profile "minimal"
                ;;
            --only=*)
                _only_mode=true
                IFS=',' read -rA _parsed_comps <<< "${1#--only=}"
                _only_components+=("${_parsed_comps[@]}")
                ;;
            --only)
                _only_mode=true
                shift
                while [[ $# -gt 0 && "${1:0:1}" != "-" ]]; do
                    IFS=',' read -rA _parsed_comps <<< "$1"
                    _only_components+=("${_parsed_comps[@]}")
                    shift
                done
                continue  # skip outer shift — args already consumed
                ;;
            --non-interactive)
                NON_INTERACTIVE=true
                ;;
            --no-*)
                if [[ "$_only_mode" == true ]]; then
                    echo "Error: --only cannot be mixed with profile or component flags" >&2
                    exit 1
                fi
                # Disable a component: --no-zsh, --no-claude, etc.
                local component="${1#--no-}"
                component="$(printf '%s' "$component" | tr '[:lower:]' '[:upper:]')"
                component="${component//-/_}"  # dashes to underscores
                typeset -g "INSTALL_${component}=false"
                typeset -g "DEPLOY_${component}=false"
                ;;
            --*)
                if [[ "$_only_mode" == true ]]; then
                    echo "Error: --only cannot be mixed with profile or component flags" >&2
                    exit 1
                fi
                # Enable a component: --zsh, --claude, etc.
                local component="${1#--}"
                component="$(printf '%s' "$component" | tr '[:lower:]' '[:upper:]')"
                component="${component//-/_}"
                typeset -g "INSTALL_${component}=true"
                typeset -g "DEPLOY_${component}=true"
                ;;
            *)
                log_warning "Unknown argument: $1"
                ;;
        esac
        shift
    done

    # Deferred --only apply: validate components, then set minimal + enable selected
    if [[ "$_only_mode" == true ]]; then
        local _known_components=(core vim editor claude codex ghostty htop pdb matplotlib
            git_hooks secrets secrets_env cleanup claude_cleanup ai_update brew_update keyboard
            bedtime serena mouseless text_replacements vpn finicky claude_tools macos_settings
            zsh tmux ai_tools docker extras experimental create_user
            shell git_config)

        for _comp in "${_only_components[@]}"; do
            _comp="${_comp// /}"
            [[ -z "$_comp" ]] && continue
            local _comp_lower="${_comp:l}"
            _comp_lower="${_comp_lower//-/_}"
            if (( ! ${_known_components[(Ie)$_comp_lower]} )); then
                echo "Error: Unknown component '${_comp}'. Valid: ${(j:, :)_known_components}" >&2
                exit 1
            fi
        done

        apply_profile "minimal"
        for _comp in "${_only_components[@]}"; do
            _comp="${_comp// /}"
            [[ -z "$_comp" ]] && continue
            local _comp_upper="${(U)_comp//-/_}"
            typeset -g "INSTALL_${_comp_upper}=true"
            typeset -g "DEPLOY_${_comp_upper}=true"
        done
    fi
}
