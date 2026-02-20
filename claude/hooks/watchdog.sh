#!/usr/bin/env bash
# Background watchdog: monitors Claude Code session for hangs
# Launched by watchdog_start.sh, killed by watchdog_stop.sh
#
# Usage: watchdog.sh <session_id> <transcript_path>
#
# Environment:
#   CLAUDE_WATCHDOG_TIMEOUT  - seconds before alerting (default: 600)
#   CLAUDE_WATCHDOG_INTERVAL - check frequency in seconds (default: 60)
#   CLAUDE_WATCHDOG_MAX_LIFE - max lifetime in seconds (default: 28800 = 8h)

set -uo pipefail

SESSION_ID="${1:-}"
TRANSCRIPT_PATH="${2:-}"

if [[ -z "$SESSION_ID" || -z "$TRANSCRIPT_PATH" ]]; then
  exit 1
fi

TIMEOUT="${CLAUDE_WATCHDOG_TIMEOUT:-600}"
INTERVAL="${CLAUDE_WATCHDOG_INTERVAL:-60}"
MAX_LIFE="${CLAUDE_WATCHDOG_MAX_LIFE:-28800}"
TMPDIR="${TMPDIR:-/tmp}"

PID_FILE="${TMPDIR}/claude-watchdog-${SESSION_ID}.pid"
MARKER_FILE="${TMPDIR}/claude-watchdog-${SESSION_ID}.working"

# Write PID file
echo $$ > "$PID_FILE"

# Cleanup on exit
cleanup() {
  rm -f "$PID_FILE"
}
trap cleanup EXIT

START_TIME=$(date +%s)
LAST_NOTIFY=0

# Cross-platform file mtime (epoch seconds)
file_mtime() {
  local f="$1"
  if [[ "$(uname)" == "Darwin" ]]; then
    stat -f "%m" "$f" 2>/dev/null || echo 0
  else
    stat -c "%Y" "$f" 2>/dev/null || echo 0
  fi
}

while true; do
  sleep "$INTERVAL"

  NOW=$(date +%s)

  # Exit if max lifetime exceeded
  if (( NOW - START_TIME > MAX_LIFE )); then
    break
  fi

  # Exit if transcript file is gone (session ended without cleanup)
  if [[ ! -f "$TRANSCRIPT_PATH" ]]; then
    break
  fi

  # Skip if not in working state
  if [[ ! -f "$MARKER_FILE" ]]; then
    continue
  fi

  # Check transcript staleness
  MTIME=$(file_mtime "$TRANSCRIPT_PATH")
  STALE_SECONDS=$(( NOW - MTIME ))

  if (( STALE_SECONDS >= TIMEOUT )); then
    # Don't spam — cooldown period after each notification
    if (( NOW - LAST_NOTIFY < TIMEOUT )); then
      continue
    fi

    STALE_MIN=$(( STALE_SECONDS / 60 ))

    # macOS notification
    if [[ "$(uname)" == "Darwin" ]]; then
      osascript -e "display notification \"No progress for ${STALE_MIN}m — session may be stuck\" with title \"Claude Code Watchdog\" sound name \"Submarine\"" 2>/dev/null || true
    fi

    # Terminal bell (works on most terminals)
    printf '\a' 2>/dev/null || true

    LAST_NOTIFY=$NOW
  fi
done
