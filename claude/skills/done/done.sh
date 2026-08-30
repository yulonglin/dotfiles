#!/usr/bin/env bash
# Generate a ✅ session title for the `done` skill.
# Outputs the title to stdout — caller uses /rename to apply it.
set -euo pipefail

# Resolve the API key. Secrets are not globally exported (supply-chain defense),
# so reach them through the same helper the hooks use rather than a dotenv file.
DOT_DIR="${DOT_DIR:-$HOME/code/dotfiles}"
SECRETS_HELPER="$DOT_DIR/custom_bins/dotfiles-secrets"
if [[ -z "${ANTHROPIC_API_KEY:-}" && -x "$SECRETS_HELPER" ]]; then
  if exports=$("$SECRETS_HELPER" shell ANTHROPIC_API_KEY 2>/dev/null) && [[ -n "$exports" ]]; then
    eval "$exports"
  fi
fi

# Find current transcript (most recently modified .jsonl in the project dir).
# In a linked worktree the session's transcripts stay under the MAIN checkout's
# project dir, not the worktree's — so try the cwd-derived path first and fall
# back to the one derived from the git common dir's parent.
CANDIDATES=("$HOME/.claude/projects/$(pwd | sed 's|/|-|g')")
COMMON_DIR=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
if [[ -n "$COMMON_DIR" ]]; then
  MAIN_ROOT=$(dirname "$COMMON_DIR")
  CANDIDATES+=("$HOME/.claude/projects/$(printf '%s' "$MAIN_ROOT" | sed 's|/|-|g')")
fi

TRANSCRIPT=""
for PROJECT_DIR in "${CANDIDATES[@]}"; do
  TRANSCRIPT=$(/bin/ls -t "$PROJECT_DIR"/*.jsonl 2>/dev/null | head -1 || true)
  [[ -n "$TRANSCRIPT" ]] && break
done
[[ -z "$TRANSCRIPT" ]] && echo "ERROR: No transcript found in ${CANDIDATES[*]}" >&2 && exit 1

# Check for existing name
EXISTING=$(jq -r 'select(.type == "custom-title") | .customTitle // empty' "$TRANSCRIPT" 2>/dev/null || true)
EXISTING="${EXISTING##*$'\n'}"  # keep last line only

if [[ "$EXISTING" == "✅ "* ]]; then
  echo "Already done: $EXISTING" >&2
  exit 0
elif [[ -n "$EXISTING" ]]; then
  NAME="$EXISTING"
else
  # Generate name from first user messages via Haiku
  [[ -z "${ANTHROPIC_API_KEY:-}" ]] && echo "ERROR: ANTHROPIC_API_KEY not set (tried $SECRETS_HELPER)" >&2 && exit 1

  CONTEXT=$(jq -r 'select(.type == "user") |
    .message.content // empty |
    if type == "string" then .
    elif type == "array" then [.[] | select(.type == "text") | .text] | join(" ")
    else empty end
  ' "$TRANSCRIPT" 2>/dev/null || true)
  CONTEXT="${CONTEXT:0:1500}"
  [[ -z "$CONTEXT" ]] && echo "ERROR: No user messages found" >&2 && exit 1

  RESPONSE=$(curl -sf --max-time 10 \
    -H "x-api-key: ${ANTHROPIC_API_KEY}" \
    -H "anthropic-version: 2023-06-01" \
    -H "content-type: application/json" \
    -d "$(jq -nc --arg c "$CONTEXT" '{
      model: "claude-haiku-4-5-20251001", max_tokens: 30,
      messages: [{role: "user", content: ("Generate a short (2-5 word) session name for this work. Output ONLY the name, no quotes.\n\n" + $c)}]
    }')" \
    "https://api.anthropic.com/v1/messages" 2>/dev/null) || { echo "ERROR: Haiku API call failed" >&2; exit 1; }

  NAME=$(echo "$RESPONSE" | jq -r '.content[0].text // empty' 2>/dev/null)
  NAME=$(printf '%s' "$NAME" | tr -d '"\000-\037')
  NAME="${NAME:0:60}"
  [[ -z "$NAME" ]] && echo "ERROR: Empty name from Haiku" >&2 && exit 1
fi

# Output title — caller applies via /rename
echo "✅ $NAME"
