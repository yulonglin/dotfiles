#!/usr/bin/env bash
# Stop hook: in a BACKGROUND job, a question written as prose never reaches
# the user — it renders into a job list nobody is watching, and the session
# stalls looking exactly like a crash. This hook catches that at the moment
# it would happen.
#
# One-shot SOFT gate. The first Stop on a question-shaped turn that made no
# AskUserQuestion call is blocked with a reason the model reads; a guard file
# is written so the retry ALWAYS passes. "Advisory" here means it cannot
# permanently trap a session — never that it can be ignored the first time.
#
# Channel: {"decision":"block","reason":...} is the Stop contract that
# reaches the model (see guard_post_rebase.sh). additionalContext decorates
# without blocking, which would make the gate vacuous.
#
# Fail-open everywhere: any parse failure, missing transcript, or absent jq
# exits 0. Foreground sessions are never gated (prose questions do reach the
# user there) — the discriminator is CLAUDE_JOB_DIR.

# shellcheck disable=SC2016  # jq program and backticked prose are literal
set -uo pipefail

INPUT=$(cat)

# never re-fire inside a stop-hook continuation
STOP_HOOK_ACTIVE=$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null) || exit 0
[ "$STOP_HOOK_ACTIVE" = "true" ] && exit 0

# background jobs only
[ -n "${CLAUDE_JOB_DIR:-}" ] || exit 0

command -v jq >/dev/null 2>&1 || exit 0

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null) || exit 0
[ -n "$SESSION_ID" ] || exit 0

TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null) || exit 0
[ -n "$TRANSCRIPT" ] && [ -r "$TRANSCRIPT" ] || exit 0

# one-shot: if we already nudged this session, let the stop through
GUARD_DIR="${TMPDIR:-/tmp}"
[ -d "$GUARD_DIR" ] && [ -w "$GUARD_DIR" ] || GUARD_DIR=/tmp
GUARD="$GUARD_DIR/claude-bgq-nudged-${SESSION_ID}"
[ -f "$GUARD" ] && exit 0

# --- pull this turn out of the transcript ------------------------------------
# A turn starts at the last real user message (one that is not just a
# tool_result carrier). Within it we need: did any assistant message call
# AskUserQuestion, and what was the final assistant text?
JQ_PROG='
def content_array: if (.message.content? | type) == "array" then .message.content else [] end;
def is_tool_result: (content_array | map(select((.type // "") == "tool_result")) | length) > 0;
. as $all
| ([ range(0; ($all | length))
     | select((($all[.].type) // "") == "user" and (($all[.] | is_tool_result) | not)) ]
   | last) as $s
| (if $s == null then 0 else $s end) as $start
| ($all[$start:] | map(select(((.type) // "") == "assistant")) | map(content_array) | flatten) as $blocks
| {
    ask: (($blocks | map(select(((.type) // "") == "tool_use"
                                and ((.name) // "") == "AskUserQuestion"))
                   | length) > 0),
    text: (($blocks | map(select(((.type) // "") == "text") | (.text // "")) | last) // "")
  }
'

PARSED=$(tail -n 400 "$TRANSCRIPT" 2>/dev/null \
    | jq -R -s 'split("\n") | map(select(length > 0) | fromjson? // empty)' 2>/dev/null \
    | jq -c "$JQ_PROG" 2>/dev/null) || exit 0
[ -n "$PARSED" ] || exit 0

ASKED=$(printf '%s' "$PARSED" | jq -r '.ask' 2>/dev/null) || exit 0
[ "$ASKED" = "true" ] && exit 0

TEXT=$(printf '%s' "$PARSED" | jq -r '.text' 2>/dev/null) || exit 0
[ -n "$TEXT" ] || exit 0

# A completed job is allowed to offer follow-ups — a trailing "want me to
# also…?" after result:/failed: is not a stalled decision point.
printf '%s\n' "$TEXT" | grep -qiE '^[[:space:]]*(result|failed):' && exit 0

# --- is the closing prose question-shaped? -----------------------------------
LAST_LINE=$(printf '%s\n' "$TEXT" \
    | grep -vE '^[[:space:]]*$' \
    | grep -viE '^[[:space:]]*(result|needs input|failed):' \
    | tail -n 1)

QUESTION=false
printf '%s' "$LAST_LINE" | grep -qE '\?[[:space:]]*$' && QUESTION=true
printf '%s' "$TEXT" | grep -qiE 'which (would|do) you (prefer|want)|should i |shall i |do you want me to|would you like me to|let me know (if|whether|which|what)' \
    && QUESTION=true

[ "$QUESTION" = "true" ] || exit 0

# The one-shot guarantee depends on the guard file. If it cannot be written
# (read-only TMPDIR, for instance) a block would repeat on every stop and
# trap the session — so no guard means no block.
: > "$GUARD" 2>/dev/null || exit 0

REASON='This is a background job, and you ended the turn on a question written as prose. Prose questions do NOT reach the user here — they render into a job list that fires no notification, so the session looks stalled and the decision is never seen.

Do one of two things, then finish:

1. If a human genuinely has to decide this, call AskUserQuestion with the options. That fires a notification and records the choice. Follow it with `needs input:` on its own line.
2. If the decision is scoped, low-risk, and reversible, do NOT ask at all — take the sensible default, state the assumption you took in one line, and keep working. The bound is load-bearing: it covers scoped, low-risk, reversible calls and nothing else. Where the readings conflict, the narrower one wins — ask.

This gate is one-shot. Your next stop goes through regardless, so make the call and proceed.'

jq -n --arg reason "$REASON" '{decision: "block", reason: $reason}'
exit 0
