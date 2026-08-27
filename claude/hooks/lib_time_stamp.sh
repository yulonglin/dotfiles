#!/usr/bin/env bash
# shellcheck disable=SC2034,SC1091  # state vars are shared with the sourced lib
# Shared helpers for the time-awareness hooks (inject_timestamp.sh on
# UserPromptSubmit, elapsed_stamp.sh on PostToolUse). Sourced, not executed.
#
# Why these exist: agents estimate elapsed time almost entirely from timestamps
# already in context (Ofengenden & Andriushchenko 2026: scrubbing them roughly
# doubles retrospective error), and nothing else stamps the inside of a long
# tool loop. Format follows the Claude Code precedent in issues #24182/#34530:
# local date+time with zone, plus UTC, plus a pre-computed delta so the model
# never has to do date arithmetic itself.
#
# Off switches (a stated date is a demonstrated backdoor-trigger surface, so
# model-organism repos must be able to silence this):
#   global   : `time = off` (or time.prompt-stamp / time.elapsed-stamp) in
#              claude/hooks/features.conf, via hook_feature.sh
#   per-repo : a marker file .claude/no-time-stamps in the project root
#   per-shell: CLAUDE_TIME_STAMPS=off

_ts_now() { date +%s; }

# Resolve the local IANA zone. Order: CLAUDE_LOCAL_TZ, TZ, /etc/timezone,
# /etc/localtime symlink, UTC. Sets TS_TZ and TS_TZ_WARN.
_ts_resolve_tz() {
    TS_TZ=""
    TS_TZ_WARN=""
    local cand
    for cand in "${CLAUDE_LOCAL_TZ:-}" "${TZ:-}"; do
        [ -n "$cand" ] || continue
        if [ -f "/usr/share/zoneinfo/$cand" ]; then
            TS_TZ="$cand"; return
        fi
        TS_TZ_WARN="invalid zone '$cand' (not in /usr/share/zoneinfo)"
    done
    if [ -r /etc/timezone ]; then
        cand=$(head -1 /etc/timezone 2>/dev/null)
        if [ -n "$cand" ] && [ -f "/usr/share/zoneinfo/$cand" ]; then
            TS_TZ="$cand"; return
        fi
    fi
    if [ -L /etc/localtime ]; then
        cand=$(readlink /etc/localtime 2>/dev/null)
        cand="${cand##*zoneinfo/}"
        if [ -n "$cand" ] && [ -f "/usr/share/zoneinfo/$cand" ]; then
            TS_TZ="$cand"; return
        fi
    fi
    TS_TZ="UTC"
}

# "2h13m", "45m", "3d 4h", "<1m"
_ts_fmt_dur() {
    local s=$1
    if [ "$s" -lt 60 ]; then printf '<1m'; return; fi
    local d=$((s / 86400)) h=$((s % 86400 / 3600)) m=$((s % 3600 / 60))
    if [ "$d" -gt 0 ]; then printf '%dd %dh' "$d" "$h"
    elif [ "$h" -gt 0 ]; then printf '%dh%02dm' "$h" "$m"
    else printf '%dm' "$m"; fi
}

# GNU date takes -d @epoch; BSD/macOS date takes -r epoch.
_ts_date() {
    local when=$1 fmt=$2
    date -d "@$when" "$fmt" 2>/dev/null || date -r "$when" "$fmt"
}

# "Thu 2026-08-27 02:40 PDT (UTC-07:00) · 09:40 UTC"
_ts_fmt_now() {
    local now=$1 off local_s utc_s
    off=$(TZ="$TS_TZ" _ts_date "$now" '+%z')
    off="${off:0:3}:${off:3:2}"
    local_s=$(TZ="$TS_TZ" _ts_date "$now" '+%a %Y-%m-%d %H:%M %Z')
    utc_s=$(TZ=UTC _ts_date "$now" '+%H:%M')
    if [ "$TS_TZ" = "UTC" ]; then
        printf '%s' "$local_s"
    else
        printf '%s (UTC%s) · %s UTC' "$local_s" "$off" "$utc_s"
    fi
}

# Session-scoped state: last_prompt, turn_start, last_stamp (epoch seconds).
_ts_state_path() {
    printf '%s/claude-time-%s.state' "${CLAUDE_TIME_STATE_DIR:-${TMPDIR:-/tmp}}" "$1"
}

_ts_load_state() {
    TS_LAST_PROMPT=0; TS_TURN_START=0; TS_LAST_STAMP=0
    local f=$1 k v
    [ -r "$f" ] || return 0
    while IFS='=' read -r k v; do
        case "$k" in
            last_prompt) TS_LAST_PROMPT=${v:-0} ;;
            turn_start)  TS_TURN_START=${v:-0} ;;
            last_stamp)  TS_LAST_STAMP=${v:-0} ;;
        esac
    done < "$f"
}

_ts_save_state() {
    local f=$1
    printf 'last_prompt=%s\nturn_start=%s\nlast_stamp=%s\n' \
        "$TS_LAST_PROMPT" "$TS_TURN_START" "$TS_LAST_STAMP" > "$f.tmp.$$" \
        && mv -f "$f.tmp.$$" "$f"
}

# Returns 0 when stamps are silenced for this project/shell.
_ts_disabled() {
    case "${CLAUDE_TIME_STAMPS:-on}" in off|0|false|no) return 0 ;; esac
    local root="${CLAUDE_PROJECT_DIR:-$PWD}"
    [ -e "$root/.claude/no-time-stamps" ]
}

# Session id from hook stdin JSON, falling back to a per-process key.
_ts_session_id() {
    local input=$1 sid=""
    if command -v jq >/dev/null 2>&1; then
        sid=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
    fi
    [ -n "$sid" ] || sid="pid$PPID"
    printf '%s' "$sid" | tr -c 'A-Za-z0-9_-' '_'
}
