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
if [[ ${#ALIASES[@]} -gt 0 ]]; then
    echo "using extra aliases: ${ALIASES[*]}"
else
    echo "using extra aliases: none"
fi
echo "mode: ${APPEND}"

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

# zshrc setup
eval "echo \"source $DOT_DIR/config/zshrc.sh\" $OP \"\$HOME/.zshrc\""
# Append additional alias scripts if specified
if [[ ${#ALIASES[@]} -gt 0 ]]; then
    for alias_name in "${ALIASES[@]}"; do
        echo "source $DOT_DIR/config/aliases_${alias_name}.sh" >> "$HOME/.zshrc"
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
