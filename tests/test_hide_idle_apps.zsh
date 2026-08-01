#!/usr/bin/env zsh
# Runs custom_bins/hide-idle-apps end to end with its two external dependencies
# stubbed: osascript (System Events) and tools/window-exposure. Both need a
# window server, which CI and sandboxes don't have - stubbing them is what lets
# the decision logic be tested at all rather than by eye on a real desktop.
#
# The script under test is HARDLINKED into the fake tree, never copied: it
# resolves its own config and helper paths from ${0:A:h}, and :A resolves
# symlinks back to the real repo. A hardlink is the same inode, so what runs
# here cannot drift from what ships.
set -uo pipefail

REPO="${0:A:h:h}"
# Under the repo's gitignored tmp/, not $TMPDIR: agent sandboxes commonly allow
# only one level below their temp root, and this tree is several deep.
mkdir -p "$REPO/tmp" || { print -ru2 -- "FATAL: cannot create $REPO/tmp"; exit 1 }
WORK="$(mktemp -d "$REPO/tmp/hide-idle-test.XXXXXX")" \
    || { print -ru2 -- "FATAL: mktemp -d under $REPO/tmp failed"; exit 1 }
# set -u does NOT catch a failed mktemp: WORK ends up set-but-EMPTY, and every
# path below is derived from it - ROOT would become /root and FAKEHOME /home,
# so the stub writes and the cleanup rm would land outside the repo entirely.
# Validate before deriving anything and before arming the trap: an `rm -rf`
# trap must never be installed on a variable we have not checked.
[[ -n "$WORK" && -d "$WORK" && "$WORK" == "$REPO/tmp/"* ]] \
    || { print -ru2 -- "FATAL: work dir not under $REPO/tmp: ${WORK:-<empty>}"; exit 1 }
ROOT="$WORK/root"
FAKEHOME="$WORK/home"
trap 'rm -rf "${WORK:?}"' EXIT   # only the temp tree this script just created
PASS=0 FAIL=0

check() {  # check <label> <haystack> <needle>
    if [[ "$2" == *"$3"* ]]; then
        print -r -- "  ok   $1"; (( PASS++ ))
    else
        print -r -- "  FAIL $1 -- expected to find: $3"; (( FAIL++ ))
    fi
}
check_not() {
    if [[ "$2" != *"$3"* ]]; then
        print -r -- "  ok   $1"; (( PASS++ ))
    else
        print -r -- "  FAIL $1 -- should NOT contain: $3"; (( FAIL++ ))
    fi
}

# --- fake tree -------------------------------------------------------------
mkdir -p "$ROOT/custom_bins" "$ROOT/config" "$ROOT/tools/window-exposure" \
         "$ROOT/bin" "$FAKEHOME"
ln "$REPO/custom_bins/hide-idle-apps"       "$ROOT/custom_bins/hide-idle-apps"
ln "$REPO/custom_bins/app-lifecycle-config" "$ROOT/custom_bins/app-lifecycle-config"
cp "$REPO/config/app-lifecycle.yaml" "$REPO/config/hide-idle.conf" "$ROOT/config/"

# Stands in for osascript: returns a canned System Events snapshot, and records
# hide attempts instead of performing them.
cat > "$ROOT/bin/osascript" <<'STUB'
#!/usr/bin/env zsh
if [[ "$*" == *"set visible"* ]]; then
    print -r -- "$*" >> "${STUB_HIDE_LOG:?}"
    exit "${STUB_HIDE_RC:-0}"   # a hide can fail; the caller must not assume it worked
fi
print -rn -- "${STUB_SNAPSHOT:-}"
STUB

# A fixed clock. Every timing assertion here is "N seconds before now", and a
# real clock ticking between seeding the state and reading it back is enough to
# make a boundary test flip. The stub and seed_state() below read the same
# STUB_NOW, so the seeded epochs and the script's idea of now cannot drift.
cat > "$ROOT/bin/date" <<'STUB'
#!/usr/bin/env zsh
[[ "${1:-}" == "+%s" && -n "${STUB_NOW:-}" ]] && { print -r -- "$STUB_NOW"; exit 0 }
exec /bin/date "$@"
STUB

