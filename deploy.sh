#!/bin/bash
set -euo pipefail
USAGE=$(cat <<-END
    Usage: ./deploy.sh [OPTIONS] [--aliases <alias1,alias2,...>], eg. ./deploy.sh --vim --aliases=speechmatics,custom
    Creates ~/.zshrc and ~/.tmux.conf with location
    specific config

    OPTIONS:
        --vim                   deploy very simple vimrc config 
        --aliases               specify additional alias scripts to source in .zshrc, separated by commas
        --append               append to existing config files instead of overwriting
        --ascii                 specify the ASCII art file to use
END
)

export DOT_DIR=$(dirname $(realpath $0))

VIM="false"
ALIASES=()
APPEND="false"
ASCII_FILE="start.txt"  # Default value
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
    } >> "$rc_file" || { echo "Error: Failed to write tool integrations to $rc_file"; exit 1; }
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

# echo "changing default shell to zsh"
# chsh -s $(which zsh)

# zsh
