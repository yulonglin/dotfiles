#!/usr/bin/env bash
# Stop hook: if a code file changed this turn (marked by
# quality_mark_dirty.sh), nudge Claude via additionalContext to verify the work
# before finishing. Soft nudge only — never blocks the stop. The one hard gate
# lives at PR-creation time (quality_pr_gate.sh).
#
# Target skill: this nudge previously pointed at a "simplify" skill that does
# not exist anywhere on disk — the only simplifier installed is the
# code-simplifier AGENT, which is disabled in settings.json. It now points at
# superpowers:verification-before-completion, which is installed and enabled.
#
# stop_hook_active guard: additionalContext keeps the conversation going
# through the same loop protections as decision:block, so without this guard
# a verification pass that itself edits code would re-mark the session dirty
# and re-trigger the nudge on the next Stop check.
set -euo pipefail

INPUT=$(cat)

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null) || exit 0
[ -z "$SESSION_ID" ] && exit 0

MARKER="${TMPDIR:-/tmp}/claude-quality-dirty-${SESSION_ID}"
[ -f "$MARKER" ] || exit 0
rm -f "$MARKER" 2>/dev/null || true

STOP_HOOK_ACTIVE=$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null) || exit 0
[[ "$STOP_HOOK_ACTIVE" == "true" ]] && exit 0

cat <<'HOOK_EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "Stop",
    "additionalContext": "Code was written this turn — consider running the Skill tool with skill: \"superpowers:verification-before-completion\" over the changed files before finishing."
  }
}
HOOK_EOF
exit 0
