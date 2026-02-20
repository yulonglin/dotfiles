#!/usr/bin/env bash
# Hook: Launch the session watchdog background process
# Event: SessionStart
# Reads session_id and transcript_path from stdin JSON

set -euo pipefail

# Read hook input
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)

if [[ -z "$SESSION_ID" || -z "$TRANSCRIPT_PATH" ]]; then
  exit 0
fi

# Check if watchdog is enabled (default: yes)
if [[ "${CLAUDE_WATCHDOG_ENABLED:-1}" == "0" ]]; then
  exit 0
fi

TMPDIR="${TMPDIR:-/tmp}"
PID_FILE="${TMPDIR}/claude-watchdog-${SESSION_ID}.pid"
HOOKS_DIR="$(cd "$(dirname "$0")" && pwd)"

# Kill any existing watchdog for this session (handles resume)
if [[ -f "$PID_FILE" ]]; then
  OLD_PID=$(cat "$PID_FILE" 2>/dev/null || true)
  if [[ -n "$OLD_PID" ]] && kill -0 "$OLD_PID" 2>/dev/null; then
    kill "$OLD_PID" 2>/dev/null || true
  fi
  rm -f "$PID_FILE"
fi

# Launch watchdog detached
nohup "$HOOKS_DIR/watchdog.sh" "$SESSION_ID" "$TRANSCRIPT_PATH" \
  >/dev/null 2>&1 &
disown

exit 0
