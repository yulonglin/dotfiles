#!/bin/bash
# Setup the Alfred workflow watchdog (macOS only).
#
# Alfred script filters fire per keystroke and should finish in milliseconds. A
# buggy one can hang forever: on 2026-09-12 two `osascript` runs of the Open
# Conference URL workflow spun at 100% CPU for 18 hours each — ~19 core-hours —
# and surfaced only as "Alfred is using significant energy", because macOS bills
# a child's energy to the parent app. Nothing on the machine noticed.
#
# Runs every 5 minutes. The watchdog only kills a process that is BOTH old and
# pegged on two samples, so blocked `display dialog` prompts (0% CPU) and slow
# polling loops are left alone. See custom_bins/alfred-watchdog --help.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=scripts/scheduler/scheduler.sh
source "$DOT_DIR/scripts/scheduler/scheduler.sh"

JOB_ID="alfred-watchdog"
WATCHDOG="$DOT_DIR/custom_bins/alfred-watchdog"
INTERVAL_SECONDS=300

log_step() { echo -e "${BLUE}==>${NC} $1"; }

uninstall() {
    unschedule "$JOB_ID" 2>/dev/null || true
}

install() {
    log_step "Setting up Alfred workflow watchdog..."

    if [[ "$(uname -s)" != "Darwin" ]]; then
        _sched_log_info "Alfred is macOS-only. Skipping."
        return 0
    fi

    if [[ ! -f "$WATCHDOG" ]]; then
        _sched_log_warn "Watchdog not found at $WATCHDOG. Skipping."
        return 1
    fi

    chmod +x "$WATCHDOG"
    schedule_interval "$JOB_ID" "$WATCHDOG" "$INTERVAL_SECONDS"
}

# Always uninstall first to ensure clean state
uninstall >/dev/null 2>&1 || true

# If only uninstalling, exit
if [[ "${1:-}" == "--uninstall" ]]; then
    _sched_log_info "Alfred workflow watchdog uninstalled."
    exit 0
fi

install
