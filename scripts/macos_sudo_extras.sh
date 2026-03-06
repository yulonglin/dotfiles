#!/bin/bash
# macOS Sudo Extras
# Optional security hardening that requires elevated privileges.
# Run manually: sudo ./scripts/macos_sudo_extras.sh

set -e

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "This script is only for macOS. Skipping..."
    exit 0
fi

if [[ $EUID -ne 0 ]]; then
    echo "This script requires sudo. Run: sudo $0"
    exit 1
fi

echo "Applying macOS security hardening..."

# Enable firewall
echo "  → Enabling firewall..."
/usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on 2>/dev/null || true
/usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on 2>/dev/null || true

# Remove GarageBand (if installed)
if [[ -d "/Applications/GarageBand.app" ]]; then
    echo "  → Removing GarageBand..."
    if command -v trash &>/dev/null; then
        trash "/Applications/GarageBand.app" 2>/dev/null || rm -rf "/Applications/GarageBand.app"
    else
        rm -rf "/Applications/GarageBand.app"
    fi
fi

echo "✅ Security hardening complete!"
