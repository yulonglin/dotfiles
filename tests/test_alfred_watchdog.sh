#!/usr/bin/env bash
# Regression tests for custom_bins/alfred-watchdog.
#
# The tool kills processes, so the two properties that matter are symmetric:
# it must kill a wedged Alfred descendant, and it must NOT kill anything else.
# Both are tested against real processes rather than mocks — a spinning
# `osascript` is cheap to create and is exactly what the tool sees in production.
#
# Uses --test-anchor-pid to stand in for Alfred so the kill path can be
# exercised without driving the real app.
#
# SAFETY RULE FOR THIS FILE: no kill-enabled run may ever be anchored at a
# process whose descendants include anything this suite did not spawn. That rules
# out the real Alfred (an earlier version pointed a kill-enabled run straight at
# it) and it also rules out $$, the test shell — anything the developer
# backgrounded from the same shell before running the tests is a genuine
# descendant of $$. Every spinner therefore gets its own dedicated anchor whose
# tree contains only that spinner. The two runs that must resolve the real
# anchor, to prove the environment cannot redirect it, are --dry-run.
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
#
# Each registered PID's children are swept too, and that belt-and-braces pass is
# not paranoia: when this file recorded the wrong PID, killing only the recorded
# one orphaned the real spinner, and several runs' worth piled up unnoticed. The
# sweep is scoped to children of processes this suite started, so it can never
# reach anything else — a bare `pkill -x osascript` would also kill the user's
# live Alfred workflows and is exactly the mistake this tool is meant to avoid.
cleanup() {
  local pid child
  for pid in ${SPAWNED[@]+"${SPAWNED[@]}"}; do
    for child in $(pgrep -P "$pid" 2>/dev/null); do
      kill -9 "$child" 2>/dev/null || true
    done
    kill -9 "$pid" 2>/dev/null || true
  done
}
trap cleanup EXIT INT TERM

# Exit 77, not 0. tests/run-all.sh maps 0 to PASS and reserves 77 for "this suite
# decided it cannot run here" — so skipping with 0 would report a green run on
# Linux CI, or on a sandboxed Mac, having executed no assertion at all. A test for
# a process killer claiming to have passed without running is worse than useless.
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "SKIP: alfred-watchdog is macOS-only"
  exit 77
fi

# Capture pgrep's status on its own line. Written as `! pgrep … && [[ $? -gt 1 ]]`
# this never fired: the `!` turns pgrep's failure into a success, so $? was 0 and
# a sandboxed run charged ahead and failed loudly instead of skipping.
pgrep -x osascript >/dev/null 2>&1
pgrep_probe=$?
if [[ $pgrep_probe -gt 1 ]]; then
  echo "SKIP: pgrep cannot read the process list (sandboxed?)"
  exit 77
fi

# Runs "$@" inside a dedicated wrapper process and sets ANCHOR and SPINNER.
#
# The subshell becomes a real process, starts the command as its only child, then
# `exec sleep`s so it keeps that PID and stays alive as a stable anchor. So
# ANCHOR's entire descendant tree is exactly one process: SPINNER. Anchoring the
# watchdog there means a kill-enabled run cannot reach anything else on the
# machine, whatever else the developer happens to be running.
ANCHOR=""
SPINNER=""
spawn_under_anchor() {
  local pidfile
  pidfile="$(mktemp "${TMPDIR:-/tmp}/alfred-wd-test.XXXXXX")"

  ( "$@" & echo $! > "$pidfile"; exec sleep 300 ) &
  ANCHOR=$!
  SPAWNED+=("$ANCHOR")

  local i
  for ((i = 0; i < 50; i++)); do
    [[ -s "$pidfile" ]] && break
    sleep 0.1
  done
  SPINNER="$(cat "$pidfile" 2>/dev/null)"
  rm -f "$pidfile"

  if [[ -z "$SPINNER" ]]; then
    fail "harness could not start a spinner under its anchor"
    return 1
  fi
  SPAWNED+=("$SPINNER")
}

# True while a pid is a real, running process. `kill -0` is not enough: it
# succeeds for a zombie, and a killed spinner stays a zombie until its parent
# reaps it — here the parent is an `exec sleep` anchor that never does. Using
# kill -0 made "did the watchdog kill it?" answer "no" for a process it had in
# fact killed, which is also how the same mistake in the tool itself was found.
is_running() {
  local st
  st="$(ps -o state= -p "$1" 2>/dev/null)" || return 1
  st="$(printf '%s' "$st" | tr -d ' ')"
  [[ -n "$st" && "$st" != Z* ]]
}

