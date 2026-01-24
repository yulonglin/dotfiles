#!/bin/bash
# Fix ownership issues after running things as root
# Run as root: sudo ./fix_permissions.sh

set -e

USERNAME="${USERNAME:-yulong}"
PERSISTENT="${PERSISTENT:-/workspace}"
HOME_DIR="${HOME_DIR:-$PERSISTENT/$USERNAME}"

echo "=== Fixing Permissions ==="
echo "User: $USERNAME"
echo "Home: $HOME_DIR"
echo ""

# Must run as root
if [[ "$(id -u)" -ne 0 ]]; then
    echo "Error: Run as root (sudo $0)"
    exit 1
fi

# Fix user home
if [[ -d "$HOME_DIR" ]]; then
    echo "Fixing $HOME_DIR..."
    chown -R "$USERNAME:$USERNAME" "$HOME_DIR"
fi

# Fix global npm if exists and has issues
if [[ -d /usr/local/lib/node_modules ]]; then
    echo "Fixing /usr/local/lib/node_modules..."
    # Just ensure it's accessible, don't change ownership
    chmod -R a+r /usr/local/lib/node_modules
fi

echo ""
echo "=== Done ==="
echo "Now login as: su - $USERNAME"
