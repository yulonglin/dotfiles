#!/usr/bin/env bash
# PostToolUse hook (matcher: Write|Edit): marks the session dirty when a code
# file changes, so the paired Stop hook (simplify_nudge.sh) can nudge Claude
# to run the simplify skill before finishing.
set -euo pipefail

# Extensions worth nudging on — code files, not docs/config/data (those would
# make this hook noisy on every markdown/JSON/YAML edit).
CODE_EXT_RE='\.(py|ts|tsx|js|jsx|mjs|cjs|rs|go|rb|sh|bash|zsh|c|cc|cpp|h|hpp|java|kt|swift|scala|php|cs|lua|sql)$'

INPUT=$(cat)

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null) || exit 0
[ -z "$SESSION_ID" ] && exit 0

FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || exit 0
[ -z "$FILE_PATH" ] && exit 0

if [[ "$FILE_PATH" =~ $CODE_EXT_RE ]]; then
  touch "${TMPDIR:-/tmp}/claude-simplify-dirty-${SESSION_ID}" 2>/dev/null || true
fi

exit 0
