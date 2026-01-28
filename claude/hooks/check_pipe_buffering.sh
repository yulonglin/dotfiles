#!/bin/bash
# Claude Code PreToolUse hook: Warn about pipe patterns that cause buffering issues
# Suggests command-specific flags or stdbuf when piping through head/tail/less/more
#
# Exit codes:
#   0 - Allow (with optional warning message to stderr)
#   2 - Block (not used here — warnings only)

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

# Skip empty commands
[ -z "$COMMAND" ] && exit 0

# Check for interactive pagers (these won't work in non-interactive context)
if echo "$COMMAND" | grep -qE '\|\s*(less|more)\b'; then
    echo "WARNING: Piping through less/more won't work non-interactively. Use bat --paging=never or remove the pipe." >&2
    exit 0
fi

# Check for commands that have native limit flags being piped through head/tail
# git log | head → git log -n X
if echo "$COMMAND" | grep -qE '\bgit\s+log\b.*\|\s*head\b'; then
    echo "SUGGESTION: Use 'git log -n N' instead of piping through head." >&2
    exit 0
fi

# git diff | head → git diff (already truncated by Claude)
# kubectl logs | tail → kubectl logs --tail=N
if echo "$COMMAND" | grep -qE '\bkubectl\s+logs\b.*\|\s*tail\b'; then
    echo "SUGGESTION: Use 'kubectl logs --tail=N' instead of piping through tail." >&2
    exit 0
fi

# docker logs | tail → docker logs --tail=N
if echo "$COMMAND" | grep -qE '\bdocker\s+logs\b.*\|\s*tail\b'; then
    echo "SUGGESTION: Use 'docker logs --tail=N' instead of piping through tail." >&2
    exit 0
fi

exit 0
