#!/usr/bin/env bash
# shellcheck disable=SC2034,SC1091  # state vars are shared with the sourced lib
# UserPromptSubmit hook: prints the current local date/time + UTC, and the gap
# since the previous prompt when it is large enough to matter. Plain stdout on
# this event is added to Claude's context. Rationale, format and off switches:
# lib_time_stamp.sh.
set -uo pipefail

HOOK_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 0
# shellcheck source=lib_time_stamp.sh
source "$HOOK_DIR/lib_time_stamp.sh" || exit 0

INPUT=$(cat)
_ts_disabled && exit 0

GAP_MIN="${CLAUDE_TIME_GAP_MIN:-10}"
now=$(_ts_now)
sid=$(_ts_session_id "$INPUT")
state=$(_ts_state_path "$sid")
_ts_load_state "$state"

gap=""
if [ "$TS_LAST_PROMPT" -gt 0 ] && [ $((now - TS_LAST_PROMPT)) -ge $((GAP_MIN * 60)) ]; then
    gap=" · $(_ts_fmt_dur $((now - TS_LAST_PROMPT))) since your last message"
fi

TS_LAST_PROMPT=$now; TS_TURN_START=$now; TS_LAST_STAMP=$now
_ts_save_state "$state" 2>/dev/null || true

_ts_resolve_tz
warn=""
[ -n "$TS_TZ_WARN" ] && warn=" — WARNING: $TS_TZ_WARN, using $TS_TZ"
printf '[Now: %s%s%s]\n' "$(_ts_fmt_now "$now")" "$gap" "$warn"
exit 0
