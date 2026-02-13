#!/bin/bash
# Setup weekly system package auto-update
# macOS: brew (launchd), Linux: apt/dnf/pacman (cron)
# Runs every Sunday at 5:00 AM

set -euo pipefail

# Get directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
UPDATE_BIN="$DOT_DIR/custom_bins/update-packages"

# Source scheduler abstraction
source "$DOT_DIR/scripts/scheduler/scheduler.sh"

JOB_ID="update-packages"

# Logging (uses scheduler's internal prefix to avoid conflicts)
log_step() { echo -e "${BLUE}==>${NC} $1"; }

uninstall() {
    unschedule "$JOB_ID" 2>/dev/null || true
    # Clean up old brew-only job if it exists
    unschedule "update-brew" 2>/dev/null || true
}

install() {
    log_step "Setting up weekly package auto-update..."

    if [[ ! -f "$UPDATE_BIN" ]]; then
        _sched_log_warn "Binary not found at $UPDATE_BIN. Skipping."
        return 1
    fi

    # Sunday at 5:00 AM
    schedule_weekly "$JOB_ID" "$UPDATE_BIN" 0 5 0
}

# Always uninstall first to ensure clean state
uninstall >/dev/null 2>&1 || true

# If only uninstalling, exit
if [[ "${1:-}" == "--uninstall" ]]; then
    _sched_log_info "Package auto-update uninstalled."
    exit 0
fi

# Otherwise install
install
