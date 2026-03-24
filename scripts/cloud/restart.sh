#!/bin/bash
# Quick restore after container restart
#
# RunPod containers lose /etc/passwd and /home on restart.
# This recreates the user, re-establishes symlinks to /workspace, and restores SSH.
#
# Usage:
#   ./restart.sh                         # Auto-detect provider
#   ./restart.sh dev                     # Custom username
#
# One-liner:
#   curl -fsSL https://raw.githubusercontent.com/yulonglin/dotfiles/main/scripts/cloud/restart.sh | bash

USERNAME="${1:-${USERNAME:-yulong}}"
USER_HOME="/home/$USERNAME"
GITHUB_USER="${GITHUB_USER:-yulonglin}"

echo "=== Restoring User ==="
echo "Username: $USERNAME"
echo "Home: $USER_HOME"

# Recreate user entry (lost on container restart)
useradd -m -d "$USER_HOME" -s /usr/bin/zsh "$USERNAME" 2>/dev/null || true
echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$USERNAME"

# Re-establish symlinks to persistent storage
if [[ -d /workspace ]]; then
    for dir in code .claude .local .config; do
        target="/workspace/$dir"
        link="$USER_HOME/$dir"
        [[ -d "$target" ]] || continue
        [[ -L "$link" ]] && continue
        rm -rf "$link" 2>/dev/null
        ln -sf "$target" "$link"
    done
fi

# Restore SSH access
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

# Fix ownership of home (local FS, chown works here)
chown -R "$USERNAME:$USERNAME" "$USER_HOME" 2>/dev/null || true

# Restart sshd (container restart may have stopped it)
service ssh restart 2>/dev/null || systemctl restart sshd 2>/dev/null || true
# Start cron (container restart stops it)
service cron start 2>/dev/null || true

echo ""
echo "=== User Restored ==="
echo "SSH with: ssh $USERNAME@<ip>"
echo "Switch:   su - $USERNAME"
