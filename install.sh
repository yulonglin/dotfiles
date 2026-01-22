#!/bin/bash
set -euo pipefail
USAGE=$(cat <<-END
    Usage: ./install.sh [OPTION]
    Install dotfile dependencies on mac or linux

    OPTIONS:
        --tmux            install tmux
        --zsh             install zsh
        --extras          install extra CLI tools (dust, jless, hyperfine, lazygit, code2prompt)
        --ai-tools        install AI CLI tools (Claude Code, Gemini, Codex)
        --cleanup         install automatic cleanup for ~/Downloads and ~/Screenshots
        --experimental    install experimental features (ty type checker)
        --minimal         disable defaults, install only specified components
        --force-reinstall reinstall tools even if already present
        --create-user     create non-root user (name from config/user.conf, default: yulong)

    DEFAULTS (applied unless --minimal is used):
        macOS:  --zsh --tmux --ai-tools --cleanup
                + core tools via brew (bat, eza, zoxide, delta, fzf, jq)
        Linux:  --zsh --tmux --ai-tools --create-user
                + mise (universal tool manager)
                + modern CLI tools via mise (bat, eza, fd, ripgrep, delta, zoxide)

    EXAMPLES:
        ./install.sh                    # Install defaults
        ./install.sh --extras           # Install defaults + extras
        ./install.sh --minimal --tmux   # Install ONLY tmux (no defaults)
        ./install.sh --experimental     # Install defaults + ty type checker
END
)

zsh=false
tmux=false
extras=false
ai_tools=false
cleanup=false
experimental=false
force=false
force_reinstall=false
minimal=false
create_user=false
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
        --force-reinstall)
            force_reinstall=true && shift ;;
        --create-user)
            create_user=true && shift ;;
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

# Helper: Check if command exists, print "already installed" with version
is_installed() {
    local cmd="$1"
    local version_flag="${2:---version}"
    if [[ "$force_reinstall" = true ]]; then
        return 1
    fi
    if command -v "$cmd" &>/dev/null; then
        local version=$("$cmd" $version_flag 2>/dev/null | head -1 || echo "")
        if [[ -n "$version" ]]; then
            echo "  $cmd already installed ($version)"
        else
            echo "  $cmd already installed"
        fi
        return 0
    fi
    return 1
}

# Helper: Check if brew cask is installed
is_brew_cask_installed() {
    local cask="$1"
    if [[ "$force_reinstall" = true ]]; then
        return 1
    fi
    command -v brew &>/dev/null && brew list --cask "$cask" &>/dev/null
}

# Helper: Set ZSH as default shell if possible
set_zsh_default_shell() {
    [[ "$SHELL" == *"zsh"* ]] && return 0
    local zsh_path=$(which zsh 2>/dev/null)
    if [[ -x "$zsh_path" ]] && sudo -n true 2>/dev/null; then
        echo "Setting ZSH as default shell..."
        grep -qxF "$zsh_path" /etc/shells 2>/dev/null || echo "$zsh_path" | sudo tee -a /etc/shells >/dev/null
        chsh -s "$zsh_path"
        echo "  ✓ Default shell changed to ZSH"
    fi
}

# Helper: Clone a ZSH plugin
clone_zsh_plugin() {
    local repo="$1"
    local name="${2:-$(basename "$repo" .git)}"
    git clone --quiet "$repo" "${ZSH_CUSTOM}/plugins/$name" 2>/dev/null || echo "Warning: $name failed"
}

# Helper: Create non-root development user
create_dev_user() {
    # Requires root/sudo
    if [[ $EUID -ne 0 ]]; then
        echo "Skipping --create-user: not running as root"
        return 0
    fi

    # Load username from config, default to "yulong"
    local config_file="$(dirname "$0")/config/user.conf"
    local username="yulong"
    if [[ -f "$config_file" ]]; then
        source "$config_file"
        username="${DEV_USERNAME:-yulong}"
    fi

    # Idempotent: skip if user exists
    if id "$username" &>/dev/null; then
        echo "User $username already exists"
        return 0
    fi

    echo "Creating user: $username"
    local shell=$(command -v zsh || command -v bash)
    useradd -m -s "$shell" "$username"

    # Add to sudo group (wheel on some distros, sudo on Debian/Ubuntu)
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

    echo "User $username created. Switch with: su - $username"
}

# Helper: Install mise (universal version manager)
install_mise() {
    if is_installed mise; then
        return 0
    fi
    echo "Installing mise..."
    mkdir -p "$HOME/.local/bin"
    curl https://mise.run | sh
    export PATH="$HOME/.local/bin:$PATH"
    if command -v mise &>/dev/null; then
        eval "$(mise activate bash)"
        return 0
    fi
    echo "Warning: mise installation failed"
    return 1
}