# `exec` is load-bearing in all three. Without it, `fn &` forks a subshell that
# then runs osascript as a *child*, so `$!` records the subshell's PID and not
# the osascript's. Two consequences, both bad: the assertions check whether the
# wrapper died rather than the spinner, and cleanup kills the wrapper and leaves
# the osascript orphaned and still spinning. That is exactly how eleven runaway
# osascript processes at ~70% CPU each accumulated while developing this file —
# the suite for a runaway-process killer was itself leaking runaway processes.
# With `exec`, the subshell *becomes* the osascript and keeps the PID.
spin_forever()  { exec osascript -e 'repeat' -e 'end repeat'; }
idle_quietly()  { exec osascript -e 'delay 30'; }
spin_then_idle() {
  exec osascript -e 'set deadline to (current date) + 4' \
                 -e 'repeat while (current date) < deadline' \
                 -e 'end repeat' \
                 -e 'delay 60'
}
# Mostly idle, then hot: the shape the cumulative-CPU gate exists to spare. It
# stands in for a workflow that waited on a dialog and then started real work, so
# it is old enough and hot right now, but has spent almost none of its life
# burning CPU.
idle_then_spin() {
  exec osascript -e 'delay 12' \
                 -e 'repeat' \
                 -e 'end repeat'
}

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

"$WATCHDOG" --test-anchor-pid not-a-pid >/dev/null 2>&1
if [[ $? -eq 64 ]]; then
  pass "rejects non-numeric --test-anchor-pid with exit 64"
else
  fail "did not exit 64 on bad --test-anchor-pid"
fi

# Leading zeros pass the digit validator but used to reach bash arithmetic as
# octal, so "08" failed at the point of use rather than at validation — long
# after the caller could tell why.
OCTAL_OUT="$("$WATCHDOG" --age-minutes 08 --cpu-threshold 09 --sample-gap 02 --dry-run 2>&1)"
OCTAL_RC=$?
if [[ $OCTAL_RC -eq 0 ]] && ! grep -qi 'value too great\|invalid arithmetic\|syntax error' <<< "$OCTAL_OUT"; then
  pass "leading-zero numeric options are read as base 10"
else
  fail "leading-zero options broke arithmetic (exit $OCTAL_RC)"
fi

# --- 3. a spinner outside the anchor's tree is left alone --------------------
# The safety property: age gate wide open and CPU threshold low, so only the
# ancestry check can spare it. The spinner and the anchor are deliberately
# unrelated processes.
spawn_under_anchor spin_forever
OUTSIDER="$SPINNER"
sleep 120 &
LONE_ANCHOR=$!
SPAWNED+=("$LONE_ANCHOR")
sleep 3

"$WATCHDOG" --test-anchor-pid "$LONE_ANCHOR" \
  --age-minutes 0 --cpu-threshold 50 --sample-gap 2 >/dev/null 2>&1
if is_running "$OUTSIDER"; then
  pass "leaves a spinning osascript outside the anchor's tree alone"
else
  fail "KILLED a process outside the anchor's tree"
fi
kill -9 "$OUTSIDER" "$LONE_ANCHOR" 2>/dev/null || true

# --- 4. an idle descendant is spared ----------------------------------------
# Stands in for a blocked `display dialog`: present and old, but ~0% CPU, which
# is the case an age-only watchdog would wrongly kill.
spawn_under_anchor idle_quietly
IDLER="$SPINNER"
sleep 2

"$WATCHDOG" --test-anchor-pid "$ANCHOR" \
  --age-minutes 0 --cpu-threshold 50 --sample-gap 2 >/dev/null 2>&1
if is_running "$IDLER"; then
  pass "leaves an idle (0% CPU) descendant alone"
else
  fail "KILLED an idle descendant — CPU gate is not working"
fi
kill -9 "$IDLER" 2>/dev/null || true

# --- 5. a wedged descendant IS killed ---------------------------------------
# The core function: every gate (ancestry, age, cumulative CPU, live CPU, two
# samples) should fire. Asserts exit 0 too, since a survival-only check would
# also pass if the watchdog errored out before doing anything.
spawn_under_anchor spin_forever
WEDGED="$SPINNER"
sleep 3

"$WATCHDOG" --test-anchor-pid "$ANCHOR" \
  --age-minutes 0 --cpu-threshold 50 --sample-gap 2 >/dev/null 2>&1
WEDGED_RC=$?
sleep 1
if [[ $WEDGED_RC -ne 0 ]]; then
  fail "watchdog exited $WEDGED_RC on the wedged case (expected 0)"
  kill -9 "$WEDGED" 2>/dev/null || true
elif is_running "$WEDGED"; then
  fail "did NOT kill a wedged descendant"
  kill -9 "$WEDGED" 2>/dev/null || true
else
  pass "kills a wedged (100% CPU) Alfred descendant"
fi

# --- 6. --dry-run kills nothing ---------------------------------------------
spawn_under_anchor spin_forever
DRY="$SPINNER"
sleep 3

"$WATCHDOG" --test-anchor-pid "$ANCHOR" \
  --dry-run --age-minutes 0 --cpu-threshold 50 --sample-gap 2 >/dev/null 2>&1
if is_running "$DRY"; then
  pass "--dry-run reports without killing"
else
  fail "--dry-run killed a process"
fi
kill -9 "$DRY" 2>/dev/null || true

# --- 7. the age gate holds a young spinner ----------------------------------
spawn_under_anchor spin_forever
YOUNG="$SPINNER"
sleep 3

"$WATCHDOG" --test-anchor-pid "$ANCHOR" \
  --age-minutes 10 --cpu-threshold 50 --sample-gap 2 >/dev/null 2>&1
