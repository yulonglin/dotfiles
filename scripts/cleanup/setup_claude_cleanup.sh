#!/bin/bash
# Setup automatic clearing of idle Claude Code sessions
# Works on macOS (launchd) and Linux (cron)

set -euo pipefail

# Get directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
CLEAR_BIN="$DOT_DIR/custom_bins/clear-claude-code"

# Source scheduler abstraction
source "$DOT_DIR/scripts/scheduler/scheduler.sh"

JOB_ID="clear-claude-code"

# Logging (uses scheduler's internal prefix to avoid conflicts)
log_step() { echo -e "${BLUE}==>${NC} $1"; }

uninstall() {
    unschedule "$JOB_ID" 2>/dev/null || true
}

install() {
    log_step "Setting up Claude Code session cleanup..."

    if [[ ! -f "$CLEAR_BIN" ]]; then
        _sched_log_warn "Binary not found at $CLEAR_BIN. Skipping."
        return 1
    fi

    schedule_daily "$JOB_ID" "$CLEAR_BIN" 17 0
}

# Always uninstall first to ensure clean state
uninstall >/dev/null 2>&1 || true

# If only uninstalling, exit
if [[ "${1:-}" == "--uninstall" ]]; then
    _sched_log_info "Claude cleanup automation uninstalled."
    exit 0
fi

# Otherwise install
install