# Helper: Install modern CLI tools via mise with fallbacks
install_cli_tools() {
    # Tools to install: bat, eza, fd, ripgrep, delta, zoxide

    # Try mise first (fastest - uses ubi backend for precompiled binaries)
    if command -v mise &>/dev/null; then
        echo "Installing CLI tools via mise..."
        # Use ubi backend for precompiled binaries (fastest)
        # zoxide needs cargo backend as ubi doesn't have it
        mise use -g \
            ubi:sharkdp/bat \
            ubi:eza-community/eza \
            ubi:sharkdp/fd \
            ubi:BurntSushi/ripgrep \
            ubi:dandavison/delta \
            cargo:zoxide 2>/dev/null || {
            echo "  Warning: Some mise installations failed, trying individual installs..."
            mise use -g ubi:sharkdp/bat 2>/dev/null || true
            mise use -g ubi:eza-community/eza 2>/dev/null || true
            mise use -g ubi:sharkdp/fd 2>/dev/null || true
            mise use -g ubi:BurntSushi/ripgrep 2>/dev/null || true
            mise use -g ubi:dandavison/delta 2>/dev/null || true
            mise use -g cargo:zoxide 2>/dev/null || true
        }
        return 0
    fi

    # Fallback: cargo-binstall (precompiled binaries, no compile time)
    if command -v cargo &>/dev/null; then
        if ! command -v cargo-binstall &>/dev/null; then
            echo "Installing cargo-binstall..."
            cargo install cargo-binstall --locked 2>/dev/null || {
                echo "Warning: cargo-binstall installation failed, using cargo install"
            }
        fi

        if command -v cargo-binstall &>/dev/null; then
            echo "Installing CLI tools via cargo-binstall..."
            cargo binstall -y bat eza fd-find ripgrep git-delta zoxide 2>/dev/null || true
            return 0
        fi

        # Final fallback: cargo install (compiles from source - slow)
        echo "Installing CLI tools via cargo (this may take a while)..."
        local cargo_flags="--locked"
        [[ "$force_reinstall" = true ]] && cargo_flags="--locked --force"
        for tool in bat eza zoxide git-delta; do
            if ! is_installed "$tool"; then
                cargo install "$tool" $cargo_flags 2>/dev/null || echo "  Warning: $tool installation failed"
            fi
        done
        return 0
    fi

    # Minimal fallback: apt for what's available
    echo "Installing CLI tools via apt (limited selection)..."
    apt install -y fd-find ripgrep 2>/dev/null || true
}

# Helper: Install extras CLI tools via mise
install_extras_cli_tools() {
    if command -v mise &>/dev/null; then
        echo "Installing extras CLI tools via mise..."
        mise use -g \
            ubi:bootandy/dust \
            ubi:PaulJuliusMartinez/jless \
            ubi:sharkdp/hyperfine \
            ubi:jesseduffield/lazygit \
            cargo:code2prompt 2>/dev/null || {
            echo "  Warning: Some extras installations failed, trying individual installs..."
            mise use -g ubi:bootandy/dust 2>/dev/null || true
            mise use -g ubi:PaulJuliusMartinez/jless 2>/dev/null || true
            mise use -g ubi:sharkdp/hyperfine 2>/dev/null || true
            mise use -g ubi:jesseduffield/lazygit 2>/dev/null || true
            mise use -g cargo:code2prompt 2>/dev/null || true
        }
        return 0
    fi
    return 1
}

# Script directory (portable, works without realpath)
DOT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Apply defaults unless --minimal was specified
if [ "$minimal" = false ]; then
    echo "Applying defaults for $machine (use --minimal to disable)..."
    zsh=true
    tmux=true
    ai_tools=true
    if [ "$machine" = "Mac" ]; then
        cleanup=true
    else
        create_user=true
    fi
fi

