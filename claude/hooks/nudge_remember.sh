#!/usr/bin/env bash
# Hook: Nudge user to externalize session state (/remember) after extended use
# Event: Stop
# Triggers after TURN_THRESHOLD turns OR TIME_THRESHOLD_MIN minutes, whichever first
# After triggering, enters cooldown (COOLDOWN_TURNS) before nudging again

set -euo pipefail

TURN_THRESHOLD=20
TIME_THRESHOLD_MIN=45
COOLDOWN_TURNS=10

# Read session_id from stdin JSON
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
if [[ -z "$SESSION_ID" ]]; then
  exit 0
fi

STATE_FILE="${TMPDIR:-/tmp}/claude-remember-nudge-${SESSION_ID}"

# Initialize state file on first run
if [[ ! -f "$STATE_FILE" ]]; then
  printf '%s\n%s\n%s\n' "$(date +%s)" "0" "0" > "$STATE_FILE"
  exit 0
fi

# Read state: start_time, turn_count, last_nudge_turn
IFS=$'\n' read -r -d '' START_TIME TURN_COUNT LAST_NUDGE_TURN < "$STATE_FILE" || true
START_TIME="${START_TIME:-$(date +%s)}"
TURN_COUNT="${TURN_COUNT:-0}"
LAST_NUDGE_TURN="${LAST_NUDGE_TURN:-0}"

# Increment turn count
TURN_COUNT=$((TURN_COUNT + 1))

# Check cooldown
TURNS_SINCE_NUDGE=$((TURN_COUNT - LAST_NUDGE_TURN))
if [[ "$LAST_NUDGE_TURN" -gt 0 ]] && [[ "$TURNS_SINCE_NUDGE" -lt "$COOLDOWN_TURNS" ]]; then
  printf '%s\n%s\n%s\n' "$START_TIME" "$TURN_COUNT" "$LAST_NUDGE_TURN" > "$STATE_FILE"
  exit 0
fi

# Check thresholds
NOW=$(date +%s)
ELAPSED_MIN=$(( (NOW - START_TIME) / 60 ))
SHOULD_NUDGE=false

if [[ "$TURN_COUNT" -ge "$TURN_THRESHOLD" ]]; then
  SHOULD_NUDGE=true
fi

if [[ "$ELAPSED_MIN" -ge "$TIME_THRESHOLD_MIN" ]]; then
  SHOULD_NUDGE=true
fi

if [[ "$SHOULD_NUDGE" == "true" ]]; then
  # Update last nudge turn
  printf '%s\n%s\n%s\n' "$START_TIME" "$TURN_COUNT" "$TURN_COUNT" > "$STATE_FILE"

  # Return message to assistant (non-blocking nudge)
  cat <<'HOOK_EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "Stop",
    "message": "Session milestone: this session has been running for a while. Consider reminding the user to run /remember or externalize important state to files (plans/, CLAUDE.md learnings, specs/) before context gets too large to summarize well."
  }
}
HOOK_EOF
  exit 0
fi

# Update state without nudging
printf '%s\n%s\n%s\n' "$START_TIME" "$TURN_COUNT" "$LAST_NUDGE_TURN" > "$STATE_FILE"
exit 0
