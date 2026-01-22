#!/bin/bash
set -euo pipefail
USAGE=$(cat <<-END
    Usage: ./deploy.sh [OPTIONS] [--aliases <alias1,alias2,...>], eg. ./deploy.sh --vim --aliases=speechmatics,custom
    Creates ~/.zshrc and ~/.tmux.conf with location
    specific config

    OPTIONS:
        --vim                   deploy very simple vimrc config
        --editor                deploy VSCode/Cursor settings and extensions (merges with existing)
        --aliases               specify additional alias scripts to source in .zshrc, separated by commas
        --append                append to existing config files instead of overwriting
        --ascii                 specify the ASCII art file to use
        --cleanup               install automatic cleanup for ~/Downloads and ~/Screenshots (macOS only)
        --claude                deploy Claude Code configuration (symlink claude/ to ~/.claude)
        --codex                 deploy Codex CLI configuration (symlink codex/ to ~/.codex)
        --ghostty               deploy Ghostty terminal configuration (symlink config/ghostty to config dir)
        --matplotlib            deploy matplotlib styles (anthropic, deepmind) to ~/.config/matplotlib/stylelib
        --git-hooks             deploy global git hooks (secret detection, layered with repo hooks)
        --experimental          enable experimental features (ty type checker)
        --secrets               sync secrets from/to GitHub gist (ssh config, git identity)
        --minimal               disable defaults, deploy only specified components

    DEFAULTS (applied unless --minimal is used):
        --claude --codex --vim --editor --experimental --ghostty --matplotlib --git-hooks --secrets --cleanup (macOS only)

    EXAMPLES:
        ./deploy.sh                           # Deploy all defaults
        ./deploy.sh --aliases=speechmatics    # Deploy defaults + speechmatics aliases
        ./deploy.sh --minimal --vim           # Deploy ONLY vim (no defaults)
        ./deploy.sh --minimal --claude        # Deploy ONLY claude (no other defaults)

    Git configuration is always deployed.
END
)

export DOT_DIR=$(dirname $(realpath $0))

VIM="false"
EDITOR="false"
ALIASES=()
APPEND="false"
ASCII_FILE="start.txt"  # Default value
CLEANUP="false"
CLAUDE="false"
CODEX="false"
GHOSTTY="false"
MATPLOTLIB="false"
GIT_HOOKS="false"
EXPERIMENTAL="false"
SECRETS="false"
MINIMAL="false"
while (( "$#" )); do
    case "$1" in
        -h|--help)
            echo "$USAGE" && exit 1 ;;
        --minimal)
            MINIMAL="true" && shift ;;
        --vim)
            VIM="true" && shift ;;
        --editor)
            EDITOR="true" && shift ;;
        --aliases=*)
            IFS=',' read -r -a ALIASES <<< "${1#*=}" && shift ;;
        --append)
            APPEND="true" && shift ;;
        --ascii=*)
            ASCII_FILE="${1#*=}" && shift ;;
        --cleanup)
            CLEANUP="true" && shift ;;
        --claude)
            CLAUDE="true" && shift ;;
        --codex)
            CODEX="true" && shift ;;
        --ghostty)
            GHOSTTY="true" && shift ;;
        --matplotlib)
            MATPLOTLIB="true" && shift ;;
        --git-hooks)
            GIT_HOOKS="true" && shift ;;
        --experimental)
            EXPERIMENTAL="true" && shift ;;
        --secrets)
            SECRETS="true" && shift ;;
        --) # end argument parsing
            shift && break ;;
        -*|--*=) # unsupported flags
            echo "Error: Unsupported flag $1" >&2 && exit 1 ;;
    esac
done

# Detect operating system
operating_system="$(uname -s)"
case "${operating_system}" in
    Linux*)     machine=Linux;;
    Darwin*)    machine=Mac;;
    *)          machine="UNKNOWN:${operating_system}"
                echo "Error: Unsupported operating system ${operating_system}" && exit 1
esac

# Install zsh if not present
if ! command -v zsh &>/dev/null; then
    echo "ZSH not found, installing..."
    if [[ "$machine" == "Mac" ]]; then
        brew install zsh
    else
        apt install -y zsh 2>/dev/null || echo "Warning: Could not install zsh"
    fi
fi

# Apply defaults unless --minimal was specified
if [ "$MINIMAL" = "false" ]; then
    echo "Applying defaults for $machine: --claude --codex --vim --editor --experimental --ghostty --matplotlib --git-hooks --secrets --cleanup (use --minimal to disable)"
    CLAUDE="true"
    CODEX="true"
    VIM="true"
    EDITOR="true"
    EXPERIMENTAL="true"
    GHOSTTY="true"
    MATPLOTLIB="true"
    GIT_HOOKS="true"
    SECRETS="true"
    # Cleanup only on macOS
    if [ "$machine" = "Mac" ]; then
        CLEANUP="true"
    fi
fi

