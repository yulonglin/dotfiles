#!/bin/bash
set -euo pipefail
USAGE=$(cat <<-END
    Usage: ./install.sh [OPTION]
    Install dotfile dependencies on mac or linux

    OPTIONS:
        --tmux          install tmux
        --zsh           install zsh
        --extras        install extra dependencies
        --ai-tools      install AI CLI tools (Claude Code, Gemini, Codex)
        --cleanup       install automatic cleanup for ~/Downloads and ~/Screenshots
        --experimental  install experimental features (ty type checker)
        --minimal       disable defaults, install only specified components

    DEFAULTS (applied unless --minimal is used):
        macOS:  --zsh --tmux --ai-tools --cleanup
        Linux:  --zsh --tmux --ai-tools

    EXAMPLES:
        ./install.sh                    # Install defaults
        ./install.sh --extras           # Install defaults + extras
        ./install.sh --minimal --tmux   # Install ONLY tmux (no defaults)
        ./install.sh --experimental     # Install defaults + ty type checker

    If OPTIONS are passed they will be installed
    with apt if on linux or brew if on OSX
END
)

zsh=false
tmux=false
extras=false
ai_tools=false
cleanup=false
experimental=false
force=false
minimal=false
while (( "$#" )); do
    case "$1" in
        -h|--help)
            echo "$USAGE" && exit 1 ;;
        --minimal)
            minimal=true && shift ;;
        --zsh)
            zsh=true && shift ;;
        --tmux)
            tmux=true && shift ;;
        --extras)
            extras=true && shift ;;
        --ai-tools)
            ai_tools=true && shift ;;
        --cleanup)
            cleanup=true && shift ;;
        --experimental)
            experimental=true && shift ;;
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

# Apply defaults unless --minimal was specified
if [ "$minimal" = false ]; then
    echo "Applying defaults for $machine (use --minimal to disable)..."
    zsh=true
    tmux=true
    ai_tools=true
    if [ "$machine" = "Mac" ]; then
        cleanup=true
    fi
fi

# Installing on linux with apt
if [ $machine == "Linux" ]; then
    DOT_DIR=$(dirname $(realpath $0))
    apt update -y 2>/dev/null || echo "Skipping apt update (no permissions)"
    
    # Try installing ZSH, fall back to local install if it fails
    if [ $zsh == true ]; then
        if ! command -v zsh &> /dev/null && [ ! -f "$HOME/local/bin/zsh" ]; then
            apt install -y zsh 2>/dev/null || {
                echo "apt install zsh failed, installing locally..."
                "$DOT_DIR/scripts/helpers/install_zsh_local.sh"
            }
        else
            echo "ZSH already installed"
        fi
    fi
    
    [ $tmux == true ] && apt install -y tmux 2>/dev/null || true
    apt install -y less nano htop ncdu nvtop lsof rsync jq fzf 2>/dev/null || true

    # Install atuin for unified shell history
    echo "Installing Atuin..."
    curl --proto '=https' --tlsv1.2 -LsSf https://setup.atuin.sh | sh 2>/dev/null || echo "Warning: Atuin installation failed"

    curl -LsSf https://astral.sh/uv/install.sh | sh
    
    if [ $extras == true ]; then
        apt install -y fd-find ripgrep 2>/dev/null || true

        # Install Homebrew for tools not in apt
        if ! command -v brew &> /dev/null; then
            yes | curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh | /bin/bash
        fi
        if command -v brew &> /dev/null; then
            brew install dust jless hyperfine lazygit 2>/dev/null || true
        fi

        # Install Rust and cargo tools
        if ! command -v cargo &> /dev/null; then
            yes | curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
            . "$HOME/.cargo/env"
        fi
        if command -v cargo &> /dev/null; then
            echo "Installing Rust CLI tools via cargo (fallback for no-sudo environments)..."
            cargo install bat eza zoxide delta code2prompt --locked 2>/dev/null || true
        fi

        apt install -y npm 2>/dev/null || true
        if command -v npm &> /dev/null; then
            npm i -g shell-ask 2>/dev/null || true
        fi
    fi

