#!/bin/bash
# Setup keyboard repeat enforcement at login (macOS only)
# Workaround for macOS Tahoe resetting keyboard repeat settings
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

LABEL="com.user.keyboard-repeat"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
BIN="$DOT_DIR/custom_bins/enforce-keyboard-repeat"

[[ "$(uname -s)" != "Darwin" ]] && exit 0

# Uninstall first (idempotent)
launchctl unload "$PLIST" 2>/dev/null || true
[[ -f "$PLIST" ]] && rm -f "$PLIST"

if [[ "${1:-}" == "--uninstall" ]]; then
    echo "Keyboard repeat enforcement uninstalled."
    exit 0
fi

# Verify binary exists
if [[ ! -f "$BIN" ]]; then
    echo "Warning: $BIN not found. Skipping." >&2
    exit 1
fi

# Install plist
mkdir -p "$(dirname "$PLIST")"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$BIN</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$HOME/Library/Logs/$LABEL.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/Library/Logs/$LABEL.log</string>
</dict>
</plist>
EOF

launchctl load "$PLIST"
echo "Keyboard repeat enforcement installed (runs at login)."
