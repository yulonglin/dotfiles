#!/bin/bash
# Quick restore after container restart (user home already exists in persistent storage)
#
# RunPod containers lose /etc/passwd on restart, so we need to recreate the user entry.
# The home directory and all config persists in persistent storage.
#
# Usage:
#   ./restart.sh                         # Auto-detect provider
#   ./restart.sh dev                     # Custom username
#
# One-liner:
#   curl -fsSL https://raw.githubusercontent.com/yulonglin/dotfiles/main/scripts/cloud/restart.sh | bash

USERNAME="${1:-${USERNAME:-yulong}}"

# Auto-detect provider (same logic as setup.sh)
if [[ -n "$USER_HOME" ]]; then
    :
elif [[ -d /workspace ]] || [[ -n "$RUNPOD_POD_ID" ]]; then
    USER_HOME="/workspace/$USERNAME"
else
    USER_HOME="/home/$USERNAME"
fi

echo "=== Restoring User ==="
echo "Username: $USERNAME"
echo "Home: $USER_HOME"

# Check home dir exists
if [ ! -d "$USER_HOME" ]; then
    echo "Error: $USER_HOME does not exist. Run setup.sh first."
    exit 1
fi

# Recreate user entry (home dir already exists)
useradd -d "$USER_HOME" -s /usr/bin/zsh "$USERNAME" 2>/dev/null || true
echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$USERNAME"

# Restore SSH access
GITHUB_USER="${GITHUB_USER:-yulonglin}"
mkdir -p "$USER_HOME/.ssh"
if [ -f /root/.ssh/authorized_keys ]; then
    cp /root/.ssh/authorized_keys "$USER_HOME/.ssh/"
else
    curl -fsSL "https://github.com/$GITHUB_USER.keys" > "$USER_HOME/.ssh/authorized_keys"
fi
[ -f /root/.ssh/config ] && cp /root/.ssh/config "$USER_HOME/.ssh/" 2>/dev/null || true
chown -R "$USERNAME:$USERNAME" "$USER_HOME/.ssh"
chmod 700 "$USER_HOME/.ssh"
chmod 600 "$USER_HOME/.ssh/authorized_keys"
chmod 755 "$USER_HOME"  # sshd refuses key auth if home is group/world-writable

echo ""
echo "=== User Restored ==="
echo "SSH with: ssh $USERNAME@<ip>"
