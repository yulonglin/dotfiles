#!/bin/bash
set -euo pipefail
USAGE=$(cat <<-END
    Usage: ./install.sh [OPTION]
    Install dotfile dependencies on mac or linux

    OPTIONS:
        --tmux       install tmux
        --zsh        install zsh
        --extras     install extra dependencies

    If OPTIONS are passed they will be installed
    with apt if on linux or brew if on OSX
END
)

zsh=false
tmux=false
extras=false
force=false
while (( "$#" )); do
    case "$1" in
        -h|--help)
            echo "$USAGE" && exit 1 ;;
        --zsh)
            zsh=true && shift ;;
        --tmux)
            tmux=true && shift ;;
        --extras)
            extras=true && shift ;;
        --force)
            force=true && shift ;;
        --) # end argument parsing
            shift && break ;;
        -*|--*=) # unsupported flags
            echo "Error: Unsupported flag $1" >&2 && exit 1 ;;
    esac
done

operating_system="$(uname -s)"
case "${operating_system}" in
    Linux*)     machine=Linux;;
    Darwin*)    machine=Mac;;
    *)          machine="UNKNOWN:${operating_system}"
                echo "Error: Unsupported operating system ${operating_system}" && exit 1
esac

# Installing on linux with apt
if [ $machine == "Linux" ]; then
    DOT_DIR=$(dirname $(realpath $0))
    apt update -y 2>/dev/null || echo "Skipping apt update (no permissions)"
    
    # Try installing ZSH, fall back to local install if it fails
    if [ $zsh == true ]; then
        if ! command -v zsh &> /dev/null && [ ! -f "$HOME/local/bin/zsh" ]; then
            apt install -y zsh 2>/dev/null || {
                echo "apt install zsh failed, installing locally..."
                "$DOT_DIR/install_zsh_local.sh"
            }
        else
            echo "ZSH already installed"
        fi
    fi
    
    [ $tmux == true ] && apt install -y tmux 2>/dev/null || true
    apt install -y less nano htop ncdu nvtop lsof rsync jq 2>/dev/null || true
    curl -LsSf https://astral.sh/uv/install.sh | sh
    
    if [ $extras == true ]; then
        apt install -y ripgrep

        yes | curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh | /bin/bash
        yes | brew install dust jless

        yes | curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        . "$HOME/.cargo/env" 
        yes | cargo install code2prompt
        yes | brew install peco

        apt install -y npm
        yes | npm i -g shell-ask
    fi

# Installing on mac with homebrew
elif [ $machine == "Mac" ]; then
    echo "Installing core packages..."
    brew install --quiet coreutils ncdu htop rsync btop jq 2>/dev/null || echo "Warning: Some packages may have failed to install"
    curl -LsSf https://astral.sh/uv/install.sh | sh

    DOT_DIR=$(dirname $(realpath $0))
    if [ $zsh == true ]; then
        echo "Installing ZSH..."
        brew install --quiet zsh 2>/dev/null || echo "Warning: ZSH installation failed"
    fi
    if [ $tmux == true ]; then
        echo "Installing tmux..."  
        brew install --quiet tmux 2>/dev/null || echo "Warning: tmux installation failed"
    fi

    if [ $extras == true ]; then
        echo "Installing extras..."
        brew install --quiet ripgrep dust jless peco 2>/dev/null || echo "Warning: Some extras failed to install"

        echo "Installing Rust..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --quiet
        . "$HOME/.cargo/env" 2>/dev/null || true
        cargo install code2prompt --quiet 2>/dev/null || echo "Warning: code2prompt installation failed"
    fi

    # macOS settings
    defaults write -g InitialKeyRepeat -int 10 2>/dev/null || true
    defaults write -g KeyRepeat -int 1 2>/dev/null || true  
    defaults write -g com.apple.mouse.scaling 5.0 2>/dev/null || true
    defaults write com.microsoft.VSCode ApplePressAndHoldEnabled -bool false 2>/dev/null || true
fi

# Setting up oh my zsh and oh my zsh plugins
ZSH=~/.oh-my-zsh
ZSH_CUSTOM=$ZSH/custom
if [ -d $ZSH ] && [ "$force" = "false" ]; then
    echo "Skipping download of oh-my-zsh and related plugins, pass --force to force redownload"
else
    echo "Installing oh-my-zsh and plugins..."
    rm -rf $ZSH
    
    echo "  → Installing oh-my-zsh..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

    echo "  → Installing powerlevel10k theme..."
    git clone --quiet https://github.com/romkatv/powerlevel10k.git \
        ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/themes/powerlevel10k 2>/dev/null || echo "Warning: powerlevel10k installation failed"

    echo "  → Installing zsh plugins..."
    git clone --quiet https://github.com/zsh-users/zsh-syntax-highlighting.git \
        ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting 2>/dev/null || echo "Warning: zsh-syntax-highlighting failed"

    git clone --quiet https://github.com/zsh-users/zsh-autosuggestions \
        ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions 2>/dev/null || echo "Warning: zsh-autosuggestions failed"

    git clone --quiet https://github.com/zsh-users/zsh-completions \
        ${ZSH_CUSTOM:=~/.oh-my-zsh/custom}/plugins/zsh-completions 2>/dev/null || echo "Warning: zsh-completions failed"

    git clone --quiet https://github.com/zsh-users/zsh-history-substring-search \
        ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-history-substring-search 2>/dev/null || echo "Warning: zsh-history-substring-search failed"
    
    echo "  → Installing tmux theme pack..."
    git clone --quiet https://github.com/jimeh/tmux-themepack.git ~/.tmux-themepack 2>/dev/null || echo "Warning: tmux-themepack failed"

    echo "✅ oh-my-zsh installation complete!"
    echo "Run ./deploy.sh to configure your dotfiles"
fi

if [ $extras == true ]; then
    echo " --------- INSTALLING EXTRAS ⏳ ----------- "
    if command -v cargo &> /dev/null; then
        NO_ASK_OPENAI_API_KEY=1 bash -c "$(curl -fsSL https://raw.githubusercontent.com/hmirin/ask.sh/main/install.sh)"
    fi
fi
