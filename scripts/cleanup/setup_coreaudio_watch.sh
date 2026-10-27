#!/bin/bash
# Setup the CoreAudio wedge watcher (macOS only).
#
# A wedged coreaudiod hangs every app that touches audio while CPU, memory and
# the network all look healthy, so it gets mistaken for something else. On
# 2026-10-26 Telegram hung on every launch for two hours, and the hang reports
# naming "Deadlock: coreaudiod" sat unread the whole time.
#
# Runs every 2 minutes. The watcher reads new crash and hang reports, and probes
# CoreAudio only when one points at it, while it is already wedged, or every 15
# minutes as a backstop. It posts a notification on wedge and on recovery. See
# custom_bins/coreaudio-watch --help and docs/macos-media-wedge.md.
#
# Bash rather than zsh because it sources the bash scheduler library, like the
# other setup_*.sh scripts here.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=scripts/scheduler/scheduler.sh
source "$DOT_DIR/scripts/scheduler/scheduler.sh"

JOB_ID="coreaudio-watch"
WATCHER="$DOT_DIR/custom_bins/coreaudio-watch"
INTERVAL_SECONDS=120

log_step() { echo -e "${BLUE}==>${NC} $1"; }

uninstall() {
    unschedule "$JOB_ID" 2>/dev/null || true
}

install() {
    log_step "Setting up CoreAudio wedge watcher..."

    if [[ "$(uname -s)" != "Darwin" ]]; then
        _sched_log_info "CoreAudio is macOS-only. Skipping."
        return 0
    fi

    if [[ ! -f "$WATCHER" ]]; then
        _sched_log_warn "Watcher not found at $WATCHER. Skipping."
        return 1
    fi

    chmod +x "$WATCHER"
    schedule_interval "$JOB_ID" "$WATCHER" "$INTERVAL_SECONDS"
}

# Always uninstall first to ensure clean state
uninstall >/dev/null 2>&1 || true

# If only uninstalling, exit
if [[ "${1:-}" == "--uninstall" ]]; then
    _sched_log_info "CoreAudio wedge watcher uninstalled."
    exit 0
fi

install
