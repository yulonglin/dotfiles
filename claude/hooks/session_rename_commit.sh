#!/usr/bin/env bash
# PostToolUse(Bash) hook: after the first successful git commit, set terminal
# title and tmux window name to reflect the commit subject, then nudge Claude
# to run /rename so the session gets a descriptive name.
#
# Triggers once per session (idempotent via state file in $TMPDIR).
# Only fires on real commits — skips amends and "nothing to commit" results.

set -euo pipefail

INPUT=$(cat)

# Quick exit: only care about Bash tool calls
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')
[[ -z "$COMMAND" ]] && exit 0

# Must contain "git commit" (but not --amend)
[[ "$COMMAND" != *"git commit"* ]] && exit 0
[[ "$COMMAND" == *"--amend"* ]] && exit 0

# Check tool_result for "nothing to commit" or empty — bail early
TOOL_RESULT=$(echo "$INPUT" | jq -r '.tool_result // ""')
[[ "$TOOL_RESULT" == *"nothing to commit"* ]] && exit 0
[[ "$TOOL_RESULT" == *"nothing added to commit"* ]] && exit 0
[[ -z "$TOOL_RESULT" ]] && exit 0

# Idempotent: only trigger once per session
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // ""')
[[ -z "$SESSION_ID" ]] && exit 0

STATE_FILE="${TMPDIR:-/tmp}/claude-rename-commit-${SESSION_ID}"
[[ -f "$STATE_FILE" ]] && exit 0

# Mark as triggered (before side effects so we don't fire twice on errors)
touch "$STATE_FILE"

# Extract commit subject from tool_result.
# git commit outputs lines like: "  1 file changed, ..." after the summary line.
# The commit subject appears in a line like:
#   [branch abc1234] Subject line here
# or:
#   [branch (root-commit) abc1234] Subject line here
SUBJECT=$(echo "$TOOL_RESULT" | grep -Eo '^\[([^]]+)\] .+' | head -1 | sed 's/^\[[^]]*\] //' || true)

# Fallback: just use a generic label if extraction fails
if [[ -z "$SUBJECT" ]]; then
  SUBJECT="git commit"
fi

# Truncate and prefix with ✅
TITLE="✅ ${SUBJECT:0:60}"

# Set terminal title via OSC escape (works in most terminals)
printf '\033]0;%s\007' "$TITLE" > /dev/tty 2>/dev/null || true

# Set tmux window name if inside a tmux session
if [[ -n "${TMUX:-}" ]]; then
  tmux rename-window "$TITLE" 2>/dev/null || true
fi

# Output systemMessage nudging Claude to run /rename
jq -n --arg subject "$SUBJECT" '{
  systemMessage: ("✅ First commit made: \"" + $subject + "\". The terminal title has been updated. Consider suggesting /rename to the user with a descriptive session name.")
}'
exit 0