# Stands in for `ioreg -c IOHIDSystem`, whose HIDIdleTime is in NANOseconds.
# Default is a long idle; STUB_HID_IDLE_NS sets it, STUB_IOREG_RC=1 makes the
# reading unavailable (which must count as busy, not as idle).
cat > "$ROOT/bin/ioreg" <<'STUB'
#!/usr/bin/env zsh
(( ${STUB_IOREG_RC:-0} != 0 )) && exit "${STUB_IOREG_RC}"
print -r -- '    | | |   "HIDIdleTime" = '"${STUB_HID_IDLE_NS:-3600000000000}"
STUB

# Stands in for `pmset -g assertions`. With STUB_AUDIO_IN=1 the coreaudiod
# assertion lists audio-in on its Resources line - a live microphone.
#
# Transcribed from real `pmset -g assertions` output on macOS 15 (2026-07-28),
# and the detail lines are the point. `Resources:` does NOT follow its owning
# assertion directly: `Created for PID:` sits between them, and a parser that
# forgets who it is reading as soon as it sees an unrecognised line will miss
# the microphone entirely. An earlier version of this stub omitted that line
# and let a broken mic gate pass 60 assertions. Do not "tidy" it away.
cat > "$ROOT/bin/pmset" <<'STUB'
#!/usr/bin/env zsh
print -r -- '   pid 350(powerd): [0x0007ab13] 00:29:17 PreventUserIdleSystemSleep named: "Powerd"'
print -r -- '   pid 418(runningboardd): [0x0007ba43] 00:00:00 PreventUserIdleSystemSleep named: "anon"'
print -r -- '\tCreated for PID: 94069. '
print -r -- '   pid 419(coreaudiod): [0x0007b540] 00:21:23 PreventUserIdleSystemSleep named: "com.apple.audio.BuiltInSpeakerDevice.context"'
print -r -- '\tCreated for PID: 2458. '
print -r -- '\tResources: BuiltInSpeakerDevice '
if [[ -n "${STUB_AUDIO_IN:-}" ]]; then
    print -r -- '   pid 419(coreaudiod): [0x0007ab15] 01:04:45 PreventUserIdleSystemSleep named: "com.apple.audio.DD40597F.context"'
    print -r -- '\tCreated for PID: 93627. '
    print -r -- '\tResources: audio-in audio-out BuiltInSpeakerDevice '
fi
print -r -- '   pid 6556(Claude): [0x00062797] 64:39:35 NoIdleSleepAssertion named: "Electron"'
STUB

# Stands in for the manual trigger the escalation rungs call. Records the whole
# argument list, so a test can tell a close (--max-action close) from a quit.
cat > "$ROOT/custom_bins/clear-mac-apps" <<'STUB'
#!/usr/bin/env zsh
print -r -- "$*" >> "${STUB_ESCALATE_LOG:?}"
exit "${STUB_ESCALATE_RC:-0}"
STUB

# Stands in for the exposure helper: records its flags, then emits canned output
# or an exit code the caller picks.
cat > "$ROOT/tools/window-exposure/window-exposure" <<'STUB'
#!/usr/bin/env zsh
print -r -- "$*" >> "${STUB_HELPER_ARGS_LOG:?}"
(( ${STUB_HELPER_RC:-0} != 0 )) && exit "${STUB_HELPER_RC}"
print -rn -- "${STUB_HELPER_OUT:-}"
STUB

print -r -- "// stub" > "$ROOT/tools/window-exposure/main.swift"
chmod +x "$ROOT/bin/osascript" "$ROOT/bin/date" "$ROOT/bin/ioreg" "$ROOT/bin/pmset" \
         "$ROOT/custom_bins/clear-mac-apps" "$ROOT/tools/window-exposure/window-exposure"
touch "$ROOT/tools/window-exposure/window-exposure"  # must out-date main.swift

if [[ "$ROOT/custom_bins/hide-idle-apps" -ef "$REPO/custom_bins/hide-idle-apps" ]]; then
    print -r -- "  ok   script under test is the real file (same inode)"; (( PASS++ ))
else
    print -r -- "  FAIL script under test is a copy, not the real file"; (( FAIL++ ))
fi

