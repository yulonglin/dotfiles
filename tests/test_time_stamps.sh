#!/usr/bin/env bash
# Pins the time-awareness hooks: stamp format, gap delta, PostToolUse throttle,
# timezone fallback warning, and every off switch. State lives in a temp dir so
# the test never touches a live session's clock.
set -uo pipefail

DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../claude/hooks" && pwd)
PROMPT="$DIR/inject_timestamp.sh"
ELAPSED="$DIR/elapsed_stamp.sh"
WORK=""
for base in "${TMPDIR:-}" /tmp/claude /tmp; do
    if [ -z "$base" ] || [ ! -d "$base" ] || [ ! -w "$base" ]; then continue; fi
    WORK=$(mktemp -d -p "$base" 2>/dev/null) && break
done
[ -n "$WORK" ] || { echo "cannot make a temp dir"; exit 1; }
trap 'rm -rf "$WORK"' EXIT
export CLAUDE_TIME_STATE_DIR="$WORK"
export CLAUDE_LOCAL_TZ=America/Los_Angeles
export CLAUDE_PROJECT_DIR="$WORK/proj"
mkdir -p "$CLAUDE_PROJECT_DIR"
unset CLAUDE_TIME_STAMPS

fails=0
ok()   { printf 'ok    %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; fails=$((fails + 1)); }
expect_empty() { if [ -z "$1" ]; then ok "$2"; else fail "$2, got: $1"; fi; }
run()  { printf '{"session_id":"%s"}' "$1" | "$2"; }
state() { printf '%s/claude-time-%s.state' "$WORK" "$1"; }

# 1. Prompt stamp: local date with zone, UTC offset, UTC clock, no gap on first prompt.
out=$(run s1 "$PROMPT")
if printf '%s' "$out" | grep -Eq '^\[Now: (Mon|Tue|Wed|Thu|Fri|Sat|Sun) [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2} P[DS]T \(UTC-0[78]:00\) · [0-9]{2}:[0-9]{2} UTC\]$'; then
    ok "prompt stamp format: $out"
else
    fail "prompt stamp format, got: $out"
fi

# 2. Gap delta appears only past CLAUDE_TIME_GAP_MIN.
now=$(date +%s)
printf 'last_prompt=%s\nturn_start=%s\nlast_stamp=%s\n' $((now - 8000)) $((now - 8000)) $((now - 8000)) > "$(state s2)"
out=$(run s2 "$PROMPT")
if printf '%s' "$out" | grep -q '2h13m since your last message'; then ok "gap delta 2h13m"; else fail "gap delta, got: $out"; fi
printf 'last_prompt=%s\nturn_start=%s\nlast_stamp=%s\n' $((now - 120)) $((now - 120)) $((now - 120)) > "$(state s3)"
out=$(run s3 "$PROMPT")
if printf '%s' "$out" | grep -q 'since your last message'; then fail "gap shown under threshold: $out"; else ok "no gap under threshold"; fi

# 3. Elapsed stamp: silent right after a prompt, fires once past the interval, then throttles.
run s4 "$PROMPT" >/dev/null
out=$(run s4 "$ELAPSED")
expect_empty "$out" "elapsed silent right after prompt"
printf 'last_prompt=%s\nturn_start=%s\nlast_stamp=%s\n' $((now - 1500)) $((now - 1500)) $((now - 400)) > "$(state s4)"
out=$(run s4 "$ELAPSED")
if printf '%s' "$out" | jq -e '.hookSpecificOutput.hookEventName == "PostToolUse" and (.hookSpecificOutput.additionalContext | test("^\\[Time check: 25m elapsed in this turn · now .* UTC\\]$"))' >/dev/null 2>&1; then
    ok "elapsed fires as additionalContext JSON: $out"
else
    fail "elapsed JSON, got: $out"
fi
out=$(run s4 "$ELAPSED")
expect_empty "$out" "elapsed throttled on the next call"

# 4. Elapsed with no prior prompt stamp (headless/resumed) starts the clock silently.
out=$(run s5 "$ELAPSED")
if [ -z "$out" ] && [ -r "$(state s5)" ]; then ok "elapsed bootstraps state silently"; else fail "elapsed bootstrap: '$out'"; fi

# 5. Timezone: invalid CLAUDE_LOCAL_TZ warns loudly and falls back; UTC prints no duplicate clock.
out=$(CLAUDE_LOCAL_TZ=Mars/Olympus run s6 "$PROMPT")
if printf '%s' "$out" | grep -q "WARNING: invalid zone 'Mars/Olympus'"; then ok "invalid zone warns"; else fail "invalid zone, got: $out"; fi
out=$(CLAUDE_LOCAL_TZ=UTC run s7 "$PROMPT")
if printf '%s' "$out" | grep -Eq '^\[Now: [A-Za-z]{3} [0-9-]{10} [0-9:]{5} UTC\]$'; then ok "UTC zone prints once"; else fail "UTC format, got: $out"; fi

# 6. Off switches: env, project marker, and the global feature flag via hook_feature.sh.
out=$(CLAUDE_TIME_STAMPS=off run s8 "$PROMPT"); expect_empty "$out" "env off switch"
mkdir -p "$CLAUDE_PROJECT_DIR/.claude" && touch "$CLAUDE_PROJECT_DIR/.claude/no-time-stamps"
out=$(run s9 "$PROMPT"); expect_empty "$out" "project marker off switch"
out=$(run s9 "$ELAPSED"); expect_empty "$out" "project marker silences elapsed too"
rm -f "$CLAUDE_PROJECT_DIR/.claude/no-time-stamps"
printf 'time = off\n' > "$WORK/features.conf"
out=$(printf '{"session_id":"s10"}' | CLAUDE_HOOK_FEATURES_FILE="$WORK/features.conf" bash "$DIR/hook_feature.sh" run time.prompt-stamp -- "$PROMPT")
expect_empty "$out" "features.conf time=off"
printf 'time = off\ntime.prompt-stamp = on\n' > "$WORK/features.conf"
out=$(printf '{"session_id":"s11"}' | CLAUDE_HOOK_FEATURES_FILE="$WORK/features.conf" bash "$DIR/hook_feature.sh" run time.prompt-stamp -- "$PROMPT")
if [ -n "$out" ]; then ok "child flag overrides parent"; else fail "child flag override"; fi

if [ "$fails" -eq 0 ]; then echo "all time-stamp tests passed"; else echo "$fails failure(s)"; exit 1; fi
