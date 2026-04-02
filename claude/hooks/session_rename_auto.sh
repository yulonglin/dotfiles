#!/usr/bin/env bash
# Hook: Auto-rename terminal/tmux window based on session content
# Event: Stop
# Triggers ONCE at turn 3, calls Haiku async to generate a descriptive name,
# then sets terminal title (OSC) and tmux window name.

set -euo pipefail

TRIGGER_TURN=3
MODEL="claude-haiku-4-5-20251001"
MAX_TOKENS=30
TRANSCRIPT_HEAD_LINES=30

# Read session_id and transcript_path from stdin JSON
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
if [[ -z "$SESSION_ID" ]]; then
  exit 0
fi

STATE_FILE="${TMPDIR:-/tmp}/claude-rename-auto-${SESSION_ID}"

# Initialize state file on first run (turn 0 = not yet counted)
if [[ ! -f "$STATE_FILE" ]]; then
  printf '%s\n' "0" > "$STATE_FILE"
  exit 0
fi

# Read current turn count
TURN_COUNT=$(cat "$STATE_FILE")

# -1 means already triggered — never fire again
if [[ "$TURN_COUNT" == "-1" ]]; then
  exit 0
fi

# Increment turn count
TURN_COUNT=$((TURN_COUNT + 1))

# Only trigger at exactly turn 3
if [[ "$TURN_COUNT" -lt "$TRIGGER_TURN" ]]; then
  printf '%s\n' "$TURN_COUNT" > "$STATE_FILE"
  exit 0
fi

# At turn 3: mark as triggered (prevent future runs)
printf '%s\n' "-1" > "$STATE_FILE"

# Check prerequisites
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
if [[ -z "$TRANSCRIPT_PATH" ]] || [[ ! -f "$TRANSCRIPT_PATH" ]]; then
  exit 0
fi
if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
  exit 0
fi

# --- Async Haiku call in background subshell ---
# shellcheck disable=SC2030,SC2031
(
  # Extract user messages from first ~TRANSCRIPT_HEAD_LINES of transcript
  # Session name should reflect what the USER is working on, not assistant responses
  CONTEXT=""
  line_count=0
  while IFS= read -r line && [[ "$line_count" -lt "$TRANSCRIPT_HEAD_LINES" ]]; do
    entry_type=$(echo "$line" | jq -r '.type // empty' 2>/dev/null)
    if [[ "$entry_type" == "human" ]]; then
      text=$(echo "$line" | jq -r '
        .message.content |
        if type == "string" then .
        elif type == "array" then [.[] | select(.type == "text") | .text] | join(" ")
        else ""
        end
      ' 2>/dev/null | head -c 300)
      if [[ -n "$text" ]]; then
        CONTEXT="${CONTEXT}User: ${text}
"
      fi
    fi
    ((line_count++)) || true
  done < "$TRANSCRIPT_PATH"

  if [[ -z "$CONTEXT" ]]; then
    exit 0
  fi

  # Build API payload
  # shellcheck disable=SC2016
  PROMPT="Based on these user messages, generate a short (2-5 words) descriptive session name. Focus on what the user is working on. Output ONLY the name, no quotes, no punctuation, no explanation.

${CONTEXT}"

  PAYLOAD=$(jq -n \
    --arg model "$MODEL" \
    --argjson max_tokens "$MAX_TOKENS" \
    --arg prompt "$PROMPT" \
    '{
      model: $model,
      max_tokens: $max_tokens,
      messages: [{ role: "user", content: $prompt }]
    }')

  RESPONSE=$(curl -s --max-time 10 \
    -H "x-api-key: ${ANTHROPIC_API_KEY}" \
    -H "anthropic-version: 2023-06-01" \
    -H "content-type: application/json" \
    -d "$PAYLOAD" \
    "https://api.anthropic.com/v1/messages" 2>/dev/null)

  NAME=$(echo "$RESPONSE" | jq -r '.content[0].text // empty' 2>/dev/null | tr -d '"' | head -c 60)
  if [[ -z "$NAME" ]]; then
    exit 0
  fi

  # Set terminal title via ANSI OSC escape
  printf '\033]0;%s\007' "$NAME" > /dev/tty 2>/dev/null || true

  # Set tmux window name if inside a tmux session
  if [[ -n "${TMUX:-}" ]]; then
    tmux rename-window "$NAME" 2>/dev/null || true
  fi
) & disown

# Return synchronous systemMessage
jq -n '{
  systemMessage: "Session auto-rename triggered at turn 3: generating a descriptive name for the terminal/tmux window in the background."
}'
exit 0
