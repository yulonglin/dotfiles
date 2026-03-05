#!/bin/bash
set -euo pipefail

# PermissionRequest hook: auto-deny when autonomous mode is active.
# State file: .claude/autopilot/state.json (per-project, gitignored)
# Log: ~/.cache/claude/auto-deny.log

input=$(cat)
STATE_FILE="${CLAUDE_PROJECT_DIR:-.}/.claude/autopilot/state.json"
LOG="$HOME/.cache/claude/auto-deny.log"

# Not configured → normal prompting
[ -f "$STATE_FILE" ] || exit 0

# Check autonomous mode
jq -e '.autonomous_mode == true' "$STATE_FILE" >/dev/null 2>&1 || exit 0

# Extract what's being requested for the log/message
rule=$(echo "$input" | jq -r '
  [.permission_suggestions // [] | .[] |
   select(.type == "addRules") | .rules[]? | .ruleContent
  ] | first // "unknown"')

# Log and deny
mkdir -p "$(dirname "$LOG")"
printf '%s DENIED: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$rule" >> "$LOG" 2>/dev/null

jq -n --arg msg "Auto-denied in autonomous mode: \`$rule\` is not permitted. Do NOT retry this action. Instead: (1) use a different approach with tools already permitted by your current permission mode, (2) skip this step and continue with the rest of your task, or (3) ask the user for help." '{
  hookSpecificOutput: {
    hookEventName: "PermissionRequest",
    decision: { behavior: "deny", message: $msg, interrupt: true }
  }
}'
