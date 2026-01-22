#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# Shared Helper Functions
# ═══════════════════════════════════════════════════════════════════════════════
# Common utilities used by install.sh and deploy.sh
# Source this after config.sh
# ═══════════════════════════════════════════════════════════════════════════════

# Ensure config is loaded
if [[ -z "$PLATFORM" ]]; then
    echo "Error: config.sh must be sourced before helpers.sh" >&2
    exit 1
fi

# ─── Logging ──────────────────────────────────────────────────────────────────

log_info()    { echo "  $*"; }
log_success() { echo "✓ $*"; }
log_warning() { echo "⚠️  $*"; }
log_error()   { echo "✗ $*" >&2; }
log_section() { echo ""; echo "───────── $* ─────────"; }

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
    local path="$1"
    if [[ -e "$path" && ! -L "$path" ]]; then
        local backup="${path}.backup.$(date +%Y%m%d_%H%M%S)"
        mv "$path" "$backup"
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

# Install package via apt (Linux)
apt_install() {
    local pkg="$1"
    apt install -y "$pkg" 2>/dev/null || log_warning "$pkg installation via apt failed"
}

# Install package via mise (Linux)
mise_install() {
    local pkg="$1"
    if cmd_exists mise; then
        mise use -g "$pkg" 2>/dev/null || log_warning "$pkg installation via mise failed"
    else
        log_warning "mise not available for $pkg"
        return 1
    fi
}

# Install multiple packages
# Usage: install_packages <manager> <pkg1> <pkg2> ...
install_packages() {
    local manager="$1"
    shift

    for pkg in "$@"; do
        case "$manager" in
            brew) brew_install "$pkg" ;;
            apt)  apt_install "$pkg" ;;
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

    local username="${DEV_USERNAME:-$GIT_USER_NAME}"
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

# ─── Secrets Sync ─────────────────────────────────────────────────────────────

# Sync secrets bidirectionally with GitHub gist
sync_secrets() {
    local gist_id="${SECRETS_GIST_ID:-3cc239f160a2fe8c9e6a14829d85a371}"

    if ! gh auth status &>/dev/null 2>&1; then
        log_warning "gh not authenticated - run 'gh auth login' to sync secrets"
        return 1
    fi

    local gist_data
    gist_data=$(gh api "/gists/$gist_id" 2>/dev/null) || {
        log_warning "Failed to fetch gist - check network or gist ID"
        return 1
    }

    # Get gist updated_at timestamp
    local gist_updated_at
    gist_updated_at=$(echo "$gist_data" | python3 -c "
import sys, json
from datetime import datetime
data = json.load(sys.stdin)
ts = datetime.fromisoformat(data['updated_at'].replace('Z', '+00:00'))
print(int(ts.timestamp()))
" 2>/dev/null)

    # Helper functions
    get_gist_file() {
        echo "$gist_data" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(data['files'].get('$1', {}).get('content', ''))
" 2>/dev/null
    }

    gist_has_file() {
        echo "$gist_data" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print('yes' if '$1' in data['files'] else 'no')
" 2>/dev/null
    }

    local changes_made=false

    # Sync SSH config
    log_info "Syncing SSH config..."
    sync_file "$HOME/.ssh/config" "config" "$gist_id" "$gist_updated_at" && changes_made=true

    # Sync user.conf (git identity)
    log_info "Syncing git identity..."
    sync_file "$DOT_DIR/config/user.conf" "user.conf" "$gist_id" "$gist_updated_at" && changes_made=true

    if [[ "$changes_made" == "true" ]]; then
        log_success "Secrets synced with gist"
    else
        log_success "All secrets already in sync"
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
            [[ "$gist_filename" == "config" ]] && chmod 600 "$local_path"
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
            [[ "$gist_filename" == "config" ]] && chmod 600 "$local_path"
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

    # Deploy global gitignore
    if [[ -f "$DOT_DIR/config/gitignore_global" ]]; then
        cp "$DOT_DIR/config/gitignore_global" "$HOME/.gitignore_global"
        log_success "Deployed ~/.gitignore_global"
    fi

    # Deploy fd ignore
    if [[ -f "$DOT_DIR/config/ignore_global" ]]; then
        mkdir -p "$HOME/.config/fd"
        cp "$DOT_DIR/config/ignore_global" "$HOME/.config/fd/ignore"
        log_success "Deployed ~/.config/fd/ignore"
    fi

    # Load user config if exists
    if [[ -f "$DOT_DIR/config/user.conf" ]]; then
        source "$DOT_DIR/config/user.conf"
        GIT_USER_EMAIL="${GIT_USER_EMAIL:-$GIT_USER_EMAIL}"
        GIT_USER_NAME="${GIT_USER_NAME:-$GIT_USER_NAME}"
        log_info "Using git identity from config/user.conf"
    fi

    # Git settings to apply
    declare -A git_settings=(
        ["user.email"]="$GIT_USER_EMAIL"
        ["user.name"]="$GIT_USER_NAME"
        ["push.autoSetupRemote"]="true"
        ["push.default"]="simple"
        ["init.defaultBranch"]="main"
        ["core.excludesfile"]="~/.gitignore_global"
        ["alias.lg"]="log --color --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit"
    )

    # Check for conflicts
    local conflicts=()
    for key in "${!git_settings[@]}"; do
        local existing new
        existing=$(git config --global "$key" 2>/dev/null || echo "")
        new="${git_settings[$key]}"
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
merged = {**dotfiles, **existing}  # existing wins
with open(sys.argv[2], 'w') as f: json.dump(merged, f, indent=4); f.write('\n')
MERGE

    log_success "Merged $name settings (existing preserved)"
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
    while (( "$#" )); do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            --profile=*)
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
            --no-*)
                # Disable a component: --no-zsh, --no-claude, etc.
                local component="${1#--no-}"
                component="${component^^}"  # uppercase
                component="${component//-/_}"  # dashes to underscores
                declare -g "INSTALL_${component}=false" 2>/dev/null || \
                declare -g "DEPLOY_${component}=false" 2>/dev/null || \
                log_warning "Unknown component: $1"
                ;;
            --*)
                # Enable a component: --zsh, --claude, etc.
                local component="${1#--}"
                component="${component^^}"
                component="${component//-/_}"
                declare -g "INSTALL_${component}=true" 2>/dev/null || \
                declare -g "DEPLOY_${component}=true" 2>/dev/null || \
                log_warning "Unknown component: $1"
                ;;
            *)
                log_warning "Unknown argument: $1"
                ;;
        esac
        shift
    done
}
