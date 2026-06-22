#!/bin/bash
# Setup hourly tmux-resume (auto-resume rate-limited Claude/Codex tmux sessions).
# Works on macOS (launchd) and Linux (cron). Runs at :05 every hour.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
RESUME_BIN="$DOT_DIR/custom_bins/tmux-resume"

source "$DOT_DIR/scripts/scheduler/scheduler.sh"

JOB_ID="tmux-resume"

uninstall() { unschedule "$JOB_ID" 2>/dev/null || true; }

install() {
    if [[ ! -f "$RESUME_BIN" ]]; then
        _sched_log_warn "Binary not found at $RESUME_BIN. Skipping."
        return 1
    fi
    schedule_hourly "$JOB_ID" "$RESUME_BIN" 5
}

# Always uninstall first for clean state
uninstall >/dev/null 2>&1 || true

if [[ "${1:-}" == "--uninstall" ]]; then
    _sched_log_info "tmux-resume uninstalled."
    exit 0
fi

install
