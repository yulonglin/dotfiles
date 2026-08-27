#!/usr/bin/env bash
# shellcheck disable=SC2034,SC1091  # state vars are shared with the sourced lib
# PostToolUse hook: inside a long tool loop, remind Claude how much wall-clock
# time this turn has consumed — at most once per CLAUDE_TIME_STAMP_INTERVAL_MIN
# (default 5) minutes, so fast loops pay nothing. PostToolUse plain stdout is
# transcript-only, so the stamp goes out as hookSpecificOutput.additionalContext.
# Rationale, format and off switches: lib_time_stamp.sh.
set -uo pipefail

HOOK_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 0
# shellcheck source=lib_time_stamp.sh
source "$HOOK_DIR/lib_time_stamp.sh" || exit 0

INPUT=$(cat)
_ts_disabled && exit 0

INTERVAL_MIN="${CLAUDE_TIME_STAMP_INTERVAL_MIN:-5}"
now=$(_ts_now)
sid=$(_ts_session_id "$INPUT")
state=$(_ts_state_path "$sid")
_ts_load_state "$state"

if [ "$TS_TURN_START" -eq 0 ]; then
    # No prompt stamp seen this session (e.g. -p / resumed): start the clock, stay quiet.
    TS_TURN_START=$now; TS_LAST_STAMP=$now
    _ts_save_state "$state" 2>/dev/null || true
    exit 0
fi

[ $((now - TS_LAST_STAMP)) -ge $((INTERVAL_MIN * 60)) ] || exit 0

TS_LAST_STAMP=$now
_ts_save_state "$state" 2>/dev/null || true
_ts_resolve_tz
msg="[Time check: $(_ts_fmt_dur $((now - TS_TURN_START))) elapsed in this turn · now $(_ts_fmt_now "$now")]"
if command -v jq >/dev/null 2>&1; then
    jq -cn --arg m "$msg" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$m}}'
else
    printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}\n' "$msg"
fi
exit 0
