#!/bin/bash
# Setup periodic hide-idle-apps polling (hide apps in [hide-idle] section after
# they've been not-frontmost for N minutes). macOS only. Runs every 60s.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
HIDE_BIN="$DOT_DIR/custom_bins/hide-idle-apps"

source "$DOT_DIR/scripts/scheduler/scheduler.sh"

JOB_ID="hide-idle-apps"
POLL_INTERVAL_SECONDS=60

uninstall() { unschedule "$JOB_ID" 2>/dev/null || true; }

install() {
    if [[ "$(uname -s)" != "Darwin" ]]; then
        _sched_log_info "hide-idle-apps is macOS-only. Skipping."
        return 0
    fi
    if [[ ! -f "$HIDE_BIN" ]]; then
        _sched_log_warn "Binary not found at $HIDE_BIN. Skipping."
        return 1
    fi
    schedule_interval "$JOB_ID" "$HIDE_BIN" "$POLL_INTERVAL_SECONDS"
}

# Always uninstall first for clean state
uninstall >/dev/null 2>&1 || true

if [[ "${1:-}" == "--uninstall" ]]; then
    _sched_log_info "hide-idle-apps uninstalled."
    exit 0
fi

install
