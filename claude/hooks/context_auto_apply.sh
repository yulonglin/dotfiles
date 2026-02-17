#!/usr/bin/env bash
# SessionStart hook: auto-apply context.yaml if present
CONTEXT_FILE=".claude/context.yaml"
if [ -f "$CONTEXT_FILE" ]; then
    claude-context 2>/dev/null
fi
exit 0  # Don't block session start
