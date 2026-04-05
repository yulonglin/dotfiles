#!/bin/bash
# guard_settings_commit.sh — PreToolUse:Bash hook
#
# Intercepts git add/commit operations that would stage a degraded
# claude/settings.json. Belt-and-suspenders with the global pre-commit hook:
# this fires earlier (at `git add` time) and works even with --no-verify.
#
# How it failed: stash captured a 3-field stub of settings.json; we committed
# it, silently wiping 545 lines of structural config (statusLine, hooks, etc.).

COMMAND="${CLAUDE_TOOL_INPUT_COMMAND:-}"

# Only care about git add/commit
echo "$COMMAND" | grep -qE '\bgit\b.*(add|commit)' || exit 0

# Determine whether this command touches settings.json
TOUCHES_SETTINGS=false
if echo "$COMMAND" | grep -q 'settings\.json'; then
    TOUCHES_SETTINGS=true
elif echo "$COMMAND" | grep -q 'git commit'; then
    # Check if settings.json is already staged
    git diff --cached --name-only 2>/dev/null | grep -q 'settings\.json' && TOUCHES_SETTINGS=true
fi

[[ "$TOUCHES_SETTINGS" == "true" ]] || exit 0

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0

# Find the settings file in the working tree
SETTINGS_FILE=""
for candidate in "claude/settings.json" ".claude/settings.json"; do
    [ -f "$REPO_ROOT/$candidate" ] && SETTINGS_FILE="$REPO_ROOT/$candidate" && SETTINGS_REL="$candidate" && break
done
[ -z "$SETTINGS_FILE" ] && exit 0

# Only validate if HEAD had a substantial settings.json (>50 lines)
PREV_LINES=$(git -C "$REPO_ROOT" show "HEAD:$SETTINGS_REL" 2>/dev/null | wc -l || echo 0)
[ "$PREV_LINES" -lt 50 ] && exit 0

# Current working-tree line count
CUR_LINES=$(wc -l < "$SETTINGS_FILE" || echo 0)

# Validate required structural keys
MISSING=$(python3 -c "
import json, sys
try:
    with open('$SETTINGS_FILE') as f:
        d = json.load(f)
except Exception as e:
    print(f'parse-error: {e}')
    sys.exit(1)
required = ['statusLine', 'hooks', 'permissions']
missing = [k for k in required if k not in d]
if missing:
    print(' '.join(missing))
    sys.exit(1)
" 2>&1) || {
    echo ""
    echo "⛔  BLOCKED: $SETTINGS_REL is missing required keys: $MISSING"
    echo "    HEAD: $PREV_LINES lines  →  working tree: $CUR_LINES lines"
    echo "    This looks like a degraded stub. Do not stage it."
    echo ""
    echo "    Restore from HEAD:"
    echo "      git show HEAD:$SETTINGS_REL > $SETTINGS_FILE"
    echo ""
    exit 2
}

exit 0