echo "deploying on machine..."
echo "detected shell: ${SHELL##*/}"
if [[ ${#ALIASES[@]} -gt 0 ]]; then
    echo "using extra aliases: ${ALIASES[*]}"
else
    echo "using extra aliases: none"
fi

# Helper function to add common tool integrations
add_tool_integrations() {
    local rc_file="$1"
    local shell_name="$2"

    {
        echo ""
        echo "# Tool integrations"
        echo "[ -f ~/.fzf.${shell_name} ] && source ~/.fzf.${shell_name}"
        echo "[ -d \"\$HOME/.cargo\" ] && . \"\$HOME/.cargo/env\""
        echo "[ -d \"\$HOME/.local/bin\" ] && [ -f \"\$HOME/.local/bin/env\" ] && source \"\$HOME/.local/bin/env\""
        echo ""
        echo "# Atuin - unified shell history"
        echo "if [ -f \"\$HOME/.atuin/bin/env\" ]; then"
        echo "    source \"\$HOME/.atuin/bin/env\""
        echo "    eval \"\$(atuin init ${shell_name} --disable-up-arrow)\""
        echo "elif command -v atuin &> /dev/null; then"
        echo "    eval \"\$(atuin init ${shell_name} --disable-up-arrow)\""
        echo "fi"
    } >> "$rc_file" || { echo "Error: Failed to write tool integrations to $rc_file"; exit 1; }

    # Deploy Atuin config if it exists in dotfiles
    if [ -f "$DOT_DIR/config/atuin.toml" ]; then
        mkdir -p "$HOME/.config/atuin"
        cp "$DOT_DIR/config/atuin.toml" "$HOME/.config/atuin/config.toml"
        echo "Deployed Atuin configuration"
    fi
}

# Sync secrets from/to GitHub gist (bidirectional, last-modified wins)
deploy_secrets() {
    local gist_id="3cc239f160a2fe8c9e6a14829d85a371"

    # Check if gh is authenticated
    if ! gh auth status &>/dev/null 2>&1; then
        echo "⚠️  gh not authenticated - run 'gh auth login' to sync secrets"
        return 1
    fi

    # Get gist metadata
    local gist_data
    gist_data=$(gh api "/gists/$gist_id" 2>/dev/null) || {
        echo "⚠️  Failed to fetch gist - check network or gist ID"
        return 1
    }

    # Get gist updated_at timestamp (epoch seconds)
    local gist_updated_at
    gist_updated_at=$(echo "$gist_data" | python3 -c "import sys, json; from datetime import datetime; print(int(datetime.fromisoformat(json.load(sys.stdin)['updated_at'].replace('Z', '+00:00')).timestamp()))" 2>/dev/null)

    # Helper: get file mtime (cross-platform)
    get_mtime() {
        local file="$1"
        if [[ "$OSTYPE" == "darwin"* ]]; then
            stat -f %m "$file" 2>/dev/null || echo "0"
        else
            stat -c %Y "$file" 2>/dev/null || echo "0"
        fi
    }

    # Helper: get content from gist
    get_gist_file() {
        local filename="$1"
        echo "$gist_data" | python3 -c "import sys, json; d=json.load(sys.stdin); f=d['files'].get('$filename', {}); print(f.get('content', ''))" 2>/dev/null
    }

    # Helper: check if gist has file
    gist_has_file() {
        local filename="$1"
        echo "$gist_data" | python3 -c "import sys, json; d=json.load(sys.stdin); print('yes' if '$filename' in d['files'] else 'no')" 2>/dev/null
    }

    local changes_made=false

    # Sync SSH config
    echo "  Syncing SSH config..."
    local ssh_local="$HOME/.ssh/config"
    local ssh_gist_exists
    ssh_gist_exists=$(gist_has_file "config")

    if [[ ! -f "$ssh_local" ]]; then
        # Local doesn't exist - pull from gist
        if [[ "$ssh_gist_exists" == "yes" ]]; then
            mkdir -p "$HOME/.ssh"
            get_gist_file "config" > "$ssh_local"
            chmod 600 "$ssh_local"
            echo "    ↓ Pulled SSH config from gist (local was missing)"
            changes_made=true
        fi
    elif [[ "$ssh_gist_exists" == "no" ]]; then
        # Gist doesn't have it - push to gist
        gh gist edit "$gist_id" --add "$ssh_local" --filename "config" &>/dev/null
        echo "    ↑ Pushed SSH config to gist (gist was missing)"
        changes_made=true
    else
        # Both exist - compare and sync based on mtime
        local local_mtime
        local_mtime=$(get_mtime "$ssh_local")
        local gist_content
        gist_content=$(get_gist_file "config")
        local local_content
        local_content=$(cat "$ssh_local")

        if [[ "$local_content" != "$gist_content" ]]; then
            if [[ "$local_mtime" -gt "$gist_updated_at" ]]; then
                # Local is newer - push to gist
                gh gist edit "$gist_id" --add "$ssh_local" --filename "config" &>/dev/null
                echo "    ↑ Pushed SSH config to gist (local newer)"
                changes_made=true
            else
                # Gist is newer - pull from gist
                echo "$gist_content" > "$ssh_local"
                chmod 600 "$ssh_local"
                echo "    ↓ Pulled SSH config from gist (gist newer)"
                changes_made=true
            fi
        else
            echo "    ✓ SSH config in sync"
        fi
    fi

    # Sync user.conf (git identity)
    echo "  Syncing git identity..."
    local user_local="$DOT_DIR/config/user.conf"
    local user_gist_exists
    user_gist_exists=$(gist_has_file "user.conf")

    if [[ ! -f "$user_local" ]]; then
        # Local doesn't exist - pull from gist
        if [[ "$user_gist_exists" == "yes" ]]; then
            get_gist_file "user.conf" > "$user_local"
            echo "    ↓ Pulled user.conf from gist (local was missing)"
            changes_made=true
        fi
    elif [[ "$user_gist_exists" == "no" ]]; then
        # Gist doesn't have it - push to gist
        gh gist edit "$gist_id" --add "$user_local" --filename "user.conf" &>/dev/null
        echo "    ↑ Pushed user.conf to gist (gist was missing)"
        changes_made=true
    else
        # Both exist - compare and sync based on mtime
        local local_mtime
        local_mtime=$(get_mtime "$user_local")
        local gist_content
        gist_content=$(get_gist_file "user.conf")
        local local_content
        local_content=$(cat "$user_local")

        if [[ "$local_content" != "$gist_content" ]]; then
            if [[ "$local_mtime" -gt "$gist_updated_at" ]]; then
                # Local is newer - push to gist
                gh gist edit "$gist_id" --add "$user_local" --filename "user.conf" &>/dev/null
                echo "    ↑ Pushed user.conf to gist (local newer)"
                changes_made=true
            else
                # Gist is newer - pull from gist
                echo "$gist_content" > "$user_local"
                echo "    ↓ Pulled user.conf from gist (gist newer)"
                changes_made=true
            fi
        else
            echo "    ✓ Git identity in sync"
        fi
    fi

    if [[ "$changes_made" == "true" ]]; then
        echo "✓ Secrets synced with gist"
    else
        echo "✓ All secrets already in sync"
    fi
}

echo "append mode: ${APPEND}"

# Set the operator based on append flag
OP=">"
if [[ $APPEND == "true" ]]; then
    OP=">>"
fi

# Tmux setup
eval "echo \"source $DOT_DIR/config/tmux.conf\" $OP \"\$HOME/.tmux.conf\""

# Vimrc
if [[ $VIM == "true" ]]; then
    echo "deploying .vimrc"
    eval "echo \"source $DOT_DIR/config/vimrc\" $OP \"\$HOME/.vimrc\""
fi

# Shell configuration setup - default to zsh if available
if command -v zsh &>/dev/null; then
    CURRENT_SHELL="zsh"
else
    CURRENT_SHELL="${SHELL##*/}"
fi

# For zsh, use the full zshrc.sh which includes oh-my-zsh setup
if [[ "$CURRENT_SHELL" == "zsh" ]]; then
    eval "echo \"source $DOT_DIR/config/zshrc.sh\" $OP \"\$HOME/.zshrc\""
    RC_FILE="$HOME/.zshrc"
# For bash, source individual components (skip zsh-specific parts)
elif [[ "$CURRENT_SHELL" == "bash" ]]; then
    # Handle append mode properly for bash
    if [[ $APPEND == "false" ]]; then
        > "$HOME/.bashrc"  # Clear file first if not appending
    fi
    
    # Create minimal bashrc config that sources the essential files
    {
        echo "# Dotfiles configuration"
        echo "export DOT_DIR=$DOT_DIR"
        echo "source $DOT_DIR/config/aliases.sh"
        echo "source $DOT_DIR/config/key_bindings.sh"  # Safe to source - has shell detection
        # Skip extras.sh for bash - it contains zsh-specific settings
        echo "source $DOT_DIR/config/modern_tools.sh"
        echo "export PATH=\"\$DOT_DIR/custom_bins:\$PATH\""
    } >> "$HOME/.bashrc" || { echo "Error: Failed to write to $HOME/.bashrc"; exit 1; }
    
    # Add common tool integrations
    add_tool_integrations "$HOME/.bashrc" "bash"
    
    # ASCII art for interactive shells
    {
        echo ""
        echo "# Display ASCII art in interactive shells"
        echo "[[ \$- == *i* ]] && [ -f $DOT_DIR/config/start.txt ] && cat $DOT_DIR/config/start.txt"
    } >> "$HOME/.bashrc" || { echo "Error: Failed to write ASCII art config to $HOME/.bashrc"; exit 1; }
    
    # Add .bashrc sourcing and ZSH switcher to .bash_profile for login shells
    # Check if we need to add these components
    needs_bashrc_source=false
    needs_zsh_switcher=false

    if [[ $APPEND == "false" ]] || ! grep -q "source.*\.bashrc\|\..*\.bashrc" ~/.bash_profile 2>/dev/null; then
        needs_bashrc_source=true
    fi

    if [[ $APPEND == "false" ]] || ! grep -q "bash_zsh_switcher.sh" ~/.bash_profile 2>/dev/null; then
        needs_zsh_switcher=true
    fi

    if [[ "$needs_bashrc_source" == "true" ]] || [[ "$needs_zsh_switcher" == "true" ]]; then
        {
            if [[ "$needs_bashrc_source" == "true" ]]; then
                echo ""
                echo "# Source .bashrc for login shells (SSH sessions)"
                echo "# This MUST come before ZSH switcher to ensure aliases are loaded"
                echo "if [ -f \"\$HOME/.bashrc\" ]; then"
                echo "    . \"\$HOME/.bashrc\""
                echo "fi"
            fi

            if [[ "$needs_zsh_switcher" == "true" ]]; then
                echo ""
                echo "# ZSH switcher - comes AFTER .bashrc to preserve aliases if staying in bash"
                echo "[ -f $DOT_DIR/config/bash_zsh_switcher.sh ] && source $DOT_DIR/config/bash_zsh_switcher.sh"
            fi
        } >> "$HOME/.bash_profile" || { echo "Error: Failed to write to $HOME/.bash_profile"; exit 1; }
        echo "Updated ~/.bash_profile with bashrc sourcing and/or ZSH switcher"
    fi
    
    RC_FILE="$HOME/.bashrc"
else
    echo "Warning: Unknown shell '$CURRENT_SHELL'. Defaulting to zsh setup."
    eval "echo \"source $DOT_DIR/config/zshrc.sh\" $OP \"\$HOME/.zshrc\""
    RC_FILE="$HOME/.zshrc"
fi

# Append additional alias scripts if specified
if [[ ${#ALIASES[@]} -gt 0 ]]; then
    for alias_name in "${ALIASES[@]}"; do
        echo "source $DOT_DIR/config/aliases_${alias_name}.sh" >> "$RC_FILE"
    done
fi

# After parsing arguments
if [[ "$ASCII_FILE" != "start.txt" ]]; then
    echo "Using custom ASCII art: $ASCII_FILE"
    cp "$DOT_DIR/config/ascii_arts/$ASCII_FILE" "$DOT_DIR/config/start.txt"
fi

# Deploy secrets before git config (user.conf is needed for git identity)
if [[ "$SECRETS" == "true" ]]; then
    echo ""
    echo "Syncing secrets with GitHub gist..."
    deploy_secrets || echo "Warning: Secrets sync failed (continuing anyway)"
fi

# Git configuration deployment
echo ""
echo "Deploying git configuration..."

# Deploy global gitignore
if [[ -f "$DOT_DIR/config/gitignore_global" ]]; then
    cp "$DOT_DIR/config/gitignore_global" "$HOME/.gitignore_global"
    echo "✓ Deployed ~/.gitignore_global"
fi

# Deploy global ignore for fd
if [[ -f "$DOT_DIR/config/ignore_global" ]]; then
    mkdir -p "$HOME/.config/fd"
    cp "$DOT_DIR/config/ignore_global" "$HOME/.config/fd/ignore"
    echo "✓ Deployed ~/.config/fd/ignore"
fi

# Function to merge git config
merge_git_config() {
    local template="$DOT_DIR/config/gitconfig"

    if [[ ! -f "$template" ]]; then
        echo "Warning: Git config template not found at $template"
        return 1
    fi

    # Check if git is installed
    if ! command -v git &> /dev/null; then
        echo "Warning: git is not installed. Skipping git config deployment."
        return 1
    fi

    # Load user configuration if exists
    local default_email="30549145+yulonglin@users.noreply.github.com"
    local default_name="yulonglin"

    if [[ -f "$DOT_DIR/config/user.conf" ]]; then
        source "$DOT_DIR/config/user.conf"
        default_email="${GIT_USER_EMAIL:-$default_email}"
        default_name="${GIT_USER_NAME:-$default_name}"
        echo "  Using custom git user config from config/user.conf"
    fi

    # Function to get git config value for a key (Bash 3.2 compatible)
    get_git_value() {
        local key="$1"
        case "$key" in
            "user.email") echo "$default_email" ;;
            "user.name") echo "$default_name" ;;
            "push.autoSetupRemote") echo "true" ;;
            "push.default") echo "simple" ;;
            "init.defaultBranch") echo "main" ;;
            "core.excludesfile") echo "~/.gitignore_global" ;;
            "alias.lg") echo "log --color --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit" ;;
            *) echo "" ;;
        esac
    }

    # Parse sections from template
    local sections=("user.email" "user.name" "push.autoSetupRemote" "push.default" "init.defaultBranch" "alias.lg" "core.excludesfile")
    local conflicts=()

    # Check for conflicts
    for section in "${sections[@]}"; do
        local existing_value
        existing_value=$(git config --global "$section" 2>/dev/null || echo "")

        if [[ -n "$existing_value" ]]; then
            local new_value
            new_value=$(get_git_value "$section")

            # Check if values differ
            if [[ "$existing_value" != "$new_value" ]]; then
                conflicts+=("$section|$existing_value|$new_value")
            fi
        fi
    done

    # Handle conflicts if any
    if [[ ${#conflicts[@]} -gt 0 ]]; then
        echo ""
        echo "⚠️  Git config conflicts detected:"
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
        echo "  [M]erge interactively (choose per setting)"
        echo "  [S]kip git config deployment"
        echo ""
        read -p "Choose [K/U/M/S]: " -n 1 -r choice
        echo ""

        # Helper function to apply git config value
        apply_git_config() {
            local section="$1"
            local value
            value=$(get_git_value "$section")
            git config --global "$section" "$value"
        }

        case "$choice" in
            [Kk])
                echo "Keeping all existing values. Applying non-conflicting settings..."
                # Apply only non-conflicting settings
                for section in "${sections[@]}"; do
                    local is_conflict=false
                    for conflict in "${conflicts[@]}"; do
                        IFS='|' read -r key _ _ <<< "$conflict"
                        if [[ "$key" == "$section" ]]; then
                            is_conflict=true
                            break
                        fi
                    done

                    if [[ "$is_conflict" == "false" ]]; then
                        local existing_value
                        existing_value=$(git config --global "$section" 2>/dev/null || echo "")
                        if [[ -z "$existing_value" ]]; then
                            apply_git_config "$section"
                        fi
                    fi
                done
                ;;
            [Uu])
                echo "Using all new values from dotfiles..."
                for section in "${sections[@]}"; do
                    apply_git_config "$section"
                done
                ;;
            [Mm])
                echo "Interactive merge..."
                for conflict in "${conflicts[@]}"; do
                    IFS='|' read -r key existing new <<< "$conflict"
                    echo ""
                    echo "[$key]"
                    echo "  [1] Keep existing: $existing"
                    echo "  [2] Use new: $new"
                    read -p "Choose [1/2]: " -n 1 -r setting_choice
                    echo ""

                    if [[ "$setting_choice" == "2" ]]; then
                        apply_git_config "$key"
                        echo "  → Set to: $new"
                    else
                        echo "  → Kept: $existing"
                    fi
                done

                # Apply non-conflicting settings
                echo ""
                echo "Applying non-conflicting settings..."
                for section in "${sections[@]}"; do
                    local is_conflict=false
                    for conflict in "${conflicts[@]}"; do
                        IFS='|' read -r key _ _ <<< "$conflict"
                        if [[ "$key" == "$section" ]]; then
                            is_conflict=true
                            break
                        fi
                    done

                    if [[ "$is_conflict" == "false" ]]; then
                        local existing_value
                        existing_value=$(git config --global "$section" 2>/dev/null || echo "")
                        if [[ -z "$existing_value" ]]; then
                            apply_git_config "$section"
                        fi
                    fi
                done
                ;;
            [Ss])
                echo "Skipping git config deployment."
                return 0
                ;;
            *)
                echo "Invalid choice. Skipping git config deployment."
                return 0
                ;;
        esac
    else
        # No conflicts, apply all settings
        echo "No conflicts detected. Applying all settings..."
        for section in "${sections[@]}"; do
            local value
            value=$(get_git_value "$section")
            git config --global "$section" "$value"
        done
    fi

    echo "✓ Git configuration deployed successfully!"
}

