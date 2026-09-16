#!/usr/bin/env bash
# Checks nudge_undeadlined_poller.sh fires on an unbounded polling loop and
# stays quiet otherwise. A nudge that fires on everything gets ignored, so the
# quiet cases matter more than the loud one -- this hook runs on EVERY Bash
# call, so a false positive is expensive.
#
# The loud case is the real command from the 2026-08 incident: a health-check
# watchdog left running 31 days that held a Modal H100 warm at $96/day.

# shellcheck disable=SC2016  # the single-quoted cases are literal command text
set -uo pipefail

DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../claude/hooks" && pwd)
HOOK="$DIR/nudge_undeadlined_poller.sh"
WORK=""
for base in "${TMPDIR:-}" /tmp/claude /tmp; do
    if [ -z "$base" ] || [ ! -d "$base" ] || [ ! -w "$base" ]; then
        continue
    fi
    WORK=$(mktemp -d -p "$base" 2>/dev/null) && break
done
[ -n "$WORK" ] || { echo "cannot make a temp dir"; exit 1; }
trap 'rm -rf "$WORK"' EXIT
FEATURES="$WORK/features.conf"
printf 'nudges.undeadlined-poller = on\n' > "$FEATURES"
export CLAUDE_HOOK_FEATURES_FILE="$FEATURES"

fails=0

run_hook() {
    printf '{"tool_input":{"command":%s}}' "$(jq -Rn --arg c "$1" '$c')" | "$HOOK"
}

expect_fires() {
    local out
    out=$(run_hook "$1")
    if printf '%s' "$out" | grep -q "timeout 12h"; then
        printf 'ok    fires:  %s\n' "$1"
    else
        printf 'FAIL  silent, expected a nudge: %s\n' "$1"
        fails=$((fails + 1))
    fi
}

expect_silent() {
    local out
    out=$(run_hook "$1")
    if [ -z "$out" ]; then
        printf 'ok    silent: %s\n' "$1"
    else
        printf 'FAIL  fired, expected silence: %s\n' "$1"
        fails=$((fails + 1))
    fi
}

echo "--- should fire ---"
# The actual command from the incident.
expect_fires 'bash scripts/vllm-endpoint-watchdog.sh 180'
expect_fires 'while true; do curl -s "$URL/health"; sleep 180; done'
expect_fires 'while :; do probe; sleep 60; done'
expect_fires './keep-warm.sh'
expect_fires 'nohup ./endpoint-keepalive.sh &'

echo "--- already bounded, so silent ---"
expect_silent 'timeout 12h bash scripts/vllm-endpoint-watchdog.sh 180'
expect_silent 'gtimeout 1h ./keep-warm.sh'
expect_silent 'bash scripts/vllm-endpoint-watchdog.sh 180 --max-age 43200'
expect_silent 'systemd-run --user --unit=watchdog ./watchdog.sh'
expect_silent 'jexp uv run python -m train'
expect_silent 'bash ./watchdog.sh --no-deadline'

echo "--- reading or managing, not running, so silent ---"
expect_silent 'grep -n watchdog scripts/run.sh'
expect_silent 'rg watchdog'
expect_silent 'cat scripts/vllm-endpoint-watchdog.sh'
expect_silent 'ls -l scripts/watchdog.sh'
expect_silent 'ps aux | grep watchdog'
expect_silent 'pkill -f watchdog'
expect_silent 'kill 1455475'
expect_silent 'git commit -m "add the watchdog"'
expect_silent 'systemctl --user status watchdog.timer'
expect_silent 'tail -f logs/watchdog.log'
expect_silent 'shellcheck scripts/watchdog.sh'

echo "--- ordinary commands, so silent ---"
expect_silent 'uv run pytest -q'
expect_silent 'for i in 1 2 3; do echo "$i"; sleep 1; done'
expect_silent 'sleep 5'
expect_silent 'echo hello'

echo
if [ "$fails" -eq 0 ]; then
    echo "PASS: all cases behaved"
else
    echo "FAIL: $fails case(s) wrong"
fi
exit "$fails"
