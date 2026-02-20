#!/usr/bin/env bash
# Background watchdog: monitors Claude Code session for hangs
# Launched by watchdog_start.sh, killed by watchdog_stop.sh
#
# Usage: watchdog.sh <session_id> <transcript_path> [project_path]
#
# Environment:
#   CLAUDE_WATCHDOG_TIMEOUT  - seconds before alerting (default: 600)
#   CLAUDE_WATCHDOG_INTERVAL - check frequency in seconds (default: 60)
#   CLAUDE_WATCHDOG_MAX_LIFE - max lifetime in seconds (default: 28800 = 8h)
#   ANTHROPIC_API_KEY        - enables Haiku triage to reduce false positives

set -uo pipefail

SESSION_ID="${1:-}"
TRANSCRIPT_PATH="${2:-}"
PROJECT_PATH="${3:-}"

if [[ -z "$SESSION_ID" || -z "$TRANSCRIPT_PATH" ]]; then
  exit 1
fi

PROJECT_NAME="$(basename "${PROJECT_PATH:-unknown}")"

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

# Ask Haiku whether the session is genuinely stuck
# Returns 0 (stuck) or 1 (not stuck). Falls through to 0 on any error.
triage_with_haiku() {
  local transcript_path="$1" stale_min="$2"

  # Gate: need API key
  if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
    return 0  # No key — assume stuck, notify
  fi

  # Read last ~8KB of transcript for context
  local context
  context=$(tail -c 8000 "$transcript_path" 2>/dev/null || true)
  if [[ -z "$context" ]]; then
    return 0
  fi

  # Escape for JSON embedding
  local escaped_context
  escaped_context=$(printf '%s' "$context" | jq -Rs '.')

  local escaped_prompt
  escaped_prompt=$(printf '%s' "The transcript has had no new output for ${stale_min} minutes. Based on the conversation, is the session stuck (e.g., error loop, hanging tool call, no progress) or not stuck (e.g., finished successfully, waiting for user input, completed its task)? Reply with exactly one word: STUCK or NOT_STUCK, followed by a brief reason (one sentence)." | jq -Rs '.')

  local response
  response=$(curl -s --max-time 10 \
    -H "x-api-key: ${ANTHROPIC_API_KEY}" \
    -H "anthropic-version: 2023-06-01" \
    -H "content-type: application/json" \
    -d "{
      \"model\": \"claude-haiku-4-5-20251001\",
      \"max_tokens\": 150,
      \"system\": \"You are a session health monitor. Analyze the Claude Code session transcript and determine if the session is stuck or not. Be concise.\",
      \"messages\": [{
        \"role\": \"user\",
        \"content\": [{\"type\": \"text\", \"text\": ${escaped_prompt}}, {\"type\": \"text\", \"text\": ${escaped_context}}]
      }]
    }" \
    "https://api.anthropic.com/v1/messages" 2>/dev/null)

  if [[ -z "$response" ]]; then
    return 0  # API failed — assume stuck
  fi

  local verdict
  verdict=$(printf '%s' "$response" | jq -r '.content[0].text // empty' 2>/dev/null)

  if [[ -z "$verdict" ]]; then
    return 0
  fi

  # Store reason for notification message
  TRIAGE_REASON=$(printf '%s' "$verdict" | sed 's/^[A-Z_]* *//')

  if [[ "$verdict" == NOT_STUCK* ]]; then
    return 1  # Not stuck — skip notification
  fi

  return 0  # Stuck or ambiguous — notify
}

TRIAGE_REASON=""

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
    TRIAGE_REASON=""

    # Haiku triage: check if actually stuck before notifying
    if triage_with_haiku "$TRANSCRIPT_PATH" "$STALE_MIN"; then
      # Stuck — send notification
      local_msg="No progress for ${STALE_MIN}m"
      if [[ -n "$TRIAGE_REASON" ]]; then
        local_msg="${local_msg} — ${TRIAGE_REASON}"
      else
        local_msg="${local_msg} — session may be stuck"
      fi
      send_notification "$local_msg" "$PROJECT_NAME" "$SESSION_ID"
      LAST_NOTIFY=$NOW
    fi
    # If not stuck, skip notification silently
  fi
done
