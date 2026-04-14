#!/usr/bin/env bash
# UserPromptSubmit hook: outputs current local time for Claude context.
# Reads timezone from data/GOALS.md (timezone: line) or falls back to UTC.

GOALS_FILE="$(git rev-parse --show-toplevel 2>/dev/null)/data/GOALS.md"
TZ_NAME=""
if [ -f "$GOALS_FILE" ]; then
    TZ_NAME=$(grep -m1 '^- timezone:' "$GOALS_FILE" 2>/dev/null | sed "s/.*timezone: *//;s/^['\"]//;s/['\"]$//")
fi
TZ_NAME="${TZ_NAME:-UTC}"

# Derive short label (Asia/Singapore → SGT, America/New_York → EST, etc.)
TZ_LABEL=$(TZ="$TZ_NAME" date '+%Z' 2>/dev/null || echo "$TZ_NAME")

printf '[Current time: %s %s]\n' "$(TZ="$TZ_NAME" date '+%Y-%m-%d %H:%M')" "$TZ_LABEL"
