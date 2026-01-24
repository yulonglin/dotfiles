#!/bin/bash
# Cloud VM/container first-boot setup
# Works across providers: RunPod, Hetzner, etc.
#
# Usage:
#   ./setup.sh                           # Use defaults (RunPod-style)
#   PERSISTENT=/home ./setup.sh          # Custom persistent path (Hetzner)
#   USERNAME=dev ./setup.sh              # Custom username
#
# One-liner:
#   curl -fsSL https://raw.githubusercontent.com/yulonglin/dotfiles/main/scripts/cloud/setup.sh | bash

set -e

# ─── Configuration (override via env vars) ───────────────────────────────────
USERNAME="${USERNAME:-yulong}"
PERSISTENT="${PERSISTENT:-/workspace}"           # RunPod default
HOME_DIR="${HOME_DIR:-$PERSISTENT/$USERNAME}"    # /workspace/yulong
DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/yulonglin/dotfiles.git}"

echo "=== Cloud Setup ==="
echo "Username: $USERNAME"
echo "Home: $HOME_DIR"
echo ""

# ─── System deps ──────────────────────────────────────────────────────────────
echo "Installing system dependencies..."
apt-get update && apt-get install -y sudo zsh htop ncdu vim
command -v nvtop &>/dev/null || apt-get install -y nvtop 2>/dev/null || true

# ─── Create non-root user ─────────────────────────────────────────────────────
if ! id "$USERNAME" &>/dev/null; then
    echo "Creating user $USERNAME..."
    useradd -m -d "$HOME_DIR" -s /usr/bin/zsh "$USERNAME"
    echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$USERNAME"
else
    echo "User $USERNAME already exists"
fi

# ─── SSH keys (for direct SSH access as non-root) ────────────────────────────
if [ -d /root/.ssh ]; then
    echo "Copying SSH keys..."
    cp -r /root/.ssh "$HOME_DIR/" 2>/dev/null || true
    chown -R "$USERNAME:$USERNAME" "$HOME_DIR/.ssh"
    chmod 700 "$HOME_DIR/.ssh"
    chmod 600 "$HOME_DIR/.ssh/authorized_keys" 2>/dev/null || true
fi

# ─── Install uv (as user) ─────────────────────────────────────────────────────
echo "Installing uv..."
sudo -u "$USERNAME" -i bash -c 'curl -LsSf https://astral.sh/uv/install.sh | sh'

# ─── Clone dotfiles to ~/code/dotfiles ────────────────────────────────────────
DOTFILES="$HOME_DIR/code/dotfiles"
if [ ! -d "$DOTFILES" ]; then
    echo "Cloning dotfiles..."
    sudo -u "$USERNAME" mkdir -p "$HOME_DIR/code"
    sudo -u "$USERNAME" git clone "$DOTFILES_REPO" "$DOTFILES"
else
    echo "Dotfiles already exist at $DOTFILES"
fi

# ─── Run install and deploy as user ───────────────────────────────────────────
echo "Running install.sh..."
sudo -u "$USERNAME" -i bash -c "cd $DOTFILES && ./install.sh --zsh --tmux --ai-tools"

echo "Running deploy.sh..."
sudo -u "$USERNAME" -i bash -c "cd $DOTFILES && ./deploy.sh"

# ─── Authenticate gh if needed ────────────────────────────────────────────────
if ! sudo -u "$USERNAME" -i bash -c 'gh auth status' &>/dev/null; then
    echo "Authenticating GitHub CLI..."
    sudo -u "$USERNAME" -i bash -c 'gh auth login --web --git-protocol ssh'
fi

# ─── Install Claude Code as user ──────────────────────────────────────────────
echo "Installing Claude Code..."
sudo -u "$USERNAME" -i bash -c 'curl -fsSL https://claude.ai/install.sh | sh'

echo ""
echo "=== Setup Complete ==="
echo "SSH with: ssh $USERNAME@<ip>"
echo "Home: $HOME_DIR"
echo "Code: ~/code = $HOME_DIR/code"
