#!/bin/bash
# Setup automatic secrets sync with GitHub gist
# Works on macOS (launchd) and Linux (cron)

set -euo pipefail

# Get directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
SYNC_BIN="$DOT_DIR/custom_bins/sync-secrets"

# Source scheduler abstraction
source "$DOT_DIR/scripts/scheduler/scheduler.sh"

JOB_ID="sync-secrets"

# Logging (uses scheduler's internal prefix to avoid conflicts)
log_step() { echo -e "${BLUE}==>${NC} $1"; }

uninstall() {
    unschedule "$JOB_ID" 2>/dev/null || true
}

install() {
    log_step "Setting up automated secrets sync..."

    if [[ ! -f "$SYNC_BIN" ]]; then
        _sched_log_warn "Binary not found at $SYNC_BIN. Skipping."
        return 1
    fi

    # Schedule daily at 8:00 AM (good time for secrets sync)
    schedule_daily "$JOB_ID" "$SYNC_BIN" 8 0
}

# Always uninstall first to ensure clean state
uninstall >/dev/null 2>&1 || true

# If only uninstalling, exit
if [[ "${1:-}" == "--uninstall" ]]; then
    _sched_log_info "Secrets sync automation uninstalled."
    exit 0
fi

# Otherwise install
install
