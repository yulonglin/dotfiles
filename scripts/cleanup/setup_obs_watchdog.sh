#!/bin/bash
# Setup the OBS watchdog (macOS only).
#
# On 2026-11-25 the Focusmate virtual camera froze twice while OBS kept
# rendering: display sleep stopped the screen-capture overlay, which OBS never
# restarts, and later the Studio Display Camera feed stalled silently. Both
# times the only fix used was quitting and relaunching OBS by hand.
#
# Runs every 20 seconds. Each run exits at once when OBS is not running;
# otherwise it presses the screen source's "Restart capture" button after a
# display-sleep stop, and restarts OBS (after saving a thread sample) when a
# camera frame stays bit-identical across three checks. Enables obs-websocket
# first, since that is how it talks to OBS. See custom_bins/obs-watchdog --help.
#
# Bash rather than zsh because it sources the bash scheduler library, like the
# other setup_*.sh scripts here.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=scripts/scheduler/scheduler.sh
source "$DOT_DIR/scripts/scheduler/scheduler.sh"

JOB_ID="obs-watchdog"
WATCHDOG="$DOT_DIR/custom_bins/obs-watchdog"
INTERVAL_SECONDS=20

log_step() { echo -e "${BLUE}==>${NC} $1"; }

uninstall() {
    unschedule "$JOB_ID" 2>/dev/null || true
}

install() {
    log_step "Setting up OBS watchdog..."

    if [[ "$(uname -s)" != "Darwin" ]]; then
        _sched_log_info "OBS watchdog is macOS-only. Skipping."
        return 0
    fi

    if [[ ! -f "$WATCHDOG" ]]; then
        _sched_log_warn "Watchdog not found at $WATCHDOG. Skipping."
        return 1
    fi

    chmod +x "$WATCHDOG"
    "$WATCHDOG" --setup
    schedule_interval "$JOB_ID" "$WATCHDOG" "$INTERVAL_SECONDS"
}

# Always uninstall first to ensure clean state
uninstall >/dev/null 2>&1 || true

# If only uninstalling, exit
if [[ "${1:-}" == "--uninstall" ]]; then
    _sched_log_info "OBS watchdog uninstalled."
    exit 0
fi

install
