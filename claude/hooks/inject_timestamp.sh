#!/usr/bin/env zsh
# UserPromptSubmit hook: prints the current local date/time + UTC, and the gap
# since the previous prompt when it is large enough to matter. Plain stdout on
# this event is added to Claude's context. Rationale, format and off switches:
# lib_time_stamp.sh. Always exits 0.
emulate -L zsh
setopt no_unset pipe_fail

HOOK_DIR=${0:A:h}
source $HOOK_DIR/lib_time_stamp.sh || { cat >/dev/null 2>&1; exit 0 }

INPUT=$(cat)
_ts_disabled && exit 0

GAP_MIN=${CLAUDE_TIME_GAP_MIN:-10}
now=$(_ts_now)
sid=$(_ts_session_id "$INPUT")
state=$(_ts_state_path $sid)
_ts_load_state $state

gap=""
if (( TS_LAST_PROMPT > 0 && now - TS_LAST_PROMPT >= GAP_MIN * 60 )); then
    gap=" · $(_ts_fmt_dur $(( now - TS_LAST_PROMPT ))) since your last message"
fi

TS_LAST_PROMPT=$now; TS_TURN_START=$now; TS_LAST_STAMP=$now
_ts_save_state $state 2>/dev/null

_ts_resolve_tz
warn=""
[[ -n $TS_TZ_WARN ]] && warn=" — WARNING: $TS_TZ_WARN, using $TS_TZ"
printf '[Now: %s%s%s]\n' "$(_ts_fmt_now $now)" "$gap" "$warn"
exit 0
