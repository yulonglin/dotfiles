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
        --cleanup               install automatic cleanup for ~/Downloads and ~/Screenshots
        --claude                deploy Claude Code configuration (symlink claude/ to ~/.claude)
        --experimental          enable experimental features (ty type checker)
        --minimal               disable defaults, deploy only specified components

    DEFAULTS (applied unless --minimal is used):
        --claude --vim --editor

    EXAMPLES:
        ./deploy.sh                           # Deploy defaults (claude + vim)
        ./deploy.sh --cleanup                 # Deploy defaults + cleanup
        ./deploy.sh --minimal --vim           # Deploy ONLY vim (no claude)
        ./deploy.sh --aliases=speechmatics    # Deploy defaults + speechmatics aliases
        ./deploy.sh --experimental            # Deploy defaults + ty type checker

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
EXPERIMENTAL="false"
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
        --experimental)
            EXPERIMENTAL="true" && shift ;;
        --) # end argument parsing
            shift && break ;;
        -*|--*=) # unsupported flags
            echo "Error: Unsupported flag $1" >&2 && exit 1 ;;
    esac
done

# Apply defaults unless --minimal was specified
if [ "$MINIMAL" = "false" ]; then
    echo "Applying defaults: --claude --vim --editor (use --minimal to disable)"
    CLAUDE="true"
    VIM="true"
    EDITOR="true"
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

# Shell configuration setup
CURRENT_SHELL="${SHELL##*/}"

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

# Git configuration deployment
echo ""
echo "Deploying git configuration..."

# Deploy global gitignore
if [[ -f "$DOT_DIR/config/gitignore_global" ]]; then
    cp "$DOT_DIR/config/gitignore_global" "$HOME/.gitignore_global"
    echo "✓ Deployed ~/.gitignore_global"
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

    # Define all git config values once using associative array
    declare -A GIT_VALUES=(
        ["user.email"]="$default_email"
        ["user.name"]="$default_name"
        ["push.autoSetupRemote"]="true"
        ["push.default"]="simple"
        ["init.defaultBranch"]="main"
        ["core.excludesfile"]="~/.gitignore_global"
        ["alias.lg"]="log --color --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit"
    )

    # Parse sections from template
    local sections=("user.email" "user.name" "push.autoSetupRemote" "push.default" "init.defaultBranch" "alias.lg" "core.excludesfile")
    local conflicts=()

    # Check for conflicts
    for section in "${sections[@]}"; do
        local existing_value
        existing_value=$(git config --global "$section" 2>/dev/null || echo "")

        if [[ -n "$existing_value" ]]; then
            local new_value="${GIT_VALUES[$section]}"

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
            git config --global "$section" "${GIT_VALUES[$section]}"
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
            git config --global "$section" "${GIT_VALUES[$section]}"
        done
    fi

    echo "✓ Git configuration deployed successfully!"
}

merge_git_config

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

# Install cleanup automation if requested
if [[ "$CLEANUP" == "true" ]]; then
    echo ""
    echo "Installing automatic cleanup..."
    if [[ -f "$DOT_DIR/scripts/cleanup/install.sh" ]]; then
        "$DOT_DIR/scripts/cleanup/install.sh" --non-interactive || echo "Warning: Cleanup installation failed"
    else
        echo "Warning: Cleanup install script not found at $DOT_DIR/scripts/cleanup/install.sh"
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
            echo "  Deployed: CLAUDE.md, settings.json, agents/, notify.sh"
        fi
    fi
fi

# echo "changing default shell to zsh"
# chsh -s $(which zsh)

# zsh
