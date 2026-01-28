#!/bin/bash
# Claude Code PreToolUse hook: Warn about destructive commands that might bypass permission rules
# Catches patterns like: xargs kill, eval "rm -rf ...", sudo kill, etc.
#
# The deny/ask lists in settings.json handle direct invocations.
# This hook catches indirect invocations (piped, subshell, xargs, sudo).
#
# Exit codes:
#   0 - Allow (with optional warning)
#   2 - Block

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

[ -z "$COMMAND" ] && exit 0

# Block: sudo + destructive commands (privilege escalation around deny rules)
if echo "$COMMAND" | grep -qE '\bsudo\s+(rm\s+-r|kill|killall|pkill|shutdown|reboot|halt|mkfs|fdisk|wipefs|dd)\b'; then
    echo "BLOCKED: sudo + destructive command detected. Please confirm intent." >&2
    exit 2
fi

# Block: xargs with destructive commands
if echo "$COMMAND" | grep -qE '\bxargs\s+.*(rm\s+-r|kill|killall|pkill)\b'; then
    echo "BLOCKED: xargs + destructive command detected. Please confirm intent." >&2
    exit 2
fi

# Warn: kill/signal patterns in compound commands (&&, ||, ;, $())
# Direct `kill` is handled by ask list, but composed commands bypass it
if echo "$COMMAND" | grep -qE '(&&|;|\|\||`|\$\()\s*(kill|killall|pkill)\b'; then
    echo "WARNING: kill command in compound expression — verify target PIDs." >&2
    exit 0
fi

exit 0
