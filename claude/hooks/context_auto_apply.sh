#!/usr/bin/env bash
# SessionStart hook: auto-apply context.yaml, warn if no context configured
CONTEXT_FILE=".claude/context.yaml"
if [ -f "$CONTEXT_FILE" ]; then
    claude-context 2>/dev/null
else
    # Warn if inside a git repo without context profiles
    if git rev-parse --is-inside-work-tree &>/dev/null; then
        echo -e "\033[0;33mNo context profiles configured for this project.\033[0m"
        echo -e "Run: claude-context <profile>  (e.g., claude-context code python)"
        echo -e "List profiles: claude-context --list"
    fi
fi
exit 0  # Don't block session start