# --- canned inputs ---------------------------------------------------------
# 101 Safari frontmost; 102 Telegram 35% visible (under the 40% threshold, so
# covered); 103 Cursor 0% and already hidden; 104 Bear 41% (over, so exposed);
# 105 Slack owns no window in the list at all (another Space) -> unknown;
# 106 Ghostty is fully covered and would otherwise qualify, but is excluded.
#
# 107 and 108 exist for the ladder. Their shapes are what the two rungs actually
# look like on a real desktop: a HIDDEN app is visible=false AND owns no onscreen
# window (hidden windows leave the list), while a CLOSED app is visible=true -
# System Events calls an app with nothing to show visible - and likewise owns no
# window. That difference is exactly why un-hiding resets only the hidden rung.
#
# 109 Obsidian is `manual: skip` in the shipped config: hideable like anything
# else, but the ceiling stops it there. It has no row in the helper output, so
# it reads unknown and is left alone except where a test says otherwise.
export STUB_SNAPSHOT="FRONT:101
RUN:101	true	Safari
RUN:102	true	Telegram
RUN:103	false	Cursor
RUN:104	true	Bear
RUN:105	true	Slack
RUN:106	true	Ghostty
RUN:107	false	Notion
RUN:108	true	Spotify
RUN:109	true	Obsidian
"
export STUB_HELPER_OUT=$'101\t1\t1.000\n102\t0\t0.352\n103\t0\t0.000\n104\t1\t0.407\n106\t0\t0.000\n'
export STUB_HELPER_ARGS_LOG="$WORK/helper-args.log"
export STUB_HIDE_LOG="$WORK/hide-attempts.log"
export STUB_ESCALATE_LOG="$WORK/escalations.log"

# The escalation consent token. Every scenario below that expects a close or a
# quit needs it present, so it is part of the baseline fixture rather than
# per-test setup. Note it is NOT under .cache: the scenarios rm -rf that
# directory to reset state, which is exactly why the real token does not live
# there either. Scenario 24 deletes this one deliberately, then restores it.
ESCALATION_TOKEN="$FAKEHOME/.local/state/hide-idle-apps/escalation-enabled"
mkdir -p "${ESCALATION_TOKEN:h}"
print -r -- "test fixture" > "$ESCALATION_TOKEN"

NOW=$(date +%s)
export STUB_NOW="$NOW"

run() {  # run <helper_rc> [args...]; sets OUT / ERR / RC / ARGS / ESC
    : > "$STUB_HELPER_ARGS_LOG"   # every log is per-run, so no run can inherit
    : > "$STUB_HIDE_LOG"          # what an earlier one recorded
    : > "$STUB_ESCALATE_LOG"
    STUB_HELPER_RC="$1"; shift
    export STUB_HELPER_RC
    OUT=$(HOME="$FAKEHOME" PATH="$ROOT/bin:$PATH" \
          "$ROOT/custom_bins/hide-idle-apps" "$@" 2>"$WORK/err")
    RC=$?
    # cat, not $(<file): zsh evaluates the read-file form even under `zsh -n`,
    # where these variables are unset, so a syntax check would print errors.
    ERR=$(cat "$WORK/err" 2>/dev/null)
    ARGS=$(cat "$STUB_HELPER_ARGS_LOG" 2>/dev/null)
    ESC=$(cat "$STUB_ESCALATE_LOG" 2>/dev/null)
    STATE=$(cat "$FAKEHOME/.cache/hide-idle-apps/state" 2>/dev/null)
}

# seed_state <seconds since last poll> [pid=phase=clock_age_seconds ...]
# Every app has been covered an hour and sits on the `visible` rung unless an
# override says otherwise. clock_age is how long ago that rung's clock started,
# which is what the close and quit thresholds are measured against.
seed_state() {
    local gap="$1"; shift
    local now="$STUB_NOW" p spec
    typeset -A ph age
    for spec in "$@"; do
        ph[${spec%%=*}]="${${spec#*=}%%=*}"
        age[${spec%%=*}]="${spec##*=}"
    done
    mkdir -p "$FAKEHOME/.cache/hide-idle-apps"
    # Tabs via $'\t': print -r does NOT expand escapes, and a literal backslash-t
    # would silently make every app look freshly seen instead of long idle.
    {
        print -r -- "#v3"
        print -r -- "#last_poll"$'\t'"$(( now - gap ))"
        for p in 101 102 103 104 105 106 107 108 109; do
            print -r -- "$p"$'\t'"$(( now - 3600 ))"$'\t'"1"$'\t'"${ph[$p]:-visible}"$'\t'"$(( now - ${age[$p]:-0} ))"
        done
    } > "$FAKEHOME/.cache/hide-idle-apps/state"
}

