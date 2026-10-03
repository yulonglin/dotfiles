#!/usr/bin/env bash
# PreToolUse hook (matcher: Skill): records that a code-quality skill was
# invoked on the current repo+branch, which is what clears quality_pr_gate.sh.
#
# Hook config: matcher "Skill" with NO `if` clause — Skill(<name>) patterns do
# not work here (same finding as codex_code_review_reminder.mjs). The hook
# therefore self-validates on tool_input.skill.
#
# Semantics, stated honestly: PreToolUse fires on INVOCATION, not completion.
# The marker means "this skill was started on this branch", not "this skill
# finished and found nothing". That is the intended trade — a completion-based
# marker would never be written when a skill exits early, and the gate would
# never clear, which is the one failure mode worse than a missed review.
set -euo pipefail

# Skills whose invocation is worth recording. requesting-code-review is the one
# quality_pr_gate.sh reads; verification-before-completion is tracked for
# symmetry with the Stop nudge and for future gates.
TRACKED_SKILLS='requesting-code-review verification-before-completion'

LIB="$(dirname "$0")/lib/quality_gate_lib.sh"
[ -r "$LIB" ] || exit 0
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/quality_gate_lib.sh
. "$LIB"

command -v jq >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0

INPUT=$(cat)
SKILL=$(printf '%s' "$INPUT" | jq -r '.tool_input.skill // empty' 2>/dev/null) || exit 0
[ -n "$SKILL" ] || exit 0

# Accept both the bare and plugin-qualified forms ("superpowers:foo" -> "foo").
SKILL_NAME="${SKILL##*:}"
case " $TRACKED_SKILLS " in
    *" $SKILL_NAME "*) ;;
    *) exit 0 ;;
esac

MARKER=$(quality_gate_marker "$SKILL_NAME")
[ -n "$MARKER" ] || exit 0

mkdir -p "$(dirname "$MARKER")" 2>/dev/null || exit 0
touch "$MARKER" 2>/dev/null || true
exit 0