# Installing on linux with apt
if [ $machine == "Linux" ]; then
    apt update -y 2>/dev/null || echo "Skipping apt update (no permissions)"
    
    # Try installing ZSH, fall back to local install if it fails
    if [ $zsh == true ]; then
        if ! command -v zsh &> /dev/null && [ ! -f "$HOME/local/bin/zsh" ]; then
            apt install -y zsh 2>/dev/null || {
                echo "apt install zsh failed, installing locally..."
                "$DOT_DIR/scripts/helpers/install_zsh_local.sh"
            }
        else
            echo "  ZSH already installed"
        fi
        set_zsh_default_shell
    fi
    
    if [ $tmux == true ]; then
        if ! is_installed tmux; then
            echo "Installing tmux..."
            apt install -y tmux 2>/dev/null || true
        fi
    fi
    apt install -y less nano htop ncdu nvtop lsof rsync jq fzf 2>/dev/null || true

    # Install gitleaks for git hooks secret detection
    if ! is_installed gitleaks; then
        echo "Installing gitleaks..."
        apt install -y gitleaks 2>/dev/null || {
            # Fallback: download from GitHub releases
            echo "  apt install failed, downloading from GitHub..."
            GITLEAKS_VERSION=$(curl -s https://api.github.com/repos/gitleaks/gitleaks/releases/latest | grep -o '"tag_name": "v[^"]*' | cut -d'v' -f2 || echo "8.21.2")

            # Detect architecture
            ARCH=$(uname -m)
            case "$ARCH" in
                x86_64)  GITLEAKS_ARCH="x64" ;;
                aarch64) GITLEAKS_ARCH="arm64" ;;
                *)       echo "Warning: Unsupported architecture $ARCH for gitleaks"; GITLEAKS_ARCH="" ;;
            esac

            if [ -n "$GITLEAKS_ARCH" ]; then
                mkdir -p "$HOME/.local/bin"
                curl -sSL "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_${GITLEAKS_ARCH}.tar.gz" -o /tmp/gitleaks.tar.gz && \
                tar -xzf /tmp/gitleaks.tar.gz -C /tmp && \
                (mv /tmp/gitleaks /usr/local/bin/ 2>/dev/null || mv /tmp/gitleaks "$HOME/.local/bin/") && \
                rm -f /tmp/gitleaks.tar.gz || echo "Warning: Could not install gitleaks"
            fi
        }
    fi

    # Install atuin for unified shell history
    if ! is_installed atuin; then
        echo "Installing Atuin..."
        curl --proto '=https' --tlsv1.2 -LsSf https://setup.atuin.sh | sh 2>/dev/null || echo "Warning: Atuin installation failed"
    fi

    # Install uv (Python package manager)
    if ! is_installed uv; then
        echo "Installing uv..."
        curl -LsSf https://astral.sh/uv/install.sh | sh
    fi

    # Install mise (universal version manager - primary tool installer)
    install_mise

    # Install modern CLI tools (bat, eza, fd, ripgrep, delta, zoxide)
    echo "Installing modern CLI tools..."
    install_cli_tools

    if [ $extras == true ]; then
        echo "Installing extras CLI tools..."
        # Install extras via mise (dust, jless, hyperfine, lazygit, code2prompt)
        if ! install_extras_cli_tools; then
            echo "  Warning: mise not available, some extras may not be installed"
        fi

        # Install shell-ask via npm
        apt install -y npm 2>/dev/null || true
        if command -v npm &> /dev/null; then
            if ! is_installed ask; then
                echo "Installing shell-ask..."
                npm i -g shell-ask 2>/dev/null || true
            fi
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
    BREW_BASH="$(brew --prefix)/bin/bash"
    if [[ -x "$BREW_BASH" ]] && [[ "$force_reinstall" != true ]]; then
        echo "  bash already installed ($($BREW_BASH --version | head -1))"
    else
        echo "Installing modern bash..."
        brew install --quiet bash 2>/dev/null || echo "Warning: bash installation failed"
    fi
    if [[ -x "$BREW_BASH" ]]; then
        # Add to allowed shells if not already present
        if ! grep -qxF "$BREW_BASH" /etc/shells 2>/dev/null; then
            echo "  → To use as default shell, run:"
            echo "      sudo sh -c 'echo $BREW_BASH >> /etc/shells'"
            echo "      chsh -s $BREW_BASH"
        fi
    fi

    echo "Installing core packages..."
    brew install --quiet coreutils ncdu htop rsync btop jq fzf bat eza zoxide delta gitleaks 2>/dev/null || echo "Warning: Some packages may have failed to install"

    # Install atuin for unified shell history
    if ! is_installed atuin; then
        echo "Installing Atuin..."
        brew install --quiet atuin 2>/dev/null || echo "Warning: Atuin installation failed"
    fi

    # Install Finicky (browser router)
    if ! is_brew_cask_installed finicky; then
        echo "Installing Finicky..."
        brew install --quiet --cask finicky 2>/dev/null || echo "Warning: Finicky installation failed"
    else
        echo "  Finicky already installed"
    fi

    # Install uv (Python package manager)
    if ! is_installed uv; then
        echo "Installing uv..."
        curl -LsSf https://astral.sh/uv/install.sh | sh
    fi

    if [ $zsh == true ]; then
        if ! is_installed zsh; then
            echo "Installing ZSH..."
            brew install --quiet zsh 2>/dev/null || echo "Warning: ZSH installation failed"
        fi
        set_zsh_default_shell
    fi
    if [ $tmux == true ]; then
        if ! is_installed tmux; then
            echo "Installing tmux..."
            brew install --quiet tmux 2>/dev/null || echo "Warning: tmux installation failed"
        fi
    fi

    if [ $extras == true ]; then
        echo "Installing extras..."
        brew install --quiet fd ripgrep dust jless hyperfine lazygit 2>/dev/null || echo "Warning: Some extras failed to install"

        if ! is_installed cargo; then
            echo "Installing Rust..."
            curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --quiet
            . "$HOME/.cargo/env" 2>/dev/null || true
        fi
        if command -v cargo &>/dev/null; then
            if ! is_installed code2prompt; then
                echo "Installing code2prompt..."
                local cargo_flags="--quiet"
                [[ "$force_reinstall" = true ]] && cargo_flags="--quiet --force"
                cargo install code2prompt $cargo_flags 2>/dev/null || echo "Warning: code2prompt installation failed"
            fi
        fi
    fi

    # macOS settings
    echo "Configuring macOS system defaults..."
    "$DOT_DIR/config/macos_settings.sh" || echo "Warning: macOS settings configuration had some errors"
