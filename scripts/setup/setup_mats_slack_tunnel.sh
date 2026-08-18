#!/usr/bin/env bash
# Install the persistent macOS job for the private MATS Slack MCP tunnel.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
LABEL="com.yulonglin.mats-slack-tunnel"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
TUNNEL_WRAPPER="$DOT_DIR/custom_bins/mats-slack-tunnel"
KEYCHAIN_HELPER_SRC="$DOT_DIR/tools/mats-slack-keychain/main.swift"
KEYCHAIN_HELPER_BIN="$DOT_DIR/tools/mats-slack-keychain/mats-slack-keychain"
LOG_DIR="$HOME/Library/Logs/mats-slack-tunnel"

uninstall() {
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
    if [[ -f "$PLIST" ]]; then
        mv "$PLIST" "$PLIST.disabled"
        echo "Moved the LaunchAgent to $PLIST.disabled"
    fi
}

if [[ "${1:-}" == "--uninstall" ]]; then
    uninstall
    exit 0
fi

[[ "$(uname -s)" == Darwin ]] || {
    echo "MATS Slack tunnel setup is macOS-only" >&2
    exit 1
}
[[ -f "$KEYCHAIN_HELPER_SRC" ]] || {
    echo "Missing Keychain helper source: $KEYCHAIN_HELPER_SRC" >&2
    exit 1
}
if [[ ! -x "$KEYCHAIN_HELPER_BIN" || "$KEYCHAIN_HELPER_SRC" -nt "$KEYCHAIN_HELPER_BIN" ]]; then
    swiftc -O -framework Security -o "$KEYCHAIN_HELPER_BIN" "$KEYCHAIN_HELPER_SRC"
fi
[[ -x "$TUNNEL_WRAPPER" ]] || {
    echo "Missing executable: $TUNNEL_WRAPPER" >&2
    exit 1
}
[[ -x "$HOME/.local/bin/tunnel-client" ]] || {
    echo "Install OpenAI tunnel-client at $HOME/.local/bin/tunnel-client first" >&2
    exit 1
}

mkdir -p "$(dirname "$PLIST")" "$LOG_DIR"

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$TUNNEL_WRAPPER</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
    <key>ThrottleInterval</key>
    <integer>60</integer>
    <key>StandardOutPath</key>
    <string>$LOG_DIR/stdout.log</string>
    <key>StandardErrorPath</key>
    <string>$LOG_DIR/stderr.log</string>
</dict>
</plist>
EOF

plutil -lint "$PLIST"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "Installed $LABEL"
