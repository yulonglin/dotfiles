#!/usr/bin/env zsh
# Install the weekly Things orphan check (macOS only).
#
# Every Sunday at 09:00, `things-orphans --notify` looks for open to-dos in
# Anytime or Someday that belong to no project or area. If it finds any, it adds
# one to-do for today that links each of them, so the weekly review files them.
# It is silent when there are none, and reads the Things database read-only.
#
#   setup_things_orphans.sh               install (or reinstall) the job
#   setup_things_orphans.sh --uninstall   remove it; quiet if it is not there
set -euo pipefail

DOT_DIR="${0:A:h:h:h}"
BIN="$DOT_DIR/custom_bins/things-orphans"
JOB_ID="things-orphans"

[[ "$(uname -s)" == "Darwin" ]] || exit 0

source "$DOT_DIR/scripts/scheduler/scheduler.sh"

unschedule "$JOB_ID" >/dev/null 2>&1 || true

if [[ "${1:-}" == "--uninstall" ]]; then
  _sched_log_info "things-orphans uninstalled."
  exit 0
fi

if [[ ! -x "$BIN" ]]; then
  _sched_log_warn "Binary not found at $BIN. Skipping."
  exit 1
fi

if [[ ! -d "/Applications/Things3.app" && ! -d "/Applications/Things.app" ]]; then
  _sched_log_info "things-orphans: Things 3 is not installed. Skipping."
  exit 0
fi

# Sunday (0) at 09:00, before the weekly review.
schedule_weekly "$JOB_ID" "$DOT_DIR/scripts/cleanup/things_orphans_notify.sh" 0 9 0
