#!/usr/bin/env bash
# Hook: Kill the session watchdog and clean up temp files
# Event: SessionEnd

set -euo pipefail

# Read session_id from stdin JSON
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)

if [[ -z "$SESSION_ID" ]]; then
  exit 0
fi

TMPDIR="${TMPDIR:-/tmp}"
PID_FILE="${TMPDIR}/claude-watchdog-${SESSION_ID}.pid"
MARKER_FILE="${TMPDIR}/claude-watchdog-${SESSION_ID}.working"

# Kill watchdog process
if [[ -f "$PID_FILE" ]]; then
  PID=$(cat "$PID_FILE" 2>/dev/null || true)
  if [[ -n "$PID" ]] && kill -0 "$PID" 2>/dev/null; then
    kill "$PID" 2>/dev/null || true
  fi
  rm -f "$PID_FILE"
fi

# Clean up marker
rm -f "$MARKER_FILE"

exit 0
