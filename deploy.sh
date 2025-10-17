#!/bin/bash
set -euo pipefail
USAGE=$(cat <<-END
    Usage: ./deploy.sh [OPTIONS] [--aliases <alias1,alias2,...>], eg. ./deploy.sh --vim --aliases=speechmatics,custom
    Creates ~/.zshrc and ~/.tmux.conf with location
    specific config

    OPTIONS:
        --vim                   deploy very simple vimrc config
        --aliases               specify additional alias scripts to source in .zshrc, separated by commas
        --append                append to existing config files instead of overwriting
        --ascii                 specify the ASCII art file to use
        --cleanup               install automatic cleanup for ~/Downloads and ~/Screenshots
END
)

export DOT_DIR=$(dirname $(realpath $0))

VIM="false"
ALIASES=()
APPEND="false"
ASCII_FILE="start.txt"  # Default value
CLEANUP="false"
while (( "$#" )); do
    case "$1" in
        -h|--help)
            echo "$USAGE" && exit 1 ;;
        --vim)
            VIM="true" && shift ;;
        --aliases=*)
            IFS=',' read -r -a ALIASES <<< "${1#*=}" && shift ;;
        --append)
            APPEND="true" && shift ;;
        --ascii=*)
            ASCII_FILE="${1#*=}" && shift ;;
        --cleanup)
            CLEANUP="true" && shift ;;
        --) # end argument parsing
            shift && break ;;
        -*|--*=) # unsupported flags
            echo "Error: Unsupported flag $1" >&2 && exit 1 ;;
    esac
done

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

    # Parse sections from template
    local sections=("user.email" "user.name" "push.autoSetupRemote" "push.default" "init.defaultBranch" "alias.lg" "core.excludesfile")
    local conflicts=()

    # Check for conflicts
    for section in "${sections[@]}"; do
        local existing_value
        existing_value=$(git config --global "$section" 2>/dev/null || echo "")

        if [[ -n "$existing_value" ]]; then
            # Get new value from template
            local new_value
            case "$section" in
                "user.email")
                    new_value="30549145+yulonglin@users.noreply.github.com"
                    ;;
                "user.name")
                    new_value="yulonglin"
                    ;;
                "push.autoSetupRemote")
                    new_value="true"
                    ;;
                "push.default")
                    new_value="simple"
                    ;;
                "init.defaultBranch")
                    new_value="main"
                    ;;
                "core.excludesfile")
                    new_value="~/.gitignore_global"
                    ;;
                "alias.lg")
                    new_value="log --color --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit"
                    ;;
            esac

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
                            # Apply new setting
                            case "$section" in
                                "user.email")
                                    git config --global "$section" "30549145+yulonglin@users.noreply.github.com"
                                    ;;
                                "user.name")
                                    git config --global "$section" "yulonglin"
                                    ;;
                                "push.autoSetupRemote")
                                    git config --global "$section" true
                                    ;;
                                "push.default")
                                    git config --global "$section" "simple"
                                    ;;
                                "init.defaultBranch")
                                    git config --global "$section" "main"
                                    ;;
                                "core.excludesfile")
                                    git config --global "$section" "~/.gitignore_global"
                                    ;;
                                "alias.lg")
                                    git config --global "$section" "log --color --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit"
                                    ;;
                            esac
                        fi
                    fi
                done
                ;;
            [Uu])
                echo "Using all new values from dotfiles..."
                git config --global user.email "30549145+yulonglin@users.noreply.github.com"
                git config --global user.name "yulonglin"
                git config --global push.autoSetupRemote true
                git config --global push.default simple
                git config --global init.defaultBranch main
                git config --global core.excludesfile "~/.gitignore_global"
                git config --global alias.lg "log --color --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit"
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
                        git config --global "$key" "$new"
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
                            case "$section" in
                                "user.email")
                                    git config --global "$section" "30549145+yulonglin@users.noreply.github.com"
                                    ;;
                                "user.name")
                                    git config --global "$section" "yulonglin"
                                    ;;
                                "push.autoSetupRemote")
                                    git config --global "$section" true
                                    ;;
                                "push.default")
                                    git config --global "$section" "simple"
                                    ;;
                                "init.defaultBranch")
                                    git config --global "$section" "main"
                                    ;;
                                "core.excludesfile")
                                    git config --global "$section" "~/.gitignore_global"
                                    ;;
                                "alias.lg")
                                    git config --global "$section" "log --color --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit"
                                    ;;
                            esac
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
        git config --global user.email "30549145+yulonglin@users.noreply.github.com"
        git config --global user.name "yulonglin"
        git config --global push.autoSetupRemote true
        git config --global push.default simple
        git config --global init.defaultBranch main
        git config --global core.excludesfile "~/.gitignore_global"
        git config --global alias.lg "log --color --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit"
    fi

    echo "✓ Git configuration deployed successfully!"
}

merge_git_config

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

# echo "changing default shell to zsh"
# chsh -s $(which zsh)

# zsh
