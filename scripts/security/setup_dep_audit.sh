#!/bin/bash
# Setup weekly dependency audit
# Runs every Sunday at 10:00 AM
set -euo pipefail

# Get directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
AUDIT_BIN="$DOT_DIR/scripts/security/audit_dependencies.sh"

# Source scheduler abstraction
source "$DOT_DIR/scripts/scheduler/scheduler.sh"

JOB_ID="dep-audit"

# Logging (uses scheduler's internal prefix to avoid conflicts)
log_step() { echo -e "${BLUE}==>${NC} $1"; }

uninstall() {
    unschedule "$JOB_ID" 2>/dev/null || true
}

install() {
    log_step "Setting up weekly dependency audit..."

    if [[ ! -f "$AUDIT_BIN" ]]; then
        _sched_log_warn "Binary not found at $AUDIT_BIN. Skipping."
        return 1
    fi

    # Sunday at 10:00 AM
    schedule_weekly "$JOB_ID" "$AUDIT_BIN" 0 10 0
}

# Always uninstall first to ensure clean state
uninstall >/dev/null 2>&1 || true

# If only uninstalling, exit
if [[ "${1:-}" == "--uninstall" ]]; then
    _sched_log_info "Dependency audit uninstalled."
    exit 0
fi

# Otherwise install
install
