#!/bin/bash
# Schedule the Claude Code plugin update checker to run daily.
# Usage:
#   ./install_plugin_check.sh           # install daily 09:00
#   ./install_plugin_check.sh --remove  # remove the schedule

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=../scheduler/scheduler.sh
source "$DOTFILES_ROOT/scripts/scheduler/scheduler.sh"

JOB_ID="claude-plugin-check"
COMMAND="$SCRIPT_DIR/plugin_update_check.py"

if [[ "${1:-}" == "--remove" ]]; then
    unschedule "$JOB_ID"
    _sched_log_info "✅ Removed $JOB_ID"
    exit 0
fi

if [[ ! -x "$COMMAND" ]]; then
    chmod +x "$COMMAND"
fi

# 09:00 daily — late enough that overnight upstream releases are visible,
# early enough to be in the report by the time the user starts their day.
schedule_daily "$JOB_ID" "$COMMAND" 9 0
