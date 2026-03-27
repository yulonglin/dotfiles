#!/bin/bash
# Setup scheduled WiFi hotspot deprioritization
# macOS only (launchd, hourly) — WiFi priority is a macOS concept
# Ensures iPhone hotspot stays at lowest WiFi priority

set -euo pipefail

# Get directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
BIN="$DOT_DIR/custom_bins/wifi-hotspot-deprioritize"

# Source scheduler abstraction
source "$DOT_DIR/scripts/scheduler/scheduler.sh"

JOB_ID="wifi-hotspot-deprioritize"
LABEL="com.user.$JOB_ID"

log_step() { echo -e "${BLUE}==>${NC} $1"; }

uninstall() {
    unschedule "$JOB_ID" 2>/dev/null || true
}

install() {
    if [[ "$(uname -s)" != "Darwin" ]]; then
        _sched_log_info "Skipping WiFi hotspot deprioritization (macOS only)"
        return 0
    fi

    log_step "Setting up hourly WiFi hotspot deprioritization..."

    if [[ ! -f "$BIN" ]]; then
        _sched_log_warn "Binary not found at $BIN. Skipping."
        return 1
    fi

    # schedule_daily doesn't support hourly — write plist directly
    # Omitting Hour key = runs every hour at Minute:30
    local log_file="$HOME/Library/Logs/$LABEL.log"
    local plist_file="$HOME/Library/LaunchAgents/$LABEL.plist"

    mkdir -p "$(dirname "$plist_file")"
    cat > "$plist_file" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$BIN</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Minute</key>
        <integer>30</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>$log_file</string>
    <key>StandardErrorPath</key>
    <string>$log_file</string>
</dict>
</plist>
EOF

    load_launchd "$plist_file"
    _sched_log_info "✅ Installed launchd agent (runs every hour at :30)"
}

# Always uninstall first to ensure clean state
uninstall >/dev/null 2>&1 || true

if [[ "${1:-}" == "--uninstall" ]]; then
    _sched_log_info "WiFi hotspot deprioritization uninstalled."
    exit 0
fi

install