# Installing on mac with homebrew
elif [ $machine == "Mac" ]; then
    # Install Homebrew if not present
    if ! command -v brew &>/dev/null; then
        echo "Homebrew not found. Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

        # Add Homebrew to PATH for Apple Silicon Macs
        if [[ $(uname -m) == "arm64" ]]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
        fi
    fi

    # Install modern bash (macOS ships with bash 3.2 due to GPLv3 licensing)
    echo "Installing modern bash..."
    brew install --quiet bash 2>/dev/null || echo "Warning: bash installation failed"
    BREW_BASH="$(brew --prefix)/bin/bash"
    if [[ -x "$BREW_BASH" ]]; then
        echo "  ✓ Installed: $($BREW_BASH --version | head -1)"
        # Add to allowed shells if not already present
        if ! grep -qxF "$BREW_BASH" /etc/shells 2>/dev/null; then
            echo "  → To use as default shell, run:"
            echo "      sudo sh -c 'echo $BREW_BASH >> /etc/shells'"
            echo "      chsh -s $BREW_BASH"
        fi
    fi

    echo "Installing core packages..."
    brew install --quiet coreutils ncdu htop rsync btop jq fzf bat eza zoxide delta 2>/dev/null || echo "Warning: Some packages may have failed to install"

    # Install atuin for unified shell history
    echo "Installing Atuin..."
    brew install --quiet atuin 2>/dev/null || echo "Warning: Atuin installation failed"

    # Install Finicky (browser router)
    echo "Installing Finicky..."
    brew install --quiet --cask finicky 2>/dev/null || echo "Warning: Finicky installation failed"

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
        brew install --quiet fd ripgrep dust jless hyperfine lazygit 2>/dev/null || echo "Warning: Some extras failed to install"

        echo "Installing Rust..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --quiet
        . "$HOME/.cargo/env" 2>/dev/null || true
        cargo install code2prompt --quiet 2>/dev/null || echo "Warning: code2prompt installation failed"
    fi

    # macOS settings
    echo "Configuring macOS system defaults..."
    "$DOT_DIR/config/macos_settings.sh" || echo "Warning: macOS settings configuration had some errors"
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
    
    git clone --quiet https://github.com/jirutka/zsh-shift-select.git \
        "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-shift-select" 2>/dev/null || echo "Warning: zsh-shift-select installation failed"


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

# Install AI CLI tools
if [ "$ai_tools" = true ]; then
    echo "--------- INSTALLING AI CLI TOOLS 🤖 -----------"

    # Claude Code - native binary installation (recommended method for both platforms)
    echo "  → Installing Claude Code..."
    if command -v claude &>/dev/null; then
        CURRENT_VERSION=$(claude --version 2>/dev/null | grep -oP 'v?\K[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
        echo "    Claude Code already installed (version: $CURRENT_VERSION)"
        echo "    Auto-updates will handle future versions"
    else
        echo "    Installing Claude Code native binary..."
        curl -fsSL https://claude.ai/install.sh | bash

        # Check for Alpine Linux dependencies
        if [ "$machine" = "Linux" ] && command -v apk &>/dev/null; then
            echo "    Detected Alpine Linux - checking dependencies..."
            if ! apk info libgcc &>/dev/null || ! apk info libstdc++ &>/dev/null || ! apk info ripgrep &>/dev/null; then
                echo "    Installing required dependencies..."
                apk add libgcc libstdc++ ripgrep
                export USE_BUILTIN_RIPGREP=0
            fi
        fi
    fi

    # Verify Claude Code installation
    if command -v claude &>/dev/null; then
        echo "    ✓ Claude Code installed successfully"
        claude --version 2>/dev/null || true
    else
        echo "    ✗ Claude Code installation verification failed"
    fi

    # Ensure npm is available for other CLI tools
    if ! command -v npm &>/dev/null; then
        echo "  → Installing npm for additional CLI tools..."
        case "$machine" in
            Linux)
                apt install -y npm &>/dev/null || echo "Warning: npm installation via apt failed"
                ;;
            Mac)
                brew install --quiet node &>/dev/null || echo "Warning: node/npm installation via brew failed"
                ;;
        esac
    fi

    # Install other AI CLI tools
    echo "  → Installing additional AI CLI tools..."

    if [ "$machine" = "Mac" ] && command -v brew &>/dev/null; then
        # macOS: Use Homebrew for all CLI tools
        echo "    → Installing Gemini CLI..."
        brew install --quiet gemini-cli 2>/dev/null || echo "Warning: Gemini CLI installation failed"

        echo "    → Installing Codex CLI..."
        brew install --quiet codex 2>/dev/null || echo "Warning: Codex CLI installation failed"
    elif command -v npm &>/dev/null; then
        # Linux: Use npm if available
        echo "    → Installing Gemini CLI..."
        npm install -g @google/gemini-cli &>/dev/null || echo "Warning: Gemini CLI installation failed"

        echo "    → Installing Codex CLI..."
        npm install -g @openai/codex &>/dev/null || echo "Warning: Codex CLI installation failed"
    else
        echo "Warning: Neither Homebrew (macOS) nor npm (Linux) available for additional CLI tools"
    fi

    echo "✅ AI CLI tools installation complete!"
    echo ""

    # Configure MCP servers
    if command -v claude &>/dev/null; then
        echo "Configuring MCP servers..."

        echo "  → Adding context7 (documentation server)..."
        # Remove if exists, ignore errors
        claude mcp remove context7 &>/dev/null || true

        if [ -n "${CONTEXT7_API_KEY:-}" ]; then
            if claude mcp add --scope user --transport http context7 https://mcp.context7.com/mcp \
                --header "CONTEXT7_API_KEY: ${CONTEXT7_API_KEY}" 2>&1; then
                echo "    ✓ context7 configured with API key"
            else
                echo "    ✗ context7 installation failed"
            fi
        else
            if claude mcp add --scope user --transport http context7 https://mcp.context7.com/mcp 2>&1; then
                echo "    ✓ context7 configured (basic rate limits)"
                echo "    Note: Set CONTEXT7_API_KEY env var for higher limits"
                echo "    Get API key from: https://context7.com/api"
            else
                echo "    ✗ context7 installation failed"
            fi
        fi

        echo "  → Adding gitmcp (GitHub repo documentation)..."
        # Dynamic endpoint - trusted repos specified in ~/.claude/CLAUDE.md
        claude mcp remove gitmcp &>/dev/null || true
        if claude mcp add-json --scope user gitmcp '{"command":"npx","args":["mcp-remote","https://gitmcp.io/docs"]}' 2>&1; then
            echo "    ✓ gitmcp configured (see ~/.claude/CLAUDE.md for verified repos)"
        else
            echo "    ✗ gitmcp installation failed"
        fi

        echo ""
        echo "  MCP server configuration complete!"
        echo "  Run 'claude mcp list' to verify server health"
    else
        echo "NOTE: Claude Code not found - MCP servers not configured"
        echo "      Install Claude Code first, then run: claude mcp add <name> <url>"
    fi