fi

# Setting up oh my zsh and oh my zsh plugins
ZSH=~/.oh-my-zsh
ZSH_CUSTOM=$ZSH/custom
if [ -d "$ZSH" ] && [ "$force" = "false" ] && [ "$force_reinstall" = "false" ]; then
    echo "Skipping oh-my-zsh (already installed, use --force-reinstall to reinstall)"
else
    echo "Installing oh-my-zsh and plugins..."
    rm -rf "$ZSH"

    echo "  → Installing oh-my-zsh..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

    echo "  → Installing powerlevel10k theme..."
    git clone --quiet https://github.com/romkatv/powerlevel10k.git \
        "${ZSH_CUSTOM}/themes/powerlevel10k" 2>/dev/null || echo "Warning: powerlevel10k failed"

    echo "  → Installing zsh plugins..."
    clone_zsh_plugin "https://github.com/zsh-users/zsh-syntax-highlighting.git"
    clone_zsh_plugin "https://github.com/zsh-users/zsh-autosuggestions"
    clone_zsh_plugin "https://github.com/zsh-users/zsh-completions"
    clone_zsh_plugin "https://github.com/zsh-users/zsh-history-substring-search"
    clone_zsh_plugin "https://github.com/jirutka/zsh-shift-select.git" "zsh-shift-select"

    echo "  → Installing tmux theme pack..."
    git clone --quiet https://github.com/jimeh/tmux-themepack.git ~/.tmux-themepack 2>/dev/null || echo "Warning: tmux-themepack failed"

    echo "✅ oh-my-zsh installation complete!"
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
    if ! is_installed claude; then
        echo "  → Installing Claude Code..."
        curl -fsSL https://claude.ai/install.sh | bash || echo "Warning: Claude Code installation failed"

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
        if ! is_installed gemini; then
            echo "    → Installing Gemini CLI..."
            brew install --quiet gemini-cli 2>/dev/null || echo "Warning: Gemini CLI installation failed"
        fi

        if ! is_installed codex; then
            echo "    → Installing Codex CLI..."
            brew install --quiet codex 2>/dev/null || echo "Warning: Codex CLI installation failed"
        fi
    elif command -v npm &>/dev/null; then
        # Linux: Use npm if available
        if ! is_installed gemini; then
            echo "    → Installing Gemini CLI..."
            npm install -g @google/gemini-cli &>/dev/null || echo "Warning: Gemini CLI installation failed"
        fi

        if ! is_installed codex; then
            echo "    → Installing Codex CLI..."
            npm install -g @openai/codex &>/dev/null || echo "Warning: Codex CLI installation failed"
        fi
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

    # ty type checker (installed globally via uv tool)
    echo "    WARNING: ty is in alpha/preview - not recommended for production"
    if ! is_installed ty; then
        if command -v uv &>/dev/null; then
            echo "  → Installing ty via uv..."
            uv tool install ty 2>/dev/null || echo "    ✗ ty installation via uv failed"
        else
            echo "    ✗ uv not found - cannot install ty CLI"
            echo "    Note: You can also install ty per-project with 'uv add ty --dev'"
        fi
    fi

    echo ""
    echo "✅ Experimental features installation complete!"
    echo "   Run './deploy.sh --experimental' to deploy ty VSCode extension"
fi

# Create non-root development user if requested
if [[ "$create_user" = true ]]; then
    create_dev_user
fi
