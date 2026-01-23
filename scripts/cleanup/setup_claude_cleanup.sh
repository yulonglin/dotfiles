#!/bin/bash
# Setup automatic clearing of idle Claude Code sessions
# Works on macOS (launchd) and Linux (cron)

set -euo pipefail

# Get directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
CLEAR_BIN="$DOT_DIR/custom_bins/clear-claude-code"

# Configuration
LABEL="com.user.clear-claude-code"
PLIST_FILE="$HOME/Library/LaunchAgents/$LABEL.plist"

if [[ "$(uname -s)" == "Darwin" ]]; then
    LOG_FILE="$HOME/Library/Logs/$LABEL.log"
else
    LOG_FILE="$HOME/.clear-claude-code-cron.log"
fi

# Color output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_step() { echo -e "${BLUE}==>${NC} $1"; }

uninstall() {
    # Remove macOS LaunchAgent
    if [[ "$(uname -s)" == "Darwin" ]]; then
        if [[ -f "$PLIST_FILE" ]]; then
            launchctl unload "$PLIST_FILE" 2>/dev/null || true
            rm -f "$PLIST_FILE"
            log_info "Removed launchd agent: $PLIST_FILE"
        fi
    fi

    # Remove Linux Cron job
    if crontab -l 2>/dev/null | grep -q "clear-claude-code"; then
        crontab -l 2>/dev/null | grep -v "clear-claude-code" | crontab -
        log_info "Removed cron job"
    fi
}

install() {
    log_step "Setting up Claude Code session cleanup..."
    
    if [[ ! -f "$CLEAR_BIN" ]]; then
        log_warn "Binary not found at $CLEAR_BIN. Skipping."
        return 1
    fi

    if [[ "$(uname -s)" == "Darwin" ]]; then
        mkdir -p "$(dirname "$PLIST_FILE")"
        cat > "$PLIST_FILE" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$CLEAR_BIN</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>4</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>$LOG_FILE</string>
    <key>StandardErrorPath</key>
    <string>$LOG_FILE</string>
</dict>
</plist>
EOF
        launchctl unload "$PLIST_FILE" 2>/dev/null || true
        launchctl load "$PLIST_FILE"
        log_info "✅ Installed launchd agent (runs daily at 04:00)"
    elif [[ "$(uname -s)" == "Linux" ]]; then
        # Add new cron job (uninstall handled cleanup)
        (crontab -l 2>/dev/null; echo "0 4 * * * $CLEAR_BIN >> $LOG_FILE 2>&1") | crontab -
        log_info "✅ Installed cron job (runs daily at 04:00)"
    fi
}

# Always uninstall first to ensure clean state
uninstall >/dev/null 2>&1 || true

# If only uninstalling, exit
if [[ "${1:-}" == "--uninstall" ]]; then
    log_info "Claude cleanup automation uninstalled."
    exit 0
fi

# Otherwise install
install