# --- 1. dry run reports measured visibility --------------------------------
print -r -- "1. dry run reports measured visibility"
rm -rf "$FAKEHOME/.cache"
run 0 --dry-run
check     "runs clean"                     "$RC"  "0"
check     "passes --min-visible through"   "$ARGS" "--min-visible 40"
check     "asks for --verbose"             "$ARGS" "--verbose"
check     "frontmost labelled"             "$OUT" "frontmost  Safari"
check     "35% for Telegram"               "$OUT" "35%  Telegram"
check     "41% for Bear"                   "$OUT" "41%  Bear"
check     "0% for Cursor"                  "$OUT" "0%  Cursor"
check     "no window here reads unknown"   "$OUT" "unknown  Slack (no window on this Space)"
check_not "excluded app not reported"      "$OUT" "Ghostty"
check     "first sight hides nothing"      "$OUT" "Nothing to hide."
# Spec: the dry run prints the RESOLVED DECISION per app, not just how much of
# it is showing - phase, both configured values, the rung it is heading for, and
# what is holding it there. Checked as one span so a column silently dropping out
# cannot pass.
check     "the resolved decision, in full"  "$OUT" "visible close/quit  -> hide  visible enough"
check     "a gate that is the streak"       "$OUT" "-> hide  streak 1/2"
check     "a gate that is the frontmost"    "$OUT" "-> hide  frontmost"
check     "manual: skip shows as itself"    "$OUT" "skip/quit"
# zsh leaves TYPESET_SILENT unset, so a bare `local x` for an x that already has
# a value prints it. Three such lines used to head every dry-run report.
check_not "no declarations leak into it"    "$OUT" "akey="

# --- 2. a bad tunable is not a transient failure ---------------------------
print -r -- "2. exit 64 reads as a bad tunable, not a transient failure"
rm -rf "$FAKEHOME/.cache"
run 64 --dry-run
check     "names the tunable on stderr"    "$ERR" "bad HIDE_IDLE_MIN_VISIBLE_PERCENT="
check_not "not misfiled as transient"      "$ERR" "no usable window list"
check     "hides nothing"                  "$OUT" "Nothing would be hidden"

# --- 3. a transient helper failure stays quiet -----------------------------
print -r -- "3. exit 1 stays a silent transient failure"
rm -rf "$FAKEHOME/.cache"
run 1 --dry-run
check     "reported as transient"          "$OUT" "no usable window list"
check_not "stderr stays quiet"             "$ERR" "hide-idle-apps:"

# --- 4. only the covered, still-visible app is hidden ----------------------
print -r -- "4. real run hides only the covered, still-visible app"
rm -rf "$FAKEHOME/.cache"; seed_state 60
run 0
HIDES=$(cat "$STUB_HIDE_LOG")
check     "covered app is hidden"          "$OUT"   "Hid: Telegram"
check     "hidden by pid, not name"        "$HIDES" "unix id is 102"
check_not "frontmost never hidden"         "$HIDES" "unix id is 101"
check_not "already-hidden not re-hidden"   "$HIDES" "unix id is 103"
check_not "exposed app never hidden"       "$HIDES" "unix id is 104"
check_not "unknown app never hidden"       "$HIDES" "unix id is 105"
check_not "excluded app never hidden"      "$HIDES" "unix id is 106"
check_not "scheduled run skips --verbose"  "$ARGS" "--verbose"

# --- 5. skipped polls (sleep) hide nothing ---------------------------------
print -r -- "5. a gap over 3x the poll interval hides nothing"
rm -rf "$FAKEHOME/.cache"; seed_state 1000
run 0
check_not "no hide attempted after a gap"  "$(cat "$STUB_HIDE_LOG")" "unix id"
check_not "nothing reported hidden"        "$OUT" "Hid:"
rm -rf "$FAKEHOME/.cache"; seed_state 1000
run 0 --dry-run
check     "gap named as the reason"        "$OUT" "polls were skipped"