merge_git_config

# Deploy global git hooks if requested
if [[ "$GIT_HOOKS" == "true" ]]; then
    echo ""
    echo "Deploying global git hooks..."

    if [[ ! -d "$DOT_DIR/config/git-hooks" ]]; then
        echo "Warning: Git hooks directory not found at $DOT_DIR/config/git-hooks"
    else
        # Create ~/.git-hooks directory
        mkdir -p "$HOME/.git-hooks"

        # Copy hooks to ~/.git-hooks (not symlink, so they work even if dotfiles moves)
        for hook in "$DOT_DIR/config/git-hooks"/*; do
            if [[ -f "$hook" ]]; then
                hook_name=$(basename "$hook")
                cp "$hook" "$HOME/.git-hooks/$hook_name"
                chmod +x "$HOME/.git-hooks/$hook_name"
            fi
        done

        # Set global git hooks path
        git config --global core.hooksPath "$HOME/.git-hooks"
        echo "✓ Deployed global git hooks to ~/.git-hooks"
        echo "✓ Set git config core.hooksPath to ~/.git-hooks"
        echo "  Features:"
        echo "    - Secret detection (gitleaks or regex fallback)"
        echo "    - Layered with repo hooks (pre-commit framework, husky, .local)"
        echo "  Note: Repo hooks in .git/hooks/ are shadowed. To use both:"
        echo "    - Pre-commit framework: just add .pre-commit-config.yaml (auto-detected)"
        echo "    - Manual hooks: rename to .git/hooks/pre-commit.local"

        # Check if gitleaks is installed
        if ! command -v gitleaks &> /dev/null; then
            echo ""
            echo "  ⚠️  gitleaks not installed. Using regex fallback (less accurate)."
            echo "     Install for better detection: brew install gitleaks"
        fi
    fi
fi

# Deploy editor settings if requested
deploy_editor_settings() {
    local settings_file="$DOT_DIR/config/vscode_settings.json"

    if [[ ! -f "$settings_file" ]]; then
        echo "Warning: VSCode settings file not found at $settings_file"
        return 1
    fi

    # Merge ty settings if experimental mode is enabled
    if [[ "$EXPERIMENTAL" == "true" ]]; then
        local ty_settings="$DOT_DIR/config/vscode_settings_ty.json"
        if [[ -f "$ty_settings" ]]; then
            echo "  Experimental mode: merging ty settings"
            # Create a temporary merged settings file
            local temp_settings="/tmp/vscode_settings_merged_$$.json"
            python3 - "$settings_file" "$ty_settings" "$temp_settings" <<'TY_MERGE'
import json
import sys

base_path = sys.argv[1]
ty_path = sys.argv[2]
output_path = sys.argv[3]

# Read both files
with open(base_path, 'r') as f:
    base = json.load(f)
with open(ty_path, 'r') as f:
    ty = json.load(f)

# Merge: ty settings added to base
merged = {**base, **ty}

# Write merged settings
with open(output_path, 'w') as f:
    json.dump(merged, f, indent=4)
    f.write('\n')
TY_MERGE
            settings_file="$temp_settings"
        else
            echo "  Warning: ty settings file not found at $ty_settings"
        fi
    fi

    # Detect OS and set paths accordingly
    local vscode_dir=""
    local cursor_dir=""

    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS paths
        vscode_dir="$HOME/Library/Application Support/Code/User"
        cursor_dir="$HOME/Library/Application Support/Cursor/User"
    else
        # Linux paths
        vscode_dir="$HOME/.config/Code/User"
        cursor_dir="$HOME/.config/Cursor/User"
    fi

    # Helper function to merge settings for a specific editor
    merge_editor_settings() {
        local editor_name="$1"
        local target_file="$2"

        if [[ ! -f "$target_file" ]]; then
            # No existing settings, just copy
            cp "$settings_file" "$target_file"
            echo "✓ Deployed $editor_name settings to $target_file (new)"
            return 0
        fi

        # Existing settings found - merge with dotfiles
        python3 - "$settings_file" "$target_file" <<'MERGE_SCRIPT'
import json
import sys

dotfiles_path = sys.argv[1]
existing_path = sys.argv[2]

# Read both files
with open(dotfiles_path, 'r') as f:
    dotfiles = json.load(f)
with open(existing_path, 'r') as f:
    existing = json.load(f)

# Merge: existing settings take precedence, dotfiles adds new keys
merged = {**dotfiles, **existing}

# Write merged settings back
with open(existing_path, 'w') as f:
    json.dump(merged, f, indent=4)
    f.write('\n')  # Add trailing newline

print("merged")
MERGE_SCRIPT

        if [[ $? -eq 0 ]]; then
            echo "✓ Merged $editor_name settings to $target_file (existing settings preserved)"
        else
            echo "⚠️  Failed to merge $editor_name settings, keeping existing"
            return 1
        fi
    }

    # Helper function to install extensions for a specific editor
    install_extensions() {
        local editor_name="$1"
        local cli_command="$2"
        local extensions_file="$DOT_DIR/config/vscode_extensions.txt"

        # Check if CLI is available
        if ! command -v "$cli_command" &> /dev/null; then
            echo "  ℹ️  $cli_command CLI not found, skipping extension installation for $editor_name"
            return 0
        fi

        # Check if extensions file exists
        if [[ ! -f "$extensions_file" ]]; then
            echo "  ℹ️  Extensions file not found at $extensions_file"
            return 0
        fi

        echo "  Installing extensions for $editor_name..."
        local installed_count=0
        local skipped_count=0

        # Read and install extensions from base file
        while IFS= read -r line || [[ -n "$line" ]]; do
            # Skip empty lines and comments
            [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

            # Trim whitespace
            local ext_id=$(echo "$line" | xargs)

            # Install extension (suppress verbose output)
            if $cli_command --install-extension "$ext_id" --force &> /dev/null; then
                ((installed_count++))
            else
                ((skipped_count++))
            fi
        done < "$extensions_file"

        # Install experimental extensions if enabled
        if [[ "$EXPERIMENTAL" == "true" ]]; then
            local ty_extensions="$DOT_DIR/config/vscode_extensions_ty.txt"
            if [[ -f "$ty_extensions" ]]; then
                echo "  Installing experimental extensions for $editor_name..."
                while IFS= read -r line || [[ -n "$line" ]]; do
                    # Skip empty lines and comments
                    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

                    # Trim whitespace
                    local ext_id=$(echo "$line" | xargs)

                    # Install extension (suppress verbose output)
                    if $cli_command --install-extension "$ext_id" --force &> /dev/null; then
                        ((installed_count++))
                    else
                        ((skipped_count++))
                    fi
                done < "$ty_extensions"
            fi
        fi

        if [[ $installed_count -gt 0 ]]; then
            echo "  ✓ Installed $installed_count extension(s) for $editor_name"
        fi
        if [[ $skipped_count -gt 0 ]]; then
            echo "  ⚠️  $skipped_count extension(s) failed or already installed"
        fi
    }

    local deployed=false

    # Deploy to VSCode if installed
    if [[ -d "$vscode_dir" ]]; then
        merge_editor_settings "VSCode" "$vscode_dir/settings.json"
        install_extensions "VSCode" "code"
        deployed=true
    fi

    # Deploy to Cursor if installed
    if [[ -d "$cursor_dir" ]]; then
        merge_editor_settings "Cursor" "$cursor_dir/settings.json"
        install_extensions "Cursor" "cursor"
        deployed=true
    fi

    if [[ "$deployed" == "false" ]]; then
        echo "⚠️  Neither VSCode nor Cursor installation directories found"
        echo "   VSCode: $vscode_dir"
        echo "   Cursor: $cursor_dir"
        return 1
    fi
}

if [[ "$EDITOR" == "true" ]]; then
    echo ""
    echo "Deploying editor settings..."
    deploy_editor_settings || echo "Warning: Editor settings deployment failed"
fi

# Deploy Finicky configuration (macOS only)
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo ""
    echo "Deploying Finicky configuration..."

    if [[ ! -f "$DOT_DIR/config/finicky.js" ]]; then
        echo "Warning: Finicky config not found at $DOT_DIR/config/finicky.js"
    else
        # Check if ~/.finicky.js exists and is not already our symlink
        if [[ -e "$HOME/.finicky.js" && ! -L "$HOME/.finicky.js" ]]; then
            # Backup existing config
            backup_path="$HOME/.finicky.js.backup.$(date +%Y%m%d_%H%M%S)"
            mv "$HOME/.finicky.js" "$backup_path"
            echo "  Backed up existing config to $backup_path"
        elif [[ -L "$HOME/.finicky.js" ]]; then
            # Remove existing symlink
            rm "$HOME/.finicky.js"
            echo "  Removed existing symlink"
        fi

        # Create symlink
        ln -sf "$DOT_DIR/config/finicky.js" "$HOME/.finicky.js"
        echo "✓ Symlinked $DOT_DIR/config/finicky.js to ~/.finicky.js"
        echo "  Default browser: Safari"
        echo "  Google apps (Docs/Drive/Meet/Calendar/Mail): Google Chrome"
        echo "  Zoom meetings: Zoom app"
        echo "  Project management (Notion/Linear): Google Chrome"

        # Check if Finicky is installed
        if [[ ! -d "/Applications/Finicky.app" ]]; then
            echo ""
            echo "  ⚠️  Finicky not installed. Run './install.sh' to install it."
        fi
    fi
fi

# Deploy Ghostty configuration
if [[ "$GHOSTTY" == "true" ]]; then
    echo ""
    echo "Deploying Ghostty configuration..."

    # Ghostty config path is platform-specific
    if [[ "$machine" == "Mac" ]]; then
        GHOSTTY_CONFIG_DIR="$HOME/Library/Application Support/com.mitchellh.ghostty"
    else
        # Linux/other platforms use XDG_CONFIG_HOME or ~/.config
        GHOSTTY_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/ghostty"
    fi

    if [[ ! -f "$DOT_DIR/config/ghostty" ]]; then
        echo "Warning: Ghostty config not found at $DOT_DIR/config/ghostty"
    else
        # Create config directory if it doesn't exist
        mkdir -p "$GHOSTTY_CONFIG_DIR"

        # Check if config exists and is not already our symlink
        if [[ -e "$GHOSTTY_CONFIG_DIR/config" && ! -L "$GHOSTTY_CONFIG_DIR/config" ]]; then
            # Backup existing config
            backup_path="$GHOSTTY_CONFIG_DIR/config.backup.$(date +%Y%m%d_%H%M%S)"
            mv "$GHOSTTY_CONFIG_DIR/config" "$backup_path"
            echo "  Backed up existing config to $backup_path"
        elif [[ -L "$GHOSTTY_CONFIG_DIR/config" ]]; then
            # Remove existing symlink
            rm "$GHOSTTY_CONFIG_DIR/config"
            echo "  Removed existing symlink"
        fi

        # Create symlink
        ln -sf "$DOT_DIR/config/ghostty" "$GHOSTTY_CONFIG_DIR/config"
        echo "✓ Symlinked $DOT_DIR/config/ghostty to $GHOSTTY_CONFIG_DIR/config"
        echo "  Key bindings:"
        echo "    - Shift+Enter: Insert newline without executing"
        echo "    - Cmd+C: Copy selected text (shell-based, works with Opt+Shift selection)"
        echo "  Reload config: Cmd+Shift+Comma (or restart Ghostty)"
    fi
fi

# Install cleanup automation if requested (macOS only)
if [[ "$CLEANUP" == "true" ]]; then
    echo ""
    if [ "$machine" != "Mac" ]; then
        echo "Skipping cleanup installation (macOS only)"
    else
        echo "Installing automatic cleanup..."
        if [[ -f "$DOT_DIR/scripts/cleanup/install.sh" ]]; then
            "$DOT_DIR/scripts/cleanup/install.sh" --non-interactive || echo "Warning: Cleanup installation failed"
        else
            echo "Warning: Cleanup install script not found at $DOT_DIR/scripts/cleanup/install.sh"
        fi
    fi
fi

# Deploy Claude Code configuration if requested
if [[ "$CLAUDE" == "true" ]]; then
    echo ""
    echo "Deploying Claude Code configuration..."

    if [[ ! -d "$DOT_DIR/claude" ]]; then
        echo "Warning: Claude Code directory not found at $DOT_DIR/claude"
    else
        # Remove existing ~/.claude if it's a symlink
        if [[ -L "$HOME/.claude" ]]; then
            rm "$HOME/.claude"
            echo "  Removed existing symlink at ~/.claude"
        elif [[ -e "$HOME/.claude" ]]; then
            echo "  Warning: ~/.claude exists and is not a symlink"
            echo "  Please backup and remove ~/.claude manually, then run deploy.sh --claude again"
        fi

        # Create symlink
        if [[ ! -e "$HOME/.claude" ]]; then
            ln -sf "$DOT_DIR/claude" "$HOME/.claude"
            echo "✓ Symlinked $DOT_DIR/claude to ~/.claude"
            echo "  Deployed: CLAUDE.md, settings.json, agents/, hooks/"
        fi

        # # Configure Claude Code settings (requires claude CLI)
        # if command -v claude &> /dev/null; then
        #     claude config set preferredNotifChannel terminal_bell 2>/dev/null && \
        #         echo "✓ Enabled terminal bell notifications"
        # fi
    fi
fi

# Deploy matplotlib styles if requested
if [[ "$MATPLOTLIB" == "true" ]]; then
    echo ""
    echo "Deploying matplotlib styles..."

    MATPLOTLIB_STYLELIB="$HOME/.config/matplotlib/stylelib"

    if [[ ! -d "$DOT_DIR/config/matplotlib" ]]; then
        echo "Warning: Matplotlib config directory not found at $DOT_DIR/config/matplotlib"
    else
        # Create stylelib directory if it doesn't exist
        mkdir -p "$MATPLOTLIB_STYLELIB"

        # Symlink each style file
        for style in "$DOT_DIR/config/matplotlib"/*.mplstyle; do
            if [[ -f "$style" ]]; then
                style_name=$(basename "$style")

                # Remove existing symlink if present
                if [[ -L "$MATPLOTLIB_STYLELIB/$style_name" ]]; then
                    rm "$MATPLOTLIB_STYLELIB/$style_name"
                elif [[ -e "$MATPLOTLIB_STYLELIB/$style_name" ]]; then
                    # Backup existing file
                    backup_path="$MATPLOTLIB_STYLELIB/$style_name.backup.$(date +%Y%m%d_%H%M%S)"
                    mv "$MATPLOTLIB_STYLELIB/$style_name" "$backup_path"
                    echo "  Backed up existing $style_name to $backup_path"
                fi

                ln -sf "$style" "$MATPLOTLIB_STYLELIB/$style_name"
            fi
        done

        echo "✓ Symlinked matplotlib styles to $MATPLOTLIB_STYLELIB"
        echo "  Available styles:"
        echo "    - plt.style.use('anthropic')  # Anthropic/anthroplot colors"
        echo "    - plt.style.use('deepmind')   # Google DeepMind colors"
    fi
fi

# Deploy Codex CLI configuration if requested
if [[ "$CODEX" == "true" ]]; then
    echo ""
    echo "Deploying Codex CLI configuration..."

    if [[ ! -d "$DOT_DIR/codex" ]]; then
        echo "Warning: Codex directory not found at $DOT_DIR/codex"
    else
        # Remove existing ~/.codex if it's a symlink
        if [[ -L "$HOME/.codex" ]]; then
            rm "$HOME/.codex"
            echo "  Removed existing symlink at ~/.codex"
        elif [[ -e "$HOME/.codex" ]]; then
            echo "  Warning: ~/.codex exists and is not a symlink"
            echo "  Please backup and remove ~/.codex manually, then run deploy.sh --codex again"
        fi

        # Create symlink
        if [[ ! -e "$HOME/.codex" ]]; then
            ln -sf "$DOT_DIR/codex" "$HOME/.codex"
            echo "✓ Symlinked $DOT_DIR/codex to ~/.codex"
            echo "  Deployed: Codex CLI configuration directory"
        fi
    fi
fi

# echo "changing default shell to zsh"
# chsh -s $(which zsh)

# zsh
