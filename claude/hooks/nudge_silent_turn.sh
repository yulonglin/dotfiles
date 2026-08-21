#!/usr/bin/env bash
# Stop hook: a turn that answers a real human message with ZERO user-visible
# text looks, from the user's side, exactly like a crash — thinking and tool
# output are invisible, so the session "went silent" (incident 2026-08-21:
# two direct questions, 16s of thinking, no reply). This hook catches the
# turn at the moment it would end silently.
#
# One-shot SOFT gate per turn. The first Stop on a silent turn is blocked
# with a reason the model reads; a guard file keyed on (session, user
# message) makes the retry for the SAME turn always pass, and
# stop_hook_active short-circuits continuation stops regardless.
#
# Exempt: turns whose only output is an interactive surface that renders its
# own UI (AskUserQuestion, plan mode, SendMessage), command/interrupt turns,
# and turns with no assistant activity at all (weird states fail open).
#
# Fail-open everywhere: any parse failure, missing transcript, or absent jq
# exits 0. Companion rule: claude/rules/visible-progress.md.

# shellcheck disable=SC2016  # jq program and backticked prose are literal
set -uo pipefail

INPUT=$(cat)

# never re-fire inside a stop-hook continuation
STOP_HOOK_ACTIVE=$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null) || exit 0
[ "$STOP_HOOK_ACTIVE" = "true" ] && exit 0

command -v jq >/dev/null 2>&1 || exit 0

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null) || exit 0
[ -n "$SESSION_ID" ] || exit 0

TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null) || exit 0
[ -n "$TRANSCRIPT" ] && [ -r "$TRANSCRIPT" ] || exit 0

# --- pull this turn out of the transcript ------------------------------------
# A turn starts at the last real user message (one that is not just a
# tool_result carrier). We need: the human text of that message (minus
# injected system-reminders), whether any assistant block since then is
# non-empty visible text, whether an exempt interactive tool was used, and
# whether the assistant did anything at all.
JQ_PROG='
def content_array: if (.message.content? | type) == "array" then .message.content else [] end;
def content_str: if (.message.content? | type) == "string" then .message.content else "" end;
def is_tool_result: (content_array | map(select((.type // "") == "tool_result")) | length) > 0;
. as $all
| ([ range(0; ($all | length))
     | select((($all[.].type) // "") == "user" and (($all[.] | is_tool_result) | not)) ]
   | last) as $s
| if $s == null then {found: false} else
    ($all[$s]) as $u
    | (($u | content_array | map(select(((.type) // "") == "text") | (.text // "")) | join("\n"))
       + ($u | content_str)) as $raw
    | ($raw | gsub("<system-reminder>.*?</system-reminder>"; ""; "s")) as $utext
    | ($all[($s + 1):] | map(select(((.type) // "") == "assistant")) | map(content_array) | flatten) as $blocks
    | {
        found: true,
        utext: $utext,
        nblocks: ($blocks | length),
        has_text: (($blocks
                    | map(select(((.type) // "") == "text"
                                 and ((((.text // "") | gsub("\\s"; "")) | length) > 0)))
                    | length) > 0),
        exempt: (($blocks
                  | map(select(((.type) // "") == "tool_use"
                               and (((.name) // "")
                                    | IN("AskUserQuestion", "ExitPlanMode", "EnterPlanMode", "SendMessage"))))
                  | length) > 0)
      }
  end
'

PARSED=$(tail -n 400 "$TRANSCRIPT" 2>/dev/null \
    | jq -R -s 'split("\n") | map(select(length > 0) | fromjson? // empty)' 2>/dev/null \
    | jq -c "$JQ_PROG" 2>/dev/null) || exit 0
[ -n "$PARSED" ] || exit 0

FOUND=$(printf '%s' "$PARSED" | jq -r '.found' 2>/dev/null) || exit 0
[ "$FOUND" = "true" ] || exit 0

HAS_TEXT=$(printf '%s' "$PARSED" | jq -r '.has_text' 2>/dev/null) || exit 0
[ "$HAS_TEXT" = "true" ] && exit 0

EXEMPT=$(printf '%s' "$PARSED" | jq -r '.exempt' 2>/dev/null) || exit 0
[ "$EXEMPT" = "true" ] && exit 0

# no assistant activity at all is a weird state, not a silent turn — fail open
NBLOCKS=$(printf '%s' "$PARSED" | jq -r '.nblocks' 2>/dev/null) || exit 0
[ "$NBLOCKS" -gt 0 ] 2>/dev/null || exit 0

UTEXT=$(printf '%s' "$PARSED" | jq -r '.utext' 2>/dev/null) || exit 0

# a user message that is only injected chrome is not a human message:
# slash-command turns, command output carriers, and interrupts end without
# prose legitimately
printf '%s' "$UTEXT" | grep -qE '<command-name>|<command-message>|<local-command-stdout>|\[Request interrupted' && exit 0
UCLEAN=$(printf '%s' "$UTEXT" | tr -d '[:space:]')
[ -n "$UCLEAN" ] || exit 0

# --- one-shot per turn -------------------------------------------------------
# Keyed on (session, user-message content) so a genuinely new silent turn in
# the same session still gates once, but the retry for this turn never does.
GUARD_DIR="${TMPDIR:-/tmp}"
[ -d "$GUARD_DIR" ] && [ -w "$GUARD_DIR" ] || GUARD_DIR=/tmp
TURN_KEY=$(printf '%s%s' "$SESSION_ID" "$UTEXT" | cksum | tr -cd '0-9a-zA-Z')
GUARD="$GUARD_DIR/claude-silent-turn-${SESSION_ID}-${TURN_KEY}"
[ -f "$GUARD" ] && exit 0

# The one-shot guarantee depends on the guard file. If it cannot be written,
# a block could repeat on every stop of this turn — so no guard means no block.
: > "$GUARD" 2>/dev/null || exit 0

REASON='You are ending this turn with ZERO user-visible text since the human last spoke. The user cannot see your thinking, your tool calls, or collapsed teammate messages — from their side the session went silent, which reads as a crash or as being ignored.

Before stopping, write a visible reply:

1. Answer every question in their last message — what is answerable now gets answered now; what needs computation gets one line naming what is pending and when it will land.
2. If you are waiting on background work, say what you are waiting on and the next checkpoint.
3. If a subagent or teammate finished, restate the substance of its result in your own words.

This gate is one-shot for this turn — your next stop goes through regardless, so reply and finish.'

jq -n --arg reason "$REASON" '{decision: "block", reason: $reason}'
exit 0
