#!/bin/bash
# Quick restore after container restart (user home already exists in persistent storage)
#
# RunPod containers lose /etc/passwd on restart, so we need to recreate the user entry.
# The home directory and all config persists in /workspace.
#
# Usage:
#   ./restart.sh                         # Use defaults
#   ./restart.sh dev                     # Custom username
#   ./restart.sh dev /data               # Custom username and path
#
# One-liner:
#   curl -fsSL https://raw.githubusercontent.com/yulonglin/dotfiles/main/scripts/cloud/restart.sh | bash

USERNAME="${1:-${USERNAME:-yulong}}"
PERSISTENT="${2:-${PERSISTENT:-/workspace}}"
HOME_DIR="$PERSISTENT/$USERNAME"

echo "=== Restoring User ==="
echo "Username: $USERNAME"
echo "Home: $HOME_DIR"

# Check home dir exists
if [ ! -d "$HOME_DIR" ]; then
    echo "Error: $HOME_DIR does not exist. Run setup.sh first."
    exit 1
fi

# Recreate user entry (home dir already exists)
useradd -d "$HOME_DIR" -s /usr/bin/zsh "$USERNAME" 2>/dev/null || true
echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$USERNAME"

# Restore SSH access (RunPod injects keys to root on each start)
if [ -d /root/.ssh ]; then
    cp -r /root/.ssh "$HOME_DIR/" 2>/dev/null || true
    chown -R "$USERNAME:$USERNAME" "$HOME_DIR/.ssh"
fi

echo ""
echo "=== User Restored ==="
echo "SSH with: ssh $USERNAME@<ip>"