fi

# Install cleanup automation if requested
if [ "$cleanup" = true ]; then
    echo ""
    echo "--------- INSTALLING AUTOMATIC CLEANUP 🧹 -----------"
    if [[ -f "$DOT_DIR/scripts/cleanup/install.sh" ]]; then
        "$DOT_DIR/scripts/cleanup/install.sh" --non-interactive || echo "Warning: Cleanup installation failed"
    else
        echo "Warning: Cleanup install script not found at $DOT_DIR/scripts/cleanup/install.sh"
        echo "Run ./deploy.sh --cleanup after deployment to enable automatic cleanup"
    fi
fi

# Install experimental features if requested
if [ "$experimental" = true ]; then
    echo ""
    echo "--------- INSTALLING EXPERIMENTAL FEATURES ⚗️  -----------"

    # ty type checker
    echo "  → Installing ty type checker..."
    echo "    WARNING: ty is in alpha/preview - not recommended for production"

    if command -v ty &>/dev/null; then
        TY_VERSION=$(ty --version 2>/dev/null || echo "unknown")
        echo "    ty already installed (version: $TY_VERSION)"
    else
        # Install using pip (works cross-platform)
        if command -v pip3 &>/dev/null; then
            echo "    Installing ty via pip3..."
            pip3 install ty --quiet 2>/dev/null || echo "    ✗ ty installation via pip3 failed"
        elif command -v pip &>/dev/null; then
            echo "    Installing ty via pip..."
            pip install ty --quiet 2>/dev/null || echo "    ✗ ty installation via pip failed"
        else
            echo "    ✗ pip not found - cannot install ty CLI"
        fi
    fi

    # Verify ty installation
    if command -v ty &>/dev/null; then
        echo "    ✓ ty installed successfully"
        ty --version 2>/dev/null || true
    else
        echo "    ✗ ty installation verification failed"
        echo "    Note: You can still use the VSCode extension without the CLI"
    fi

    echo ""
    echo "✅ Experimental features installation complete!"
    echo "   Run './deploy.sh --experimental' to deploy ty VSCode extension"
fi
