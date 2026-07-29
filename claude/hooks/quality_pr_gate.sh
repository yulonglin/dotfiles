#!/usr/bin/env bash
# PreToolUse hook (matcher: Bash): blocks `gh pr create` when the branch changes
# code files and the requesting-code-review skill has not run on this branch.
#
# Why a deny rather than a nudge. PreToolUse additionalContext is delivered
# alongside the tool result — i.e. after `gh pr create` has already opened the
# PR. A reminder at that point cannot stop un-reviewed code from being
# published, it can only ask for a follow-up commit. This is the one hard gate;
# the paired Stop hook (quality_stop_nudge.sh) stays a soft nudge.
#
# FAIL OPEN, deliberately. Every unresolvable condition — no jq, not a git repo,
# no base ref, unreadable diff — exits 0 and allows the PR. A quality gate that
# blocks PR creation because it could not compute a merge-base is strictly worse
# than one that occasionally misses. Do not "harden" this into a fail-closed
# check; that is a regression, not a fix.
#
# Bypass: touch the marker file named in the deny message.
set -euo pipefail

GATE_SKILL="requesting-code-review"
CODE_EXT_RE='\.(py|ts|tsx|js|jsx|mjs|cjs|rs|go|rb|sh|bash|zsh|c|cc|cpp|h|hpp|java|kt|swift|scala|php|cs|lua|sql)$'

LIB="$(dirname "$0")/lib/quality_gate_lib.sh"
[ -r "$LIB" ] || exit 0
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/quality_gate_lib.sh
. "$LIB"

command -v jq >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0

INPUT=$(cat)
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[ -n "$CMD" ] || exit 0

# Match `gh pr create` anywhere in the command, so it is still caught after a
# `&&`, with extra whitespace, or followed by flags such as --draft.
[[ "$CMD" =~ (^|[;&|[:space:]])gh[[:space:]]+pr[[:space:]]+create([[:space:]]|$) ]] || exit 0

# `gh pr create --help` prints usage and creates nothing. Denying it would be
# pure noise, and the deny message ("run the review skill") is nonsense advice
# for someone who is just reading the docs.
[[ "$CMD" =~ (^|[[:space:]])(--help|-h)([[:space:]]|$) ]] && exit 0

MARKER=$(quality_gate_marker "$GATE_SKILL")
[ -n "$MARKER" ] || exit 0   # not a git repo, or key unavailable → allow
[ -f "$MARKER" ] && exit 0   # already reviewed on this branch → allow

# Base ref: an explicit --base wins, then origin/HEAD, then the usual names.
BASE=""
if [[ "$CMD" =~ --base[[:space:]=]+([^[:space:]\"\']+) ]]; then
    BASE="${BASH_REMATCH[1]}"
fi
if [ -z "$BASE" ]; then
    BASE=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null) || BASE=""
fi
if [ -z "$BASE" ]; then
    for cand in origin/main origin/master main master; do
        if git rev-parse --verify --quiet "$cand" >/dev/null 2>&1; then
            BASE="$cand"
            break
        fi
    done
fi
[ -n "$BASE" ] || exit 0
git rev-parse --verify --quiet "$BASE" >/dev/null 2>&1 || exit 0

CHANGED=$(git diff --name-only "$BASE...HEAD" 2>/dev/null) || exit 0
[ -n "$CHANGED" ] || exit 0

CODE_FILES=$(printf '%s\n' "$CHANGED" | grep -Ei "$CODE_EXT_RE" || true)
[ -n "$CODE_FILES" ] || exit 0   # docs/config-only branch → nothing to review

COUNT=$(printf '%s\n' "$CODE_FILES" | wc -l | tr -d ' ')
SAMPLE=$(printf '%s\n' "$CODE_FILES" | head -5 | tr '\n' ' ')

REASON="This branch changes ${COUNT} code file(s) against ${BASE} (${SAMPLE}) and the ${GATE_SKILL} skill has not run on it yet. Run the Skill tool with skill: \"superpowers:${GATE_SKILL}\" over the branch diff, then re-run this command. If a review genuinely does not apply to this branch, bypass with: touch '${MARKER}'"

jq -n --arg r "$REASON" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $r
  }
}'
exit 0
