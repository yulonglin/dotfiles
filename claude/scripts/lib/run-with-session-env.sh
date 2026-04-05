#!/bin/bash
# Wrapper that sources Claude Code session env files before running a hook script.
# Usage: bash run-with-session-env.sh <script.mjs>
#
# Reads hook JSON from stdin, extracts session_id, sources all .sh files from
# ~/.claude/session-env/{session_id}/, then passes the original JSON to the script.
set -euo pipefail

SCRIPT="$1"
if [[ -z "$SCRIPT" ]]; then
  echo "Usage: run-with-session-env.sh <script>" >&2
  exit 1
fi

# Read stdin into a variable (hook JSON)
HOOK_INPUT=$(cat)

# Extract session_id using sed (avoids spawning node just for JSON parsing)
SESSION_ID=$(printf '%s' "$HOOK_INPUT" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)

# Sanitize: session IDs should be UUID-like, reject path traversal
if [[ "$SESSION_ID" == */* ]] || [[ "$SESSION_ID" == *..* ]]; then
  SESSION_ID=""
fi

# Source all session env files if we have a session ID
if [[ -n "$SESSION_ID" ]]; then
  ENV_DIR="$HOME/.claude/session-env/$SESSION_ID"
  if [[ -d "$ENV_DIR" ]]; then
    for f in "$ENV_DIR"/*.sh; do
      [[ -f "$f" ]] && source "$f"
    done
  fi
fi

# Pass the original JSON to the script
printf '%s' "$HOOK_INPUT" | exec node "$SCRIPT"
