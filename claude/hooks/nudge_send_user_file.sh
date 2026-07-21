#!/usr/bin/env bash
# PostToolUse hook (matcher: Write): nudge to call SendUserFile for deliverable-like
# files instead of just stating the path. See:
# claude/rules/workflow-defaults.md § Auditability § Visual Outputs.
# Exit 0 always = allow (nudge only, never block).

set -euo pipefail

SIZE_CAP_BYTES=$((5 * 1024 * 1024))

# Extensions worth nudging on — deliverables a user would want to open, not
# routine source/config edits (those would make this hook noisy on every save).
DELIVERABLE_EXT_RE='\.(html?|md|jsonl|eval|svg|png|pdf|ipynb|csv)$'

# Paths to skip regardless of extension — internal/agent state, not deliverables.
SKIP_PATH_RE='(^|/)(\.git|\.claude|node_modules|\.venv|__pycache__)(/|$)'

INPUT=$(cat)

FILE_PATH=$(printf '%s' "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    inp = d.get('tool_input', d)
    print(inp.get('file_path', ''))
except Exception:
    print('')
" 2>/dev/null) || exit 0

[ -z "$FILE_PATH" ] && exit 0
[ -f "$FILE_PATH" ] || exit 0

if [[ "$FILE_PATH" =~ $SKIP_PATH_RE ]]; then
    exit 0
fi

if ! [[ "$FILE_PATH" =~ $DELIVERABLE_EXT_RE ]]; then
    exit 0
fi

SIZE_BYTES=$(stat -c%s "$FILE_PATH" 2>/dev/null || stat -f%z "$FILE_PATH" 2>/dev/null) || exit 0

if [ "$SIZE_BYTES" -ge "$SIZE_CAP_BYTES" ]; then
    exit 0
fi

cat <<HOOK_EOF
{
  "systemMessage": "NUDGE: $FILE_PATH ($SIZE_BYTES bytes) looks like a deliverable — call SendUserFile now instead of just stating the path (workflow-defaults.md § Auditability § Visual Outputs)."
}
HOOK_EOF
exit 0