if is_running "$YOUNG"; then
  pass "age gate spares a spinner younger than --age-minutes"
else
  fail "killed a spinner below the age threshold"
fi
kill -9 "$YOUNG" 2>/dev/null || true

# --- 8. the SECOND sample can reject a candidate ----------------------------
# Without this, nothing exercises second-sample rejection: the idle fixture never
# passes the first CPU gate and the wedged one stays hot, so deleting the second
# sample entirely would leave every other case green. This process spins ~4s then
# idles, so with a 6s gap it is hot on the first sample and cool on the second.
# Asserts the tool's own rejection line, because survival alone would also hold
# if the watchdog crashed early.
spawn_under_anchor spin_then_idle
COOLING="$SPINNER"
sleep 1

COOL_OUT="$("$WATCHDOG" --test-anchor-pid "$ANCHOR" \
  --age-minutes 0 --cpu-threshold 50 --sample-gap 6 2>&1)"
COOL_RC=$?

if [[ $COOL_RC -ne 0 ]]; then
  fail "watchdog exited $COOL_RC on the cooling case (expected 0)"
elif ! grep -q "working, not wedged" <<< "$COOL_OUT"; then
  fail "cooling process never reached the second sample — rejection path untested"
elif is_running "$COOLING"; then
  pass "a candidate that cools between samples is spared at confirmation"
else
  fail "KILLED a process that cooled between samples"
fi
kill -9 "$COOLING" 2>/dev/null || true

# --- 9. the anchor cannot be set from the environment ------------------------
# Regression test for a review finding, and then for the incomplete fix of it.
# The anchor was originally read from ALFRED_WATCHDOG_ANCHOR_PID, so a shell
# profile or direnv .envrc could silently point the tool at a tree outside Alfred
# and have it kill things there. Renaming it to a flag was NOT sufficient on its
# own: the new name was still read from the ambient environment because the
# variable was never initialized, and the first version of this test missed that
# by only checking the old name. Both names are checked now.
#
# Proving this needs runs with NO --test-anchor-pid, so the anchor resolves to
# the real Alfred — hence --dry-run, inspecting what the tool says it *would*
# kill rather than letting it kill anything.
spawn_under_anchor spin_forever
ENVTEST="$SPINNER"
ENVTEST_ANCHOR="$ANCHOR"
sleep 3

for var in ALFRED_WATCHDOG_ANCHOR_PID TEST_ANCHOR_PID; do
  ENV_OUT="$(env "$var=$ENVTEST_ANCHOR" "$WATCHDOG" \
    --dry-run --age-minutes 0 --cpu-threshold 50 --sample-gap 2 2>&1)"
  if grep -q "$ENVTEST" <<< "$ENV_OUT"; then
    fail "$var in the environment still redirects the anchor"
  elif grep -q "test anchor" <<< "$ENV_OUT"; then
    fail "$var in the environment was accepted as a test anchor"
  else
    pass "$var in the environment does not redirect the anchor"
  fi
done
kill -9 "$ENVTEST" 2>/dev/null || true

# --- 10. anchor PID 1 matches nothing rather than everything -----------------
# The walk stops at pid <= 1, so anchoring to launchd makes every process a
# NON-candidate. That is the fail-safe direction, but it is an accident of the
# loop bound rather than an explicit rule, and a future tidy-up of the walk could
# silently invert it into "every process descends from pid 1" — which would make
# every osascript on the machine eligible. Pinned deliberately.
spawn_under_anchor spin_forever
ROOTTEST="$SPINNER"
sleep 3

ROOT_OUT="$("$WATCHDOG" --test-anchor-pid 1 \
  --dry-run --age-minutes 0 --cpu-threshold 50 --sample-gap 2 2>&1)"
if grep -q "$ROOTTEST" <<< "$ROOT_OUT"; then
  fail "anchor PID 1 made everything a candidate — the ancestry walk inverted"
else
  pass "anchor PID 1 matches nothing rather than everything"
fi
kill -9 "$ROOTTEST" 2>/dev/null || true

# --- 11. the cumulative-CPU gate spares a mostly-idle process ----------------
# The gate's own fixture. Nothing else proves it: the idle case fails the live
# CPU check, the wedged case has burned CPU for its whole life, and the cooling
# case is rejected at the second sample instead. This one is old enough AND hot
# right now, so age and %cpu both pass — only the duty-ratio test can save it.
# Deleting that gate would leave every other case green and kill this process.
spawn_under_anchor idle_then_spin
BURSTY="$SPINNER"
sleep 14   # 12s idle, then ~2s of spinning: hot now, but ~14% of life on CPU

"$WATCHDOG" --test-anchor-pid "$ANCHOR" \
  --age-minutes 0 --cpu-threshold 50 --sample-gap 2 >/dev/null 2>&1
if is_running "$BURSTY"; then
  pass "cumulative-CPU gate spares a mostly-idle process that just turned hot"
else
  fail "KILLED a mostly-idle process during a short burst — duty-ratio gate is not working"
fi
kill -9 "$BURSTY" 2>/dev/null || true

echo
printf 'passed %d, failed %d\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
