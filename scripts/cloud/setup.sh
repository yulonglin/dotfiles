#!/bin/bash
# Cloud VM/container first-boot setup
# Auto-detects provider (RunPod, Hetzner, generic Linux)
#
# Usage:
#   ./setup.sh                           # Auto-detect provider
#   USER_HOME=/custom/path ./setup.sh    # Override home directory
#   USERNAME=dev ./setup.sh              # Custom username
#
# One-liner:
#   curl -fsSL https://raw.githubusercontent.com/yulonglin/dotfiles/main/scripts/cloud/setup.sh | bash

set -e

# ─── Configuration (override via env vars) ───────────────────────────────────
USERNAME="${USERNAME:-yulong}"
DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/yulonglin/dotfiles.git}"

# Auto-detect provider and set home directory
if [[ -n "$USER_HOME" ]]; then
    :  # explicitly provided, use as-is
elif [[ -d /workspace ]] || [[ -n "$RUNPOD_POD_ID" ]]; then
    USER_HOME="/workspace/$USERNAME"    # RunPod: persistent volume
else
    USER_HOME="/home/$USERNAME"         # Standard unix
fi

echo "=== Cloud Setup ==="
echo "Username: $USERNAME"
echo "Home: $USER_HOME"
echo ""

# ─── System deps ──────────────────────────────────────────────────────────────
echo "Installing system dependencies..."
apt-get update && apt-get install -y sudo zsh htop vim cron curl ca-certificates
command -v nvtop &>/dev/null || apt-get install -y nvtop 2>/dev/null || true
service cron start 2>/dev/null || true

# ─── Node 20 (for Gemini CLI) ─────────────────────────────────────────────────
if ! command -v node &>/dev/null || [[ "$(node -v | cut -d. -f1 | tr -d 'v')" -lt 20 ]]; then
    echo "Installing Node 20..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt-get install -y nodejs
fi

# ─── Create non-root user ─────────────────────────────────────────────────────
if ! id "$USERNAME" &>/dev/null; then
    echo "Creating user $USERNAME..."
    useradd -m -d "$USER_HOME" -s /usr/bin/zsh "$USERNAME"
    echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$USERNAME"
else
    echo "User $USERNAME already exists"
fi

# ─── Fix ownership & permissions of user's home (handles root-created files) ──
if [[ -d "$USER_HOME" ]]; then
    echo "Fixing ownership of $USER_HOME..."
    chown -R "$USERNAME:$USERNAME" "$USER_HOME"
    chmod 755 "$USER_HOME"  # sshd refuses key auth if home is group/world-writable
fi

# ─── SSH keys (for direct SSH access as non-root) ────────────────────────────
GITHUB_USER="${GITHUB_USER:-yulonglin}"
mkdir -p "$USER_HOME/.ssh"

# Try root's keys first, then fetch from GitHub
if [ -f /root/.ssh/authorized_keys ]; then
    echo "Copying SSH keys from root..."
    cp /root/.ssh/authorized_keys "$USER_HOME/.ssh/"
else
    echo "Fetching SSH keys from GitHub ($GITHUB_USER)..."
    curl -fsSL "https://github.com/$GITHUB_USER.keys" > "$USER_HOME/.ssh/authorized_keys"
fi

# Copy root's SSH config if it exists (e.g., provider-specific settings)
[ -f /root/.ssh/config ] && cp /root/.ssh/config "$USER_HOME/.ssh/" 2>/dev/null || true

chown -R "$USERNAME:$USERNAME" "$USER_HOME/.ssh"
chmod 700 "$USER_HOME/.ssh"
chmod 600 "$USER_HOME/.ssh/authorized_keys"

# ─── Bun (preferred for global CLI tools on Linux) ───────────────────────────
if ! command -v bun &>/dev/null; then
    echo "Installing bun..."
    sudo -u "$USERNAME" -i bash -c 'curl -fsSL https://bun.sh/install | bash'
fi

# ─── Install uv (as user) ─────────────────────────────────────────────────────
echo "Installing uv..."
sudo -u "$USERNAME" -i bash -c 'curl -LsSf https://astral.sh/uv/install.sh | sh'

# ─── Clone dotfiles to ~/code/dotfiles ────────────────────────────────────────
DOTFILES="$USER_HOME/code/dotfiles"
if [ ! -d "$DOTFILES" ]; then
    echo "Cloning dotfiles..."
    sudo -u "$USERNAME" mkdir -p "$USER_HOME/code"
    sudo -u "$USERNAME" git clone "$DOTFILES_REPO" "$DOTFILES"
else
    echo "Dotfiles already exist at $DOTFILES"
fi

# ─── Run install as user ─────────────────────────────────────────────────────
echo "Running install.sh..."
sudo -u "$USERNAME" -i bash -c "cd $DOTFILES && ./install.sh"

# ─── Authenticate gh (needed for gist secrets sync in deploy) ────────────────
if ! sudo -u "$USERNAME" -i bash -c 'gh auth status' &>/dev/null; then
    echo "Authenticating GitHub CLI..."
    sudo -u "$USERNAME" -i bash -c 'gh auth login --web --git-protocol ssh'
fi

# ─── Age key for SOPS secrets (paste from Bitwarden) ─────────────────────────
AGE_KEY_DIR="$USER_HOME/.config/sops/age"
if [ ! -f "$AGE_KEY_DIR/keys.txt" ]; then
    echo ""
    echo "Paste your age private key (from Bitwarden), then press Enter:"
    echo "(starts with AGE-SECRET-KEY-, leave empty to skip)"
    if [[ -e /dev/tty ]]; then
        read -rs AGE_KEY </dev/tty
    else
        echo "Non-interactive — skipping age key prompt. Paste after login with: secrets-init"
        AGE_KEY=""
    fi
    if [[ -n "$AGE_KEY" ]]; then
        sudo -u "$USERNAME" mkdir -p "$AGE_KEY_DIR"
        printf '%s\n' "$AGE_KEY" | sudo -u "$USERNAME" tee "$AGE_KEY_DIR/keys.txt" > /dev/null
        chmod 600 "$AGE_KEY_DIR/keys.txt"
        chown "$USERNAME:$USERNAME" "$AGE_KEY_DIR/keys.txt"
        echo "Age key saved."
    else
        echo "Skipping — run secrets-init after login to set up SOPS"
    fi
fi

# ─── Deploy configs (with secrets now available) ─────────────────────────────
echo "Running deploy.sh..."
sudo -u "$USERNAME" -i bash -c "cd $DOTFILES && ./deploy.sh"

# ─── Install Claude Code as user ──────────────────────────────────────────────
echo "Installing Claude Code..."
sudo -u "$USERNAME" -i bash -c 'curl -fsSL https://claude.ai/install.sh | sh'

echo ""
echo "=== Setup Complete ==="
echo "SSH with: ssh $USERNAME@<ip>"
echo "Home: $USER_HOME"
echo "Code: ~/code = $USER_HOME/code"
