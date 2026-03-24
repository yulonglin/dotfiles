#!/usr/bin/env bash
set -euo pipefail
# Gate mcp__claude-in-chrome__tabs_context_mcp with createIfEmpty: true
# Chrome auto-saves tab groups to bookmarks bar, causing persistent clutter

# Fail closed if jq not available: prompt user rather than silently allowing
if ! command -v jq &>/dev/null; then
  echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"jq not found; cannot verify createIfEmpty. Requesting manual approval."}}'
  exit 0
fi

# Single jq call: extract createIfEmpty directly, exit early if false/missing
CREATE_IF_EMPTY=$(jq -r '.tool_input.createIfEmpty // false')

if [[ "$CREATE_IF_EMPTY" == "true" ]]; then
  cat <<'EOF'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"createIfEmpty will create a Chrome tab group that auto-saves to bookmarks bar. Approve only if browser automation was explicitly requested."}}
EOF
fi
