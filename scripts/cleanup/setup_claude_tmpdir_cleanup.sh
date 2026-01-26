#!/bin/bash
# Setup weekly cleanup of Claude Code tmpdir
# Works on macOS (launchd) and Linux (cron)

set -euo pipefail

# Get directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
CLEANUP_SCRIPT="$SCRIPT_DIR/cleanup_claude_tmpdir.sh"

# Source scheduler abstraction
source "$DOT_DIR/scripts/scheduler/scheduler.sh"

JOB_ID="cleanup-claude-tmpdir"

uninstall() {
    unschedule "$JOB_ID" 2>/dev/null || true
}

install() {
    echo -e "${BLUE}==>${NC} Setting up weekly Claude tmpdir cleanup..."

    if [[ ! -f "$CLEANUP_SCRIPT" ]]; then
        _sched_log_warn "Script not found at $CLEANUP_SCRIPT. Skipping."
        return 1
    fi

    # Schedule weekly on Sunday at 3:00 AM
    schedule_weekly "$JOB_ID" "$CLEANUP_SCRIPT" 0 3 0
}

# Always uninstall first to ensure clean state
uninstall >/dev/null 2>&1 || true

# If only uninstalling, exit
if [[ "${1:-}" == "--uninstall" ]]; then
    _sched_log_info "Claude tmpdir cleanup uninstalled."
    exit 0
fi

# Otherwise install
install
