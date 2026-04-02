#!/usr/bin/env bash
# Hook: Auto-rename Claude Code session, Ghostty tab, and tmux window
# Event: Stop
# Triggers ONCE at turn 3. Calls Haiku to generate a short name, then:
#   1. Appends custom-title entry to transcript JSONL (Claude Code /resume)
#   2. Sets terminal/Ghostty tab title via OSC
#   3. Renames tmux window
# Skips if user already set a name via --name.

set -euo pipefail

TRIGGER_TURN=3
MODEL="claude-haiku-4-5-20251001"

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[[ -z "$SESSION_ID" ]] && exit 0

# Turn counter — file stores count, -1 = already fired
STATE_FILE="${TMPDIR:-/tmp}/claude-rename-auto-${SESSION_ID}"
TURN=$(cat "$STATE_FILE" 2>/dev/null || echo 0)
[[ "$TURN" == "-1" ]] && exit 0
TURN=$((TURN + 1))
if [[ "$TURN" -lt "$TRIGGER_TURN" ]]; then
  echo "$TURN" > "$STATE_FILE"
  exit 0
fi

# Don't mark as fired yet — defer until background succeeds (bug fix:
# if Haiku call fails, we retry on next turn instead of giving up forever)
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
[[ -z "$TRANSCRIPT_PATH" || ! -f "$TRANSCRIPT_PATH" ]] && exit 0
[[ -z "${ANTHROPIC_API_KEY:-}" ]] && exit 0

# Skip if user already named this session
grep -q '"custom-title"' "$TRANSCRIPT_PATH" 2>/dev/null && exit 0

# --- Background: call Haiku, then apply name ---
(
  # Collect user messages. Use grep to pre-filter human entries so jq only
  # parses relevant lines (avoids failure on truncated last line from live writes).
  CONTEXT=$(grep '"type":"human"' "$TRANSCRIPT_PATH" 2>/dev/null \
    | head -20 \
    | jq -r '
      .message.content // empty |
      if type == "string" then .
      elif type == "array" then [.[] | select(.type == "text") | .text] | join(" ")
      else empty
      end
    ' 2>/dev/null \
    | head -c 1500) || true
  [[ -z "$CONTEXT" ]] && exit 0

  RESPONSE=$(curl -sf --max-time 10 \
    -H "x-api-key: ${ANTHROPIC_API_KEY}" \
    -H "anthropic-version: 2023-06-01" \
    -H "content-type: application/json" \
    -d "$(jq -nc --arg m "$MODEL" --arg c "$CONTEXT" '{
      model: $m, max_tokens: 30,
      messages: [{role: "user", content: ("Generate a short (2-5 word) session name for this work. Output ONLY the name.\n\n" + $c)}]
    }')" \
    "https://api.anthropic.com/v1/messages" 2>/dev/null) || exit 0

  # Strip quotes and control characters from model output
  NAME=$(echo "$RESPONSE" | jq -r '.content[0].text // empty' 2>/dev/null \
    | tr -d '"' | tr -d '\000-\037' | head -c 60)
  [[ -z "$NAME" ]] && exit 0

  # Mark as fired only after we have a valid name
  echo "-1" > "$STATE_FILE"

  # 1. Claude Code session name (custom-title in transcript JSONL)
  jq -nc --arg t "$NAME" --arg s "$SESSION_ID" \
    '{"type":"custom-title","customTitle":$t,"sessionId":$s}' >> "$TRANSCRIPT_PATH"

  # 2. Terminal / Ghostty tab title
  printf '\033]0;%s\033\\\033]2;%s\033\\' "$NAME" "$NAME" > /dev/tty 2>/dev/null || true

  # 3. tmux window name
  if [[ -n "${TMUX:-}" ]]; then
    tmux set-option -w automatic-rename off 2>/dev/null || true
    tmux rename-window "$NAME" 2>/dev/null || true
  fi
) & disown

exit 0
