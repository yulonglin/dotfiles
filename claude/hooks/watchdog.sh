#!/usr/bin/env bash
# Background watchdog: monitors Claude Code session for hangs
# Launched by watchdog_start.sh, killed by watchdog_stop.sh
#
# Usage: watchdog.sh <session_id> <transcript_path> [project_path] [claude_pid]
#
# Environment:
#   CLAUDE_WATCHDOG_TIMEOUT      - seconds before alerting (default: 600)
#   CLAUDE_WATCHDOG_INTERVAL     - check frequency in seconds (default: 60)
#   CLAUDE_WATCHDOG_MAX_LIFE     - max lifetime in seconds (default: 28800 = 8h)
#   CLAUDE_WATCHDOG_MEM_LIMIT_MB - RSS threshold for memory alerts (default: 4096)

set -uo pipefail

SESSION_ID="${1:-}"
TRANSCRIPT_PATH="${2:-}"
PROJECT_PATH="${3:-}"
CLAUDE_PID="${4:-}"

if [[ -z "$SESSION_ID" || -z "$TRANSCRIPT_PATH" ]]; then
  exit 1
fi

PROJECT_NAME="$(basename "${PROJECT_PATH:-unknown}")"

TIMEOUT="${CLAUDE_WATCHDOG_TIMEOUT:-600}"
INTERVAL="${CLAUDE_WATCHDOG_INTERVAL:-60}"
MAX_LIFE="${CLAUDE_WATCHDOG_MAX_LIFE:-28800}"
MEM_LIMIT_MB="${CLAUDE_WATCHDOG_MEM_LIMIT_MB:-4096}"
MEM_LIMIT_KB=$((MEM_LIMIT_MB * 1024))
TMPDIR="${TMPDIR:-/tmp}"

# Track whether we've already notified for this memory threshold crossing
MEM_NOTIFIED=false

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

# Send notification with project context
# Tries terminal-notifier (Ghostty-attributed), falls back to osascript
send_notification() {
  local msg="$1" project="$2" session="$3"
  if command -v terminal-notifier &>/dev/null; then
    terminal-notifier \
      -message "$msg" \
      -title "Claude Watchdog" \
      -subtitle "$project" \
      -sound "Submarine" \
      -sender com.mitchellh.ghostty \
      -group "claude-watchdog-${session}"
  elif [[ "$(uname)" == "Darwin" ]]; then
    osascript -e "display notification \"$msg\" with title \"Claude Watchdog\" subtitle \"$project\" sound name \"Submarine\"" 2>/dev/null || true
  fi
  # Terminal bell fallback
  printf '\a' 2>/dev/null || true
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

  # Memory monitoring: check RSS of the claude process
  if [[ -n "$CLAUDE_PID" ]] && kill -0 "$CLAUDE_PID" 2>/dev/null; then
    RSS_KB=$(ps -p "$CLAUDE_PID" -o rss= 2>/dev/null | tr -d ' ' || echo "0")
    if [[ -n "$RSS_KB" ]] && (( RSS_KB > MEM_LIMIT_KB )); then
      if [[ "$MEM_NOTIFIED" == "false" ]]; then
        RSS_MB=$((RSS_KB / 1024))
        send_notification "Memory: ${RSS_MB}MB (limit: ${MEM_LIMIT_MB}MB) — consider /compact or restart" "$PROJECT_NAME" "$SESSION_ID"
        MEM_NOTIFIED=true
      fi
    else
      # Reset notification flag if RSS drops below threshold (e.g., after /compact)
      MEM_NOTIFIED=false
    fi
  elif [[ -n "$CLAUDE_PID" ]] && ! kill -0 "$CLAUDE_PID" 2>/dev/null; then
    # Claude process died (likely OOM-killed) — notify and exit
    send_notification "Claude process (PID $CLAUDE_PID) died — possible OOM kill" "$PROJECT_NAME" "$SESSION_ID"
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
    send_notification \
      "No recent output for ${STALE_MIN}m — session may still be running or waiting" \
      "$PROJECT_NAME" "$SESSION_ID"
    LAST_NOTIFY=$NOW
  fi
done