# --- 6. a config we cannot read acts on nothing ----------------------------
# Not an exit: a scheduled job that dies leaves no trace anyone reads. It has to
# behave like any other invalid poll - hide nothing, restart every timer - and
# say why on stderr, where launchd captures it.
print -r -- "6. an unreadable config hides nothing and says why"
cp "$ROOT/config/app-lifecycle.yaml" "$WORK/app-lifecycle.yaml.bak"
{ print -r -- "defaults:"; print -r -- "  manual: banana" } > "$ROOT/config/app-lifecycle.yaml"
rm -rf "$FAKEHOME/.cache"; seed_state 60
run 0
check     "names the bad value on stderr"  "$ERR"  "banana"
check_not "no hide attempted"              "$(cat "$STUB_HIDE_LOG")" "unix id"
rm -rf "$FAKEHOME/.cache"; seed_state 60
run 0 --dry-run
check     "dry run blames the config"      "$OUT"  "config"
cp "$WORK/app-lifecycle.yaml.bak" "$ROOT/config/app-lifecycle.yaml"

# --- 7. a state file from an older version is rebuilt, not read ------------
print -r -- "7. an older state file is discarded and rebuilt, acting on nothing"
rm -rf "$FAKEHOME/.cache"; mkdir -p "$FAKEHOME/.cache/hide-idle-apps"
{
    print -r -- "#v2"
    print -r -- "#last_poll"$'\t'"$(( NOW - 60 ))"
    print -r -- "102"$'\t'"$(( NOW - 3600 ))"$'\t'"1"
} > "$FAKEHOME/.cache/hide-idle-apps/state"
run 0
check_not "no hide from a v2 timer"        "$(cat "$STUB_HIDE_LOG")" "unix id"
check     "rebuilt at the new version"     "${STATE%%$'\n'*}" "#v3"
rm -rf "$FAKEHOME/.cache"; mkdir -p "$FAKEHOME/.cache/hide-idle-apps"
print -r -- "#v2" > "$FAKEHOME/.cache/hide-idle-apps/state"
run 0 --dry-run
check     "dry run names the version"      "$OUT" "older version"

# A line of state by pid, so a phase assertion names one app rather than hoping
# no other app happens to carry the string.
state_line() {
    local l
    for l in "${(f)STATE}"; do
        [[ "$l" == "$1"$'\t'* ]] && { print -r -- "$l"; return }
    done
}

# --- 8. an idle machine walks a hidden app to the close rung ---------------
print -r -- "8. hidden past close_after, machine idle -> close, capped at close"
rm -rf "$FAKEHOME/.cache"; seed_state 60 "107=hidden=1000"
run 0
check     "closes the hidden app"          "$ESC" "--only Notion"
check     "capped so it cannot quit"       "$ESC" "--max-action close"
check     "phase advances to closed"       "$(state_line 107)" "closed"
check     "says what it did"               "$OUT" "Escalated close: Notion"

# --- 9. busy pauses the destructive clocks, and does not reset them ---------
# The distinction is the whole point: a reset would hand an app a fresh 15
# minutes every time the trackpad is touched, so it would never reach a rung.
print -r -- "9. busy pauses the close clock by exactly the elapsed interval"
export STUB_HID_IDLE_NS=1000000000   # 1s since input: the machine is in use
rm -rf "$FAKEHOME/.cache"; seed_state 60 "107=hidden=1000"
run 0
check_not "nothing escalated while busy"   "$ESC" "Notion"
check     "clock pushed forward 60s"       "$(state_line 107)" "$(( NOW - 940 ))"
check     "still on the hidden rung"       "$(state_line 107)" "hidden"
run 0 --dry-run
check     "dry run says why"               "$OUT" "Machine BUSY"
unset STUB_HID_IDLE_NS

# --- 10. a live microphone is busy even when the keyboard is not -----------
print -r -- "10. a live mic counts as busy on its own"
export STUB_AUDIO_IN=1
rm -rf "$FAKEHOME/.cache"; seed_state 60 "107=hidden=1000"
run 0
check_not "mic in use blocks the close"    "$ESC" "Notion"
unset STUB_AUDIO_IN

# --- 11. an unreadable idle time is busy, not idle --------------------------
# Fail-safe, not fail-open: "cannot tell whether anyone is here" must never be
# the reason a window closes.
print -r -- "11. an unreadable idle reading counts as busy"
export STUB_IOREG_RC=1
rm -rf "$FAKEHOME/.cache"; seed_state 60 "107=hidden=1000"
run 0
check_not "no close without a reading"     "$ESC" "Notion"
unset STUB_IOREG_RC

