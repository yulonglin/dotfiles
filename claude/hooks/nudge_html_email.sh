#!/usr/bin/env bash
# PreToolUse hook: nudge to use text/html for Gmail drafts.
# Plain text drafts lose line breaks when edited in Gmail's compose window.
# Exit 0 = allow (nudge only, never block).

set -euo pipefail

INPUT=$(cat)

CONTENT_TYPE=$(printf '%s' "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    inp = d.get('tool_input', d)
    print(inp.get('contentType', ''))
except:
    print('')
" 2>/dev/null) || exit 0

if [ "$CONTENT_TYPE" != "text/html" ]; then
    printf 'NUDGE: Use contentType: "text/html" for Gmail drafts. Plain text loses line breaks when edited in Gmail.\n' >&2
fi

exit 0
