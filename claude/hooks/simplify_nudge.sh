#!/usr/bin/env bash
# Stop hook: surface a simplify suggestion when this session produced work a
# quality pass would improve. Two independent signals, one message:
#
#   1. a code file changed this turn (marked by simplify_mark_dirty.sh);
#   2. a throwaway script has been run enough times to deserve a permanent home
#      (tallied by simplify_track_reuse.py) — the reuse/promotion signal, which
#      fires whether or not anything was edited this turn.
#
# Soft nudge only — never blocks the stop.
#
# systemMessage, not additionalContext, and deliberately so. additionalContext
# forces the turn to continue, which made every code-writing turn pay for an
# extra pass whether or not the code needed one — the "harness scaffolding that
# adds a separate pass" pattern current models are explicitly worse off for.
# A systemMessage puts the suggestion in front of the user and stops there.
#
# Because nothing continues the turn, the stop_hook_active guard this hook used
# to carry is moot: a simplify pass can no longer re-mark the session dirty and
# re-trigger itself on the next Stop check. Don't reinstate it with the message
# type as-is.
set -euo pipefail

INPUT=$(cat)

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null) || exit 0
[ -z "$SESSION_ID" ] && exit 0

TMP="${TMPDIR:-/tmp}"
MARKER="$TMP/claude-simplify-dirty-${SESSION_ID}"
# Must match state_path() in simplify_track_reuse.py. The 0700 per-user
# directory matters because these contents are echoed back to the user as a
# systemMessage — another local account must not be able to write them.
STATE_DIR="$TMP/claude-simplify-$(id -u)"
REUSE_STATE="$STATE_DIR/reuse-${SESSION_ID}.json"
[ -d "$STATE_DIR" ] && [ -O "$STATE_DIR" ] || REUSE_STATE=""

# Runs of the same script needed before it counts as reusable. At least one of
# them must be a "stable" run (file unchanged since the previous run) so that
# edit-run-edit-run debugging never trips the nudge — see simplify_track_reuse.py.
# Leading zeros are rejected too: --argjson would choke on `007`.
THRESHOLD="${CLAUDE_SIMPLIFY_REUSE_RUNS:-3}"
[[ "$THRESHOLD" =~ ^[1-9][0-9]*$ ]] || THRESHOLD=3

PARTS=()

if [ -f "$MARKER" ]; then
  rm -f "$MARKER" 2>/dev/null || true
  PARTS+=("Code changed this turn — run \`/simplify\` over it: reuse, simplification, efficiency, altitude.")
fi

if [ -n "$REUSE_STATE" ] && [ -f "$REUSE_STATE" ]; then
  # The type guard keeps one corrupt entry from erroring the whole program out
  # and suppressing every valid candidate alongside it.
  SELECT="(.value | type) == \"object\" and ((.value.runs // 0) | tonumber? // 0) >= \$t \
and ((.value.stable // 0) | tonumber? // 0) >= 1 and (.value.notified // false) != true"
  CANDIDATES=$(jq -r --argjson t "$THRESHOLD" \
    "to_entries | map(select($SELECT)) | .[] | \"- \\(.key) (ran \\(.value.runs)×)\"" \
    "$REUSE_STATE" 2>/dev/null) || CANDIDATES=""

  if [ -n "$CANDIDATES" ]; then
    PARTS+=("Scratch scripts reused this session:
$CANDIDATES

\`/simplify\` can promote them into permanent, reusable components — a real script on PATH, a shared function, or a skill.")

    # Mark them notified so the nudge doesn't repeat every turn for the rest of
    # the session. Failure here just means a duplicate nudge later — never fatal.
    if OUT=$(jq --argjson t "$THRESHOLD" \
        "with_entries(if $SELECT then .value.notified = true else . end)" \
        "$REUSE_STATE" 2>/dev/null); then
      printf '%s\n' "$OUT" > "$REUSE_STATE.tmp" 2>/dev/null &&
        mv -f "$REUSE_STATE.tmp" "$REUSE_STATE" 2>/dev/null || true
    fi
  fi
fi

[ ${#PARTS[@]} -eq 0 ] && exit 0

# Command substitution strips the trailing blank line between parts for us.
MSG=$(printf '%s\n\n' "${PARTS[@]}")
jq -n --arg msg "$MSG" '{systemMessage: $msg}'
exit 0