# --- 12. manual: is the ceiling on the destructive rungs -------------------
print -r -- "12. the ladder stops where manual: says, even long past due"
rm -rf "$FAKEHOME/.cache"; seed_state 60 "108=closed=5000" "105=closed=5000"
run 0
check_not "manual: close is never quit"    "$ESC" "Spotify"
check     "an unlisted app does quit"      "$ESC" "--only Slack"
check_not "quit is not capped to close"    "$ESC" "--max-action"
# System Events calls a windowless app visible, so a plain visibility test would
# drop every closed app back to the bottom rung and it would never be quit.
check     "closed does not read as un-hidden" "$(state_line 108)" "closed"

# --- 13. one destructive action per poll -----------------------------------
# clear-mac-apps can spend 30s on one app; several in a 60s poll would overrun
# the interval and trip our own gap check next time round.
print -r -- "13. at most one destructive action per poll, most overdue first"
rm -rf "$FAKEHOME/.cache"; seed_state 60 "107=hidden=5000" "105=closed=5000"
run 0
check     "exactly one escalation ran"     "$(print -r -- "${(f)ESC}" | grep -c only)" "1"
check     "the more overdue app went"      "$ESC" "Notion"

# --- 14. a hide that failed does not start the close clock -----------------
print -r -- "14. a failed hide leaves the app on the visible rung"
export STUB_HIDE_RC=1
rm -rf "$FAKEHOME/.cache"; seed_state 60
run 0
check     "the hide was attempted"         "$(cat "$STUB_HIDE_LOG")" "unix id is 102"
check     "phase stays visible"            "$(state_line 102)" "visible"
check_not "nothing reported as hidden"     "$OUT" "Hid:"
unset STUB_HIDE_RC

# --- 15. an app whose windows are back drops to the visible rung -----------
# This is also what heals a rung that silently failed: the windows never left
# the onscreen list, so the app cannot keep climbing on the strength of one.
print -r -- "15. a window back in the onscreen list resets the rung"
rm -rf "$FAKEHOME/.cache"; seed_state 60 "103=hidden=5000"
run 0
check     "back to visible"                "$(state_line 103)" "visible"
check_not "and not escalated"              "$ESC" "Cursor"

# --- 16. manual: skip is hidden like anything else, and stops there ---------
# The half of the ceiling that is easy to get wrong: `manual: skip` names what
# the Shortcut does, and must not be read as "leave this app alone".
print -r -- "16. manual: skip is hidden on the normal schedule, then goes no further"
SNAP_HELPER_OUT="$STUB_HELPER_OUT"
export STUB_HELPER_OUT="${SNAP_HELPER_OUT}"$'109\t0\t0.000\n'
rm -rf "$FAKEHOME/.cache"; seed_state 60
run 0
check     "a manual: skip app is hidden"   "$OUT" "Obsidian"
export STUB_HELPER_OUT="$SNAP_HELPER_OUT"
# Now wearing the shape a hidden app really has: System Events reports it not
# visible, and its windows have left the onscreen list. Seeded true, it would be
# un-hidden by the reset rule on sight - correctly, since that is what a user
# bringing it back looks like.
SNAP_SNAPSHOT="$STUB_SNAPSHOT"
TAB=$'\t'   # via a variable: $'\t' is not expanded inside a ${x/pat/repl} pattern
export STUB_SNAPSHOT="${SNAP_SNAPSHOT/RUN:109${TAB}true/RUN:109${TAB}false}"
rm -rf "$FAKEHOME/.cache"; seed_state 60 "109=hidden=99999"
run 0
check_not "but never has windows closed"   "$ESC" "Obsidian"
check     "and stays hidden indefinitely"  "$(state_line 109)" "hidden"
export STUB_SNAPSHOT="$SNAP_SNAPSHOT"

# --- 17. auto: skip is out of the idle job's reach entirely -----------------
print -r -- "17. auto: skip is never escalated, however long it sits"
rm -rf "$FAKEHOME/.cache"; seed_state 60 "106=closed=99999"
run 0
check_not "an auto: skip app is not quit"  "$ESC" "Ghostty"

