#!/usr/bin/env bash
# Regression tests for custom_bins/alfred-watchdog.
#
# The tool kills processes, so the two properties that matter are symmetric:
# it must kill a wedged Alfred descendant, and it must NOT kill anything else.
# Both are tested against real processes rather than mocks — a spinning
# `osascript` is cheap to create and is exactly what the tool sees in production.
#
# Uses ALFRED_WATCHDOG_ANCHOR_PID to stand in for Alfred so the kill path can be
# exercised without driving the real app.
#
# macOS only (osascript, BSD ps). Run outside a sandbox: pgrep needs sysmond.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WATCHDOG="$SCRIPT_DIR/../custom_bins/alfred-watchdog"

PASS=0
FAIL=0
SPAWNED=()

pass() { printf '  \033[0;32mPASS\033[0m %s\n' "$*"; PASS=$((PASS + 1)); }
fail() { printf '  \033[0;31mFAIL\033[0m %s\n' "$*"; FAIL=$((FAIL + 1)); }

# Every spawned process is registered here and reaped on any exit path, so a
# failing assertion can never leave a core spinning.
cleanup() {
  for pid in ${SPAWNED[@]+"${SPAWNED[@]}"}; do
    kill -9 "$pid" 2>/dev/null || true
  done
}
trap cleanup EXIT INT TERM

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "alfred-watchdog is macOS-only; skipping."
  exit 0
fi

if ! pgrep -x osascript >/dev/null 2>&1 && [[ $? -gt 1 ]]; then
  echo "pgrep cannot read the process list (sandboxed?); skipping."
  exit 0
fi

echo "=== alfred-watchdog ==="

# --- 1. --help works and exits 0 -------------------------------------------
if "$WATCHDOG" --help 2>&1 | grep -q "kill Alfred workflow scripts"; then
  pass "--help prints usage"
else
  fail "--help did not print usage"
fi

# --- 2. bad arguments are rejected ------------------------------------------
"$WATCHDOG" --age-minutes not-a-number >/dev/null 2>&1
if [[ $? -eq 64 ]]; then
  pass "rejects non-numeric --age-minutes with exit 64"
else
  fail "did not exit 64 on bad --age-minutes"
fi

"$WATCHDOG" --nonsense-flag >/dev/null 2>&1
if [[ $? -eq 64 ]]; then
  pass "rejects unknown flag with exit 64"
else
  fail "did not exit 64 on unknown flag"
fi

# --- 3. a spinner that is NOT a descendant is left alone ---------------------
# The safety property. Age gate wide open and CPU threshold low, so only the
# ancestry check can save it.
osascript -e 'repeat' -e 'end repeat' &
OUTSIDER=$!
SPAWNED+=("$OUTSIDER")
sleep 3

"$WATCHDOG" --age-minutes 0 --cpu-threshold 50 --sample-gap 2 >/dev/null 2>&1
if kill -0 "$OUTSIDER" 2>/dev/null; then
  pass "leaves a spinning osascript that is not an Alfred descendant alone"
else
  fail "KILLED a process outside the Alfred tree"
fi
kill -9 "$OUTSIDER" 2>/dev/null || true

# --- 4. a busy-but-not-wedged process survives the two-sample check ----------
# Sleeps at ~0% CPU: stands in for a blocked `display dialog`, which is the
# case an age-only watchdog would wrongly kill.
osascript -e 'delay 30' &
IDLER=$!
SPAWNED+=("$IDLER")
sleep 2
IDLER_PARENT=$$

ALFRED_WATCHDOG_ANCHOR_PID=$IDLER_PARENT "$WATCHDOG" \
  --age-minutes 0 --cpu-threshold 50 --sample-gap 2 >/dev/null 2>&1
if kill -0 "$IDLER" 2>/dev/null; then
  pass "leaves an idle (0% CPU) descendant alone even when anchored to its parent"
else
  fail "KILLED an idle descendant — CPU gate is not working"
fi
kill -9 "$IDLER" 2>/dev/null || true

# --- 5. a wedged descendant IS killed ---------------------------------------
# The core function. Anchored to this shell, so the spinner below is a genuine
# descendant and every gate (ancestry, age, CPU, two samples) should fire.
osascript -e 'repeat' -e 'end repeat' &
WEDGED=$!
SPAWNED+=("$WEDGED")
sleep 3

ALFRED_WATCHDOG_ANCHOR_PID=$$ "$WATCHDOG" \
  --age-minutes 0 --cpu-threshold 50 --sample-gap 2 >/dev/null 2>&1
sleep 1
if kill -0 "$WEDGED" 2>/dev/null; then
  fail "did NOT kill a wedged descendant"
  kill -9 "$WEDGED" 2>/dev/null || true
else
  pass "kills a wedged (100% CPU) Alfred descendant"
fi

# --- 6. --dry-run kills nothing ---------------------------------------------
osascript -e 'repeat' -e 'end repeat' &
DRY=$!
SPAWNED+=("$DRY")
sleep 3

ALFRED_WATCHDOG_ANCHOR_PID=$$ "$WATCHDOG" \
  --dry-run --age-minutes 0 --cpu-threshold 50 --sample-gap 2 >/dev/null 2>&1
if kill -0 "$DRY" 2>/dev/null; then
  pass "--dry-run reports without killing"
else
  fail "--dry-run killed a process"
fi
kill -9 "$DRY" 2>/dev/null || true

# --- 7. the age gate holds a young spinner ----------------------------------
osascript -e 'repeat' -e 'end repeat' &
YOUNG=$!
SPAWNED+=("$YOUNG")
sleep 3

ALFRED_WATCHDOG_ANCHOR_PID=$$ "$WATCHDOG" \
  --age-minutes 10 --cpu-threshold 50 --sample-gap 2 >/dev/null 2>&1
if kill -0 "$YOUNG" 2>/dev/null; then
  pass "age gate spares a spinner younger than --age-minutes"
else
  fail "killed a spinner below the age threshold"
fi
kill -9 "$YOUNG" 2>/dev/null || true

echo
printf 'passed %d, failed %d\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
