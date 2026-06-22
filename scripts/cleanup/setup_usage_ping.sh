#!/bin/bash
# Setup hourly usage-ping (keeps the Claude subscription 5-hour window warm).
# Works on macOS (launchd) and Linux (cron). Runs at :00 every hour.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
PING_BIN="$DOT_DIR/custom_bins/usage-ping"

source "$DOT_DIR/scripts/scheduler/scheduler.sh"

JOB_ID="usage-ping"

uninstall() { unschedule "$JOB_ID" 2>/dev/null || true; }

install() {
    if [[ ! -f "$PING_BIN" ]]; then
        _sched_log_warn "Binary not found at $PING_BIN. Skipping."
        return 1
    fi
    schedule_hourly "$JOB_ID" "$PING_BIN" 0
}

# Always uninstall first for clean state
uninstall >/dev/null 2>&1 || true

if [[ "${1:-}" == "--uninstall" ]]; then
    _sched_log_info "usage-ping uninstalled."
    exit 0
fi

install