# --- 18. an app's own quit_after beats the default -------------------------
print -r -- "18. a per-app quit_after replaces the default rather than adding to it"
cp "$ROOT/config/app-lifecycle.yaml" "$WORK/alc.bak"
{
    print -r -- "defaults:"
    print -r -- "  manual: quit"
    print -r -- "  auto: quit"
    print -r -- "  hide_after: 15"
    print -r -- "  close_after: 15"
    print -r -- "  quit_after: 30"
    print -r -- "  user_idle: 5"
    print -r -- "  min_visible_percent: 40"
    print -r -- "apps:"
    print -r -- "  Notion: {quit_after: 120}"
} > "$ROOT/config/app-lifecycle.yaml"
rm -rf "$FAKEHOME/.cache"; seed_state 60 "107=closed=5000"   # 83m: past 30, short of 120
run 0
check_not "not quit on the default clock"  "$ESC" "Notion"
rm -rf "$FAKEHOME/.cache"; seed_state 60 "107=closed=7300"   # 121m: past its own
run 0
check     "quit once its own clock is up"  "$ESC" "--only Notion"
cp "$WORK/alc.bak" "$ROOT/config/app-lifecycle.yaml"

# --- 19. un-hiding hands back a fresh exposure timer, not just a fresh rung --
# Codex P2. Test 15 covers the neighbouring case - windows back in the onscreen
# list while System Events still calls the app not visible - and that one is
# saved by the hide guard, which needs `visible: true`. This is the case where
# the user really did un-hide it: visible becomes true while the window is still
# covered. Dropping to `visible` resets the phase clock, but the exposure timer
# lives in last_active/streak, and the poll that performs the transition runs the
# `visible` branch, so the refresh on the `hidden` rung never fires for it. Left
# stale, the app arrives already past hide_after and is hidden again in the same
# second the user brought it back - the one failure a person would actually feel.
print -r -- "19. an app the user un-hid is not hidden again on the spot"
SNAP_SNAPSHOT="$STUB_SNAPSHOT"
TAB=$'\t'
export STUB_SNAPSHOT="${SNAP_SNAPSHOT/RUN:103${TAB}false/RUN:103${TAB}true}"
rm -rf "$FAKEHOME/.cache"; seed_state 60 "103=hidden=5000"
run 0
check     "it lands back on the visible rung" "$(state_line 103)" "visible"
check_not "and is not re-hidden this poll"    "$(cat "$STUB_HIDE_LOG")" "unix id is 103"
check_not "nor reported as hidden"            "$OUT" "Cursor"
export STUB_SNAPSHOT="$SNAP_SNAPSHOT"

# --- 20. a close that failed does not become a licence to quit --------------
# Codex P2, and the mirror of test 14 one rung up. The phase is advanced before
# the call on purpose, so a job KILLED mid-close cannot re-fire every poll for
# ever - but a call that returns nonzero has to be taken back, because a hidden
# app owns no onscreen window and so never meets the reset rule that is supposed
# to heal a failed rung. Left at `closed`, its quit clock starts running on a
# close that never happened.
print -r -- "20. a failed close does not advance the app to the quit rung"
export STUB_ESCALATE_RC=1
rm -rf "$FAKEHOME/.cache"; seed_state 60 "107=hidden=5000"
run 0
check     "the close was attempted"        "$ESC" "--only Notion"
check     "but the rung is given back"     "$(state_line 107)" "hidden"
check_not "so it is not on the quit rung"  "$(state_line 107)" "closed"
unset STUB_ESCALATE_RC

# --- 21. the dry run explains the destructive rungs too ---------------------
# Codex P2. Visibility alone says nothing about an app already off the visible
# rung: what a calibration run needs from those is which rung they sit on, what
# their ceiling permits, and what is holding them - a paused clock reads exactly
# like a stuck one otherwise.
print -r -- "21. an app off the visible rung reports its rung, ceiling and gate"
rm -rf "$FAKEHOME/.cache"; seed_state 60 "107=hidden=300" "108=closed=99999"
run 0 --dry-run
check "a hidden app is heading for close"  "$OUT" "hidden   quit/quit  -> close"
check "and says how long it has to wait"   "$OUT" "-> close in 10m"
check "manual: close names its ceiling"    "$OUT" "closed  close/quit  -> quit  ceiling"

