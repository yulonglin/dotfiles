#!/bin/bash
# Setup bedtime timezone enforcement daemon (macOS only)
# Requires sudo — installs a LaunchDaemon (runs as root)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

LABEL="com.user.enforce-timezone"
PLIST="/Library/LaunchDaemons/$LABEL.plist"
SRC="$DOT_DIR/custom_bins/enforce-timezone"
# Install to root-owned location — plist must not reference user-writable paths
INSTALLED_BIN="/usr/local/bin/enforce-timezone"

[[ "$(uname -s)" != "Darwin" ]] && exit 0

# Uninstall first (idempotent)
sudo launchctl unload "$PLIST" 2>/dev/null || true
[[ -f "$PLIST" ]] && sudo rm -f "$PLIST"

if [[ "${1:-}" == "--uninstall" ]]; then
    sudo rm -f "$INSTALLED_BIN"
    sudo rm -f /var/db/enforce-timezone.last /var/db/enforce-timezone.restarts /var/db/enforce-timezone.consistent
    echo "Bedtime timezone enforcement uninstalled."
    exit 0
fi

# Verify source exists
if [[ ! -f "$SRC" ]]; then
    echo "Warning: $SRC not found. Skipping." >&2
    exit 1
fi

# Copy script to root-owned location (not symlink — prevents user editing bypass)
sudo mkdir -p /usr/local/bin
sudo cp "$SRC" "$INSTALLED_BIN"
sudo chown root:wheel "$INSTALLED_BIN"
sudo chmod 755 "$INSTALLED_BIN"

# Install plist (LaunchDaemon — runs as root)
sudo tee "$PLIST" > /dev/null <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$INSTALLED_BIN</string>
    </array>
    <key>StartInterval</key>
    <integer>120</integer>
    <key>WatchPaths</key>
    <array>
        <string>/etc/localtime</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
EOF

sudo chown root:wheel "$PLIST"
sudo chmod 644 "$PLIST"
sudo launchctl load "$PLIST"
echo "Bedtime timezone enforcement installed (runs every 2 min + on TZ change)."
echo "Script installed to $INSTALLED_BIN (root-owned, update requires re-running setup)."
