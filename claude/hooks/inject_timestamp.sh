#!/usr/bin/env bash
# UserPromptSubmit hook: outputs current local time for Claude context.
# Reads timezone from data/GOALS.md (timezone: line) and validates it against
# /usr/share/zoneinfo. Emits a loud warning if anything is wrong so the fallback
# to UTC doesn't silently mislead.

GOALS_FILE="$(git rev-parse --show-toplevel 2>/dev/null)/data/GOALS.md"
TZ_NAME=""
warn=""

if [ -z "$GOALS_FILE" ] || [ "$GOALS_FILE" = "/data/GOALS.md" ]; then
    warn="not in a git repo — cannot locate data/GOALS.md"
elif [ ! -f "$GOALS_FILE" ]; then
    warn="$GOALS_FILE not found"
else
    TZ_NAME=$(grep -m1 '^- timezone:' "$GOALS_FILE" 2>/dev/null | sed "s/.*timezone: *//;s/^['\"]//;s/['\"]$//")
    if [ -z "$TZ_NAME" ]; then
        warn="no '- timezone:' line in $GOALS_FILE"
    elif [ ! -f "/usr/share/zoneinfo/$TZ_NAME" ]; then
        warn="invalid timezone '$TZ_NAME' — not in /usr/share/zoneinfo. fix $GOALS_FILE"
        TZ_NAME=""
    fi
fi

TZ_NAME="${TZ_NAME:-UTC}"
# %z gives "-0300"; reformat to "-03:00" for readability
OFFSET_RAW=$(TZ="$TZ_NAME" date '+%z' 2>/dev/null)
OFFSET="${OFFSET_RAW:0:3}:${OFFSET_RAW:3:2}"

if [ -n "$warn" ]; then
    printf '[Current time: %s %s (UTC%s) — WARNING (falling back to UTC): %s]\n' \
        "$(TZ="$TZ_NAME" date '+%Y-%m-%d %H:%M')" "$TZ_NAME" "$OFFSET" "$warn"
else
    printf '[Current time: %s %s (UTC%s)]\n' \
        "$(TZ="$TZ_NAME" date '+%Y-%m-%d %H:%M')" "$TZ_NAME" "$OFFSET"
fi