print -r -- "22. a paused clock is reported as paused, not as a long wait"
export STUB_HID_IDLE_NS=1000000000     # 1s: someone is at the keyboard
rm -rf "$FAKEHOME/.cache"; seed_state 60 "107=hidden=99999"
run 0 --dry-run
check "the gate is named as busy"          "$OUT" "-> close busy"
unset STUB_HID_IDLE_NS

# --- 23. defaults.auto reaches apps the config never names -----------------
# Codex P2. Test 17 covers `auto: skip` on a LISTED app, which is caught by
# exclude_set - and exclude_set is built from ALC_APP_KEYS, so it structurally
# cannot hold an unlisted one. Telegram is unlisted, and test 4 already proves
# this same seeding hides it - so under a skip default, hiding it is exactly the
# bug the exclude_set test can never see.
print -r -- "23. defaults.auto: skip protects an app the config never names"
cp "$ROOT/config/app-lifecycle.yaml" "$WORK/alc.bak"
{
    print -r -- "defaults:"
    print -r -- "  manual: quit"
    print -r -- "  auto: skip"
    print -r -- "  hide_after: 15"
    print -r -- "  close_after: 15"
    print -r -- "  quit_after: 30"
    print -r -- "  user_idle: 5"
    print -r -- "  min_visible_percent: 40"
    print -r -- "apps:"
    print -r -- "  Numbers: {manual: skip}"   # a listed app the stub never runs
} > "$ROOT/config/app-lifecycle.yaml"
rm -rf "$FAKEHOME/.cache"; seed_state 60
run 0
check_not "the unlisted app is not hidden"  "$(cat "$STUB_HIDE_LOG")" "unix id is 102"
# Bare "Hid:", not "Hid: Telegram" - hid_names is space-joined, so naming one app
# only matches when it happens to sort first. Under a skip default nothing at all
# should be hidden, which is both the stronger claim and the order-free one.
check_not "and nothing is reported hidden"  "$OUT" "Hid:"
cp "$WORK/alc.bak" "$ROOT/config/app-lifecycle.yaml"

# --- 24. without the consent token, the destructive rungs are refused -------
# Scenario 8 with one thing changed: the token is gone. That is the machine that
# inherited a loaded launchd job from the era when this component defaulted to on
# and only ever hid windows. It must keep hiding - that is what was consented to
# - and must not climb to close or quit, however long the app has sat idle.
print -r -- "24. no escalation token -> hides, but never closes or quits"
rm -f "$ESCALATION_TOKEN"
rm -rf "$FAKEHOME/.cache"; seed_state 60 "107=hidden=1000"
run 0
check_not "the close is refused"            "$ESC" "--only Notion"
# The phase check is the one that matters: escalate() returns nonzero, so the
# pre-advanced rung is given back. Left at `closed`, the quit clock would start
# running on a close that never happened - and a later quit needs no second
# escalation to be wrong, it just needs this state to lie.
check     "and the rung is given back"      "$(state_line 107)" "hidden"
check     "the refusal is explained once"   "$ERR" "close/quit not enabled"
# The quit rung, reached from `closed` rather than `hidden`. Without this a gate
# wired into only the close path would pass every check above while still letting
# an inherited job quit apps outright - the single worst outcome the token exists
# to prevent. Both rungs go through escalate(), so this pins that they stay there.
rm -rf "$FAKEHOME/.cache"; seed_state 60 "107=closed=1000"
run 0
check_not "the quit is refused too"         "$ESC" "--only Notion"
check     "and that rung is given back"     "$(state_line 107)" "closed"
# Hiding is implemented locally and never routes through escalate(), so it is
# unaffected. A gate that silently disabled the whole job would be a regression.
# This half does not exercise escalate() at all - every app starts at `visible`,
# so the only way it can fail is if the gate were implemented as an early exit in
# main() rather than at the two destructive rungs. That is precisely the wrong
# implementation worth pinning, so the pair of checks is deliberate: the run hid
# something, and reached the escalation path for nothing.
rm -rf "$FAKEHOME/.cache"; seed_state 60
run 0
check     "hiding still works ungated"      "$OUT" "Hid:"
check_not "and nothing was escalated"       "$ESC" "--only"
print -r -- "test fixture" > "$ESCALATION_TOKEN"

print -r -- ""
print -r -- "PASS=$PASS FAIL=$FAIL"
(( FAIL == 0 )) || exit 1
