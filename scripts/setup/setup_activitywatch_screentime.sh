#!/usr/bin/env bash
# Install the LaunchAgent that streams iPhone/iPad Screen Time into ActivityWatch.
#
# Uses the official importer (github.com/ActivityWatch/aw-import-screentime), which
# reads ~/Library/Biome/streams/restricted/App.InFocus/remote/<device>/ and pushes
# per-device buckets (aw-import-screentime_ios_ios-<device_id>) to aw-server on :5600.
#
# Requirements: Screen Time "Share Across Devices" on both devices; Full Disk Access
# for the Python binary that launchd runs (printed at the end if the first run is denied).
set -euo pipefail

LABEL="com.yulonglin.aw-import-screentime"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
REPO="${AW_IMPORT_SCREENTIME_DIR:-$HOME/code/aw-import-screentime}"
REPO_URL="https://github.com/ActivityWatch/aw-import-screentime.git"
LOG_DIR="$HOME/Library/Logs/aw-import-screentime"

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
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    sed -n '2,9p' "$0"
    echo "Usage: $(basename "$0") [--uninstall]"
    exit 0
fi

[[ "$(uname -s)" == Darwin ]] || {
    echo "Screen Time import is macOS-only" >&2
    exit 1
}
UV="$(command -v uv || true)"
[[ -n "$UV" ]] || {
    echo "uv not found on PATH; install it first" >&2
    exit 1
}

if [[ ! -d "$REPO/.git" ]]; then
    git clone --quiet "$REPO_URL" "$REPO"
fi
(cd "$REPO" && "$UV" sync --quiet)

# Fail early, in the terminal, if Screen Time data is unreadable from here.
(cd "$REPO" && "$UV" run --no-sync aw-import-screentime devices >/dev/null) || {
    echo "Cannot read Screen Time data: grant Full Disk Access to this terminal, and check Share Across Devices" >&2
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
        <string>$UV</string>
        <string>run</string>
        <string>--no-sync</string>
        <string>--project</string>
        <string>$REPO</string>
        <string>aw-import-screentime</string>
        <string>watch</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
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
echo "Installed $LABEL (logs: $LOG_DIR)"
PYBIN="$(cd "$REPO" && "$UV" run --no-sync python -c 'import sys; print(sys.executable)')"
echo "If stderr.log shows 'Operation not permitted', add this binary to System Settings > Privacy & Security > Full Disk Access:"
echo "  $(readlink -f "$PYBIN")"
