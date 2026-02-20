#!/usr/bin/env bash
# Hook: Toggle working/idle state marker for the session watchdog
# Events: UserPromptSubmit (working), Stop (idle)
# Usage: watchdog_mark.sh working|idle

set -euo pipefail

STATE="${1:-}"
if [[ -z "$STATE" ]]; then
  exit 0
fi

# Read session_id from stdin JSON
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
if [[ -z "$SESSION_ID" ]]; then
  exit 0
fi

MARKER="${TMPDIR:-/tmp}/claude-watchdog-${SESSION_ID}.working"

case "$STATE" in
  working)
    touch "$MARKER"
    ;;
  idle)
    rm -f "$MARKER"
    ;;
esac

exit 0
