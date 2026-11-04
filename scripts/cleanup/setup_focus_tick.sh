#!/usr/bin/env zsh
# Install the focus break-ending launchd job (macOS only).
#
# `focus break` stops a Cold Turkey mode and leaves a detached waiter to start it
# again. The waiter dies with a restart or a crash, and then the break never
# ends. This job runs `focus tick` every minute, which ends an overdue break and
# is otherwise silent. `focus install-agent` writes and loads the plist
# (com.yulonglin.focus.tick); `focus uninstall-agent` removes it.
#
#   setup_focus_tick.sh               install (or reinstall) the job
#   setup_focus_tick.sh --uninstall   remove it; quiet if it is not there
set -euo pipefail

DOT_DIR="${0:A:h:h:h}"
FOCUS="$DOT_DIR/custom_bins/focus"
NOTE="${FOCUS_CONFIG:-$HOME/vault/tooling/dotfiles/config/cold-turkey.md}"
CT_APP="/Applications/Cold Turkey Blocker.app"

[[ "$(uname -s)" == "Darwin" ]] || exit 0

if [[ ! -f "$FOCUS" ]]; then
  print -u2 "Warning: $FOCUS not found. Skipping."
  exit 1
fi

if [[ "${1:-}" == "--uninstall" ]]; then
  "$FOCUS" uninstall-agent
  exit 0
fi

if [[ ! -d "$CT_APP" ]]; then
  print "focus tick: Cold Turkey Blocker is not installed. Skipping."
  exit 0
fi
if [[ ! -f "$NOTE" ]]; then
  print "focus tick: config note $NOTE is missing. Skipping."
  exit 0
fi

# Pass the note explicitly, so the path checked above is the path the plist records.
"$FOCUS" --config "$NOTE" install-agent
