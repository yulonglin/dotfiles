#!/usr/bin/env bash
# Checks nudge_undeadlined_poller.sh fires on an unbounded polling loop and
# stays quiet otherwise. A nudge that fires on everything gets ignored, so the
# quiet cases matter more than the loud one -- this hook runs on EVERY Bash
# call, so a false positive is expensive.
#
# The loud case is the real command from the 2026-08 incident: a health-check
# watchdog left running 31 days that held a Modal H100 warm at $96/day.
#
# Several cases exist because an adversarial review found the corresponding
# defect. They are marked [review] and are the ones most worth keeping:
#   - a per-request --connect-timeout is not a deadline for the loop
#   - a prefix exemption must not cover a launch that follows it in the same
#     command, and must not suppress inspection preceded by cd
#   - systemd-run/jexp bound resources, not lifetime
#   - the advice has to reach Claude (additionalContext), not just the user

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
expect_fires 'bash scripts/vllm-endpoint-watchdog.sh 180'
expect_fires 'while true; do curl -s "$URL/health"; sleep 180; done'
expect_fires 'while :; do probe; sleep 60; done'
expect_fires './keep-warm.sh'
expect_fires 'nohup ./endpoint-keepalive.sh &'
# [review] a per-request timeout bounds one call, not the loop
expect_fires 'while true; do curl --connect-timeout 5 "$URL/health"; sleep 180; done'
expect_fires 'while true; do timeout 5 curl "$URL/health"; sleep 180; done'
# [review] an exempt first command must not cover the relaunch after it
expect_fires 'pkill -f vllm-endpoint-watchdog.sh; nohup bash scripts/vllm-endpoint-watchdog.sh 180 &'
expect_fires 'echo restarting && bash ./watchdog.sh'
# [review] these cap resources, not lifetime
expect_fires 'systemd-run --user --unit=wd bash ./watchdog.sh'
expect_fires 'jexp bash ./watchdog.sh'
# [review] a lifetime flag elsewhere must not mask the real launch
expect_fires 'echo "use --max-age next time"; bash ./watchdog.sh'
# [review] canonical unbounded pollers that a naive version missed
expect_fires 'watch -n 180 curl -s "$URL/health"'
expect_fires 'while true; do curl -s "$URL/health"; done'
expect_fires 'until curl -sf "$URL/health"; do sleep 60; done'
expect_fires 'while [ 1 = 1 ]; do probe; sleep 60; done'
expect_fires 'time bash ./watchdog.sh'

echo "--- genuinely bounded, so silent ---"
expect_silent 'timeout 12h bash scripts/vllm-endpoint-watchdog.sh 180'
expect_silent 'gtimeout 1h ./keep-warm.sh'
expect_silent 'nohup timeout 12h bash ./watchdog.sh &'
expect_silent 'bash scripts/vllm-endpoint-watchdog.sh 180 --max-age 43200'
expect_silent 'systemd-run --user --property=RuntimeMaxSec=3600 bash ./watchdog.sh'
expect_silent 'bash ./watchdog.sh --no-deadline'
expect_silent 'timeout 6h bash -c "while true; do probe; sleep 60; done"'

echo "--- reading or managing, not running, so silent ---"
expect_silent 'grep -n watchdog scripts/run.sh'
expect_silent 'rg watchdog'
expect_silent 'cat scripts/vllm-endpoint-watchdog.sh'
# [review] inspection preceded by cd must not warn
expect_silent 'cd /repo && cat scripts/watchdog.sh'
expect_silent 'cd /repo && grep -n watchdog scripts/run.sh'
expect_silent 'ls -l scripts/watchdog.sh'
expect_silent 'ps aux | grep watchdog'
expect_silent 'pkill -f watchdog'
expect_silent 'kill 1455475'
expect_silent 'git commit -m "add the watchdog"'
expect_silent 'systemctl --user status watchdog.timer'
expect_silent 'tail -f logs/watchdog.log'
expect_silent 'shellcheck scripts/watchdog.sh'

echo "--- [review] the word is in the argument, not the thing being run ---"
# These are the class that would have trained the ignore reflex within a week.
expect_silent 'mv watchdog.sh archive/'
expect_silent 'cp watchdog.sh /tmp/'
expect_silent 'command cp watchdog.sh /tmp/'
expect_silent 'rm keep-warm.sh'
expect_silent 'mkdir keepalive'
expect_silent 'sudo systemctl restart watchdog.service'
expect_silent 'docker logs watchdog'
expect_silent 'kubectl get pods -l app=watchdog'
expect_silent 'uv run python analyze_watchdog.py --rows 100'
expect_silent 'nohup python analyze_watchdog.py &'
expect_silent 'eza --tree watchdog/'
expect_silent 'cd logs && ls watchdog-2026-09.log'
expect_silent 'wc -l tmp/vllm-watchdog.log'

echo "--- ordinary commands, so silent ---"
expect_silent 'echo "wait until done"; sleep 5'
expect_silent 'uv run pytest -q'
expect_silent 'for i in 1 2 3; do echo "$i"; sleep 1; done'
expect_silent 'sleep 5'
expect_silent 'echo hello'

echo "--- the advice has to reach Claude, not just the user ---"
out=$(run_hook 'bash scripts/vllm-endpoint-watchdog.sh 180')
for field in '.systemMessage' '.hookSpecificOutput.additionalContext'; do
    if printf '%s' "$out" | jq -e "$field | test(\"timeout 12h\")" >/dev/null 2>&1; then
        printf 'ok    carries %s\n' "$field"
    else
        printf 'FAIL  missing or empty: %s\n' "$field"
        fails=$((fails + 1))
    fi
done
if printf '%s' "$out" | jq -e '.hookSpecificOutput.hookEventName == "PreToolUse"' >/dev/null 2>&1; then
    printf 'ok    hookEventName is PreToolUse\n'
else
    printf 'FAIL  hookEventName is not PreToolUse\n'
    fails=$((fails + 1))
fi

echo
if [ "$fails" -eq 0 ]; then
    echo "PASS: all cases behaved"
else
    echo "FAIL: $fails case(s) wrong"
fi
exit "$fails"
