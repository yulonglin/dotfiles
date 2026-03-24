#!/bin/bash
# Fix ownership issues after running things as root
# Run as root: sudo ./fix_permissions.sh

set -e

USERNAME="${USERNAME:-yulong}"

USER_HOME="/home/$USERNAME"

echo "=== Fixing Permissions ==="
echo "User: $USERNAME"
echo "Home: $USER_HOME"
echo ""

# Must run as root
if [[ "$(id -u)" -ne 0 ]]; then
    echo "Error: Run as root (sudo $0)"
    exit 1
fi

# Fix user home
if [[ -d "$USER_HOME" ]]; then
    echo "Fixing $USER_HOME..."
    chown -R "$USERNAME:$USERNAME" "$USER_HOME"
    chmod 755 "$USER_HOME"
fi

# Fix global npm if exists and has issues
if [[ -d /usr/local/lib/node_modules ]]; then
    echo "Fixing /usr/local/lib/node_modules..."
    chmod -R a+r /usr/local/lib/node_modules
fi

echo ""
echo "=== Done ==="
echo "Now login as: su - $USERNAME"
