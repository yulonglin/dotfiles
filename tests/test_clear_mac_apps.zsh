#!/usr/bin/env zsh
# Runs custom_bins/clear-mac-apps end to end with osascript stubbed, the way
# tests/test_hide_idle_apps.zsh does. Same reasoning: System Events needs a
# window server, which CI and sandboxes don't have.
#
# The scripts under test are HARDLINKED into the fake tree, never copied: they
# resolve config and helper paths from ${0:A:h}, and :A resolves symlinks back
# to the real repo. A hardlink is the same inode, so what runs here cannot
# drift from what ships.
set -uo pipefail

REPO="${0:A:h:h}"
# Under the repo's gitignored tmp/, not $TMPDIR: agent sandboxes commonly allow
# only one level below their temp root, and this tree is several deep.
mkdir -p "$REPO/tmp" || { print -ru2 -- "FATAL: cannot create $REPO/tmp"; exit 1 }
WORK="$(mktemp -d "$REPO/tmp/clear-mac-test.XXXXXX")" \
    || { print -ru2 -- "FATAL: mktemp -d under $REPO/tmp failed"; exit 1 }
# set -u does NOT catch a failed mktemp: WORK ends up set-but-EMPTY, and ROOT
# below is derived from it, so ROOT would become /root - the stub writes and
# the cleanup rm would land outside the repo entirely. Validate before
# deriving anything and before arming the trap: an `rm -rf` trap must never be
# installed on a variable we have not checked.
[[ -n "$WORK" && -d "$WORK" && "$WORK" == "$REPO/tmp/"* ]] \
    || { print -ru2 -- "FATAL: work dir not under $REPO/tmp: ${WORK:-<empty>}"; exit 1 }
ROOT="$WORK/root"
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
check_eq() {  # check_eq <label> <actual> <expected>
    if [[ "$2" == "$3" ]]; then
        print -r -- "  ok   $1"; (( PASS++ ))
    else
        print -r -- "  FAIL $1"; (( FAIL++ ))
        # Real files, not process substitution: /dev/fd is not readable under
        # the agent sandbox and diff would fail instead of showing the diff.
        print -r -- "$3" > "$WORK/expected"; print -r -- "$2" > "$WORK/actual"
        diff "$WORK/expected" "$WORK/actual" | sed 's/^/       /'
    fi
}

# --- fake tree -------------------------------------------------------------
mkdir -p "$ROOT/custom_bins" "$ROOT/config" "$ROOT/bin"
ln "$REPO/custom_bins/clear-mac-apps"       "$ROOT/custom_bins/clear-mac-apps"
ln "$REPO/custom_bins/app-lifecycle-config" "$ROOT/custom_bins/app-lifecycle-config"
CMA="$ROOT/custom_bins/clear-mac-apps"

# Stands in for osascript. The app list and Chrome's tabs both arrive here; the
# Chrome query comes in on stdin (heredoc), everything else as arguments.
cat > "$ROOT/bin/osascript" <<'STUB'
#!/usr/bin/env zsh
script="$*"
[[ -z "$script" ]] && script="$(cat)"
# The close paths come first: their scripts name the process too, so a Chrome
# close would otherwise be answered with Chrome's tab list.
case "$script" in
    *AXCloseButton*)
        [[ -n "${STUB_AX_LOG:-}" ]] && print -r -- "$script" >> "$STUB_AX_LOG"
        (( ${STUB_AX_RC:-0} != 0 )) && exit "${STUB_AX_RC}"
        print -r -- 0 ;;
    *keystroke*)
        [[ -n "${STUB_KEY_LOG:-}" ]] && print -r -- "$script" >> "$STUB_KEY_LOG" ;;
    *"display notification"*)
        [[ -n "${STUB_NOTIFY_LOG:-}" ]] && print -r -- "$script" >> "$STUB_NOTIFY_LOG"
        : ;;
    *"set visible"*)
        # hide_app. Settable, because the hide bucket runs its osascript in a
        # background job and `wait` with no arguments would discard exactly
        # this status - which is the thing the test using it is checking.
        (( ${STUB_HIDE_RC:-0} != 0 )) && exit "${STUB_HIDE_RC}"
        : ;;
    *"to count windows"*)         print -r -- "${STUB_WINDOW_COUNT:-2}" ;;
    *"background only is false"*) print -rn -- "${STUB_APP_LIST:-}" ;;
    *"Google Chrome"*)
        # Chrome's tabs are read twice in a real run: once to classify it, and
        # again inside close_app_selectively. STUB_CHROME_TABS_2 makes the
        # protected tab vanish between the two - the exact race that decides
        # whether a capped run can still reach a quit.
        if [[ -n "${STUB_CHROME_CALLS:-}" ]]; then
            print -rn -- x >> "$STUB_CHROME_CALLS"
            calls="$(cat "$STUB_CHROME_CALLS")"
            # Read 3 is pass 2's post-close verification. Reads 2 and 3 answering
            # alike would make a closed target indistinguishable from a stuck one,
            # so the verification could never be observed to pass.
            if [[ -n "${STUB_CHROME_TABS_3:-}" && ${#calls} -ge 3 ]]; then
                print -rn -- "$STUB_CHROME_TABS_3"
                exit 0
            fi
            if [[ -n "${STUB_CHROME_TABS_2:-}" && "$calls" != x ]]; then
                print -rn -- "$STUB_CHROME_TABS_2"
                exit 0
            fi
        fi
        print -rn -- "${STUB_CHROME_TABS:-}" ;;
    *)                            : ;;   # window titles: nothing to report
esac
STUB
chmod +x "$ROOT/bin/osascript"

if [[ "$CMA" -ef "$REPO/custom_bins/clear-mac-apps" ]]; then
    print -r -- "  ok   script under test is the real file (same inode)"; (( PASS++ ))
else
    print -r -- "  FAIL script under test is a copy, not the real file"; (( FAIL++ ))
fi

# --- canned inputs ---------------------------------------------------------
# One app per bucket the old config produced, plus one it never mentioned.
export STUB_APP_LIST="Ghostty|com.mitchellh.ghostty
Bear|net.shinyfrog.bear
Mouseless|com.sinusoid.mouseless
Spark Desktop|com.readdle.smartemail
Safari|com.apple.Safari
Google Chrome|com.google.Chrome
"
export STUB_CHROME_TABS="1|Inbox (3) - Gmail
2|Google Meet - standup
"

AXCAP="$ROOT/home/.cache/hide-idle-apps/ax-capability"

run() {  # run [args...]; sets OUT / ERR / RC
    [[ -n "${STUB_AX_LOG:-}" ]]     && : > "$STUB_AX_LOG"
    [[ -n "${STUB_KEY_LOG:-}" ]]    && : > "$STUB_KEY_LOG"
    [[ -n "${STUB_NOTIFY_LOG:-}" ]] && : > "$STUB_NOTIFY_LOG"
    [[ -n "${STUB_CHROME_CALLS:-}" ]] && : > "$STUB_CHROME_CALLS"
    # HOME is faked because the close path remembers which apps cannot be closed
    # by clicking, under ~/.cache - a real run must not write to the real one.
    OUT=$(PATH="$ROOT/bin:$PATH" HOME="$ROOT/home" "$CMA" "$@" 2>"$WORK/err")
    RC=$?
    # cat, not $(<file): zsh evaluates the read-file form even under `zsh -n`,
    # where these variables are unset, so a syntax check would print errors.
    ERR=$(cat "$WORK/err" 2>/dev/null)
    # Surface stderr from any run that failed. Without this a script that dies
    # early just produces empty output and every later check fails for reasons
    # the log never explains.
    (( RC == 0 )) || print -r -- "  note (rc=$RC): $ERR"
}

# --- 1. migration preserves behaviour exactly ------------------------------
# The golden file was captured from the LAST PRE-MIGRATION clear-mac-apps run
# against this same stubbed app list. Migrating the old config and running the
# new script must reproduce it byte for byte - that is the whole claim the
# migration makes, and the only way to be sure the config swap changed nothing.
print -r -- "1. migrating the old config changes no behaviour"
"$CMA" --migrate-config "$REPO/tests/fixtures/clear_mac_apps.conf" \
    > "$ROOT/config/app-lifecycle.yaml" 2>"$WORK/err"
# On RC, not on empty stderr: every string contains the empty string, so a
# `check ... ""` would pass no matter what happened.
check "migration succeeds" "$?" "0"
run --dry-run
check_eq "dry run is byte-identical to pre-migration" \
         "$OUT" "$(cat "$REPO/tests/fixtures/clear_mac_apps.dry-run.txt")"

# Criteria 3-6 hold against the migrated config, where Bear is still close and
# Ghostty still skip - so they test the flags, not the later hand edits.
# --- 3. --only narrows to one app ------------------------------------------
print -r -- "3. --only reports just that app"
run --only Bear --dry-run
check     "Bear still closes its windows"  "$OUT" "Would CLOSE WINDOWS (1):
  - Bear"
check_not "no other app is reported"       "$OUT" "- Safari"
check     "quit bucket is empty"           "$OUT" "Would QUIT (0):"

# --- 4. --only cannot override the config ----------------------------------
print -r -- "4. --only on a skipped app still skips it"
run --only Ghostty --dry-run
check     "Ghostty lands in no-touch"      "$OUT" "Would SKIP (no-touch):
  - Ghostty"
check     "nothing would be quit"          "$OUT" "Would QUIT (0):"
check     "nothing would be closed"        "$OUT" "Would CLOSE WINDOWS (0):"

# --- 5. a protected tab downgrades quit to selective-close -----------------
print -r -- "5. a Google Meet tab protects Chrome"
run --dry-run
check     "Chrome is selective-closed"     "$OUT" "Would SELECTIVE-CLOSE"
check     "and named"                      "$OUT" "- Google Chrome"
check_not "Chrome is never quit outright"  "$OUT" "Would QUIT (2):"

# --- 6. an app the config never mentions is quit ---------------------------
print -r -- "6. an unlisted app takes the quit default"
run --dry-run
check     "Safari is quit"                 "$OUT" "Would QUIT (1):
  - Safari"

# --- max-action caps the rung ----------------------------------------------
# Not in the spec's criteria, but load-bearing: the idle job reaches its close
# rung through this flag, and without the cap an app whose `manual:` is quit
# would be quit there, collapsing hide -> close -> quit into one step.
print -r -- "7. --max-action close downgrades quits, promotes nothing"
run --max-action close --dry-run
check     "nothing is quit"                "$OUT" "Would QUIT (0):"
check     "the quit app closes instead"    "$OUT" "- Safari"
check     "slow-quit is capped too"        "$OUT" "Would SLOW-QUIT (0):"
check     "skipped app stays skipped"      "$OUT" "Would SKIP (no-touch):
  - Ghostty"

# --- 2. the shipped config, after the deliberate moves ---------------------
print -r -- "2. the shipped config quits what was moved off close-windows"
cp "$REPO/config/app-lifecycle.yaml" "$ROOT/config/app-lifecycle.yaml"
export STUB_APP_LIST="Claude|com.anthropic.claudefordesktop
Granola|so.granola.app
Tailscale|io.tailscale.ipn.macsys
NordVPN|com.nordvpn.macos
Bear|net.shinyfrog.bear
Spotify|com.spotify.client
"
run --dry-run
check     "Claude is quit"                 "$OUT" "- Claude"
check     "Granola is quit"                "$OUT" "- Granola"
check     "five apps quit, none closed"    "$OUT" "Would QUIT (4):"
check     "Bear still only closes"         "$OUT" "Would CLOSE WINDOWS (2):"
check     "Spotify still only closes"      "$OUT" "- Spotify"

# --- the close path itself, not dry-run ------------------------------------
# Everything above stops at --dry-run, so none of it ever reaches the code that
# actually closes a window. These four run it for real against the stub. Bear is
# close-windows in the shipped config, so --only Bear reaches exactly that path
# and nothing else - no quits to wait on.
export STUB_AX_LOG="$WORK/ax.log" STUB_KEY_LOG="$WORK/key.log"

print -r -- "9. closing windows clicks the close button rather than typing"
export STUB_WINDOW_COUNT=2 STUB_AX_RC=0
run --only Bear
check    "Bear's windows are closed"        "$OUT" "Closing windows: Bear"
check    "by clicking the close button"     "$(cat "$STUB_AX_LOG" 2>/dev/null)" "AXCloseButton"
check_eq "no keystroke, so no focus stolen" "$(cat "$STUB_KEY_LOG" 2>/dev/null)" ""
check_eq "and nothing is remembered"        "$(cat "$AXCAP" 2>/dev/null)" ""

print -r -- "10. an app with no close button falls back to keystrokes"
export STUB_AX_RC=1
run --only Bear
check "the click is attempted first" "$(cat "$STUB_AX_LOG" 2>/dev/null)"  "AXCloseButton"
check "keystrokes take over"         "$(cat "$STUB_KEY_LOG" 2>/dev/null)" "keystroke"
check "and the app is remembered"    "$(cat "$AXCAP" 2>/dev/null)"        "Bear"

print -r -- "11. a remembered app is never probed again"
run --only Bear
check_eq "no second probe"        "$(cat "$STUB_AX_LOG" 2>/dev/null)" ""
check    "straight to keystrokes" "$(cat "$STUB_KEY_LOG" 2>/dev/null)" "keystroke"
check_eq "recorded exactly once"  "$(grep -c $'^Bear\t' "$AXCAP")" "1"

# The record is only consulted when there IS one, so without expiry nothing would
# ever revisit it: an app that gained a close button in an update would be typed
# at for the rest of the machine's life. A stale record must therefore re-probe.
print -r -- "11b. a record older than the TTL is probed again, and refreshed"
STALE_STAMP=$(( $(date +%s) - 40 * 86400 ))
print -r -- "Bear"$'\t'"$STALE_STAMP" > "$AXCAP"
run --only Bear
check    "the click is attempted again" "$(cat "$STUB_AX_LOG" 2>/dev/null)" "AXCloseButton"
check_eq "still exactly one record"     "$(grep -c $'^Bear\t' "$AXCAP")"   "1"
check_not "and the stale stamp is gone" "$(cat "$AXCAP")"                  "$STALE_STAMP"

# The format gained a timestamp column, so every record written before this
# change has none. Trusting those forever would exempt precisely the apps that
# have been branded longest - the ones most likely to have been updated since.
print -r -- "11c. a record with no timestamp is treated as expired"
print -r -- "Bear" > "$AXCAP"
run --only Bear
check "the legacy record does not suppress the probe" "$(cat "$STUB_AX_LOG" 2>/dev/null)" "AXCloseButton"
check "and it is rewritten with a stamp"              "$(cat "$AXCAP")"                    "Bear	"

# Criterion 20: a probe that fails for want of a window says nothing about
# whether the app supports clicking, so a windowless app must not be probed at
# all - and above all must not be branded keystroke-only on that evidence.
print -r -- "12. an app with no windows is left alone, and teaches us nothing"
export STUB_WINDOW_COUNT=0
run --only Spotify
check_eq  "no probe"                 "$(cat "$STUB_AX_LOG" 2>/dev/null)"  ""
check_eq  "no keystroke"             "$(cat "$STUB_KEY_LOG" 2>/dev/null)" ""
check_not "not recorded"             "$(cat "$AXCAP" 2>/dev/null)"        "Spotify"

# --- every value on the scale gets dispatched ------------------------------
# Nothing above exercises `manual: hide` on a running app, and no app pairs
# `close` with `slow`, so neither would be noticed going wrong there. Both did
# go wrong. With a bucket per value missing, `hide` fell through to the `quit`
# default. `slow` - which only says how a quit is AWAITED - was checked as
# though it were a bucket of its own, and outranked `close`. Either way the
# config asked for a gentler action and got the harshest one. The shipped
# config's Focusmate and Obsidian entries ride on the `hide` bucket, so test 13
# is what stands between them and being quit outright.
print -r -- "13. a hide-only app is hidden, not quit"
print -r -- 'defaults:
  manual: quit
  auto: quit
apps:
  Bear:          {manual: hide}
  Spark Desktop: {manual: close, slow: true}' > "$ROOT/config/app-lifecycle.yaml"
export STUB_APP_LIST="Bear|net.shinyfrog.bear
Spark Desktop|com.readdle.smartemail
Safari|com.apple.Safari
"
run --dry-run
check     "Bear is hidden"                 "$OUT" "Would HIDE (1):
  - Bear"
check_not "and never quit"                 "$OUT" "- Bear
  - Safari"
check     "the default app still quits"    "$OUT" "Would QUIT (1):
  - Safari"

print -r -- "14. slow modifies a quit, it does not create one"
check     "the close app still closes"     "$OUT" "Would CLOSE WINDOWS (1):
  - Spark Desktop"
check     "and is not slow-quit"           "$OUT" "Would SLOW-QUIT (0):"

# Codex P2: the cap was applied when the buckets were built, so an app already
# sorted into selective-close carried no memory of it. If the protected tab is
# gone by the time close_app_selectively re-checks, that function's "nothing
# worth keeping -> quit the app" branch fired and the idle job's CLOSE rung
# performed a quit.
print -r -- "15. --max-action close survives a protected tab vanishing mid-run"
cp "$REPO/config/app-lifecycle.yaml" "$ROOT/config/app-lifecycle.yaml"
export STUB_APP_LIST="Google Chrome|com.google.Chrome
"
export STUB_CHROME_CALLS="$WORK/chrome.calls"
export STUB_CHROME_TABS_2="1|Inbox (3) - Gmail
"
run --only "Google Chrome" --max-action close
check     "the quit is refused"            "$OUT" "capped at close"
check_not "and Chrome is not quit"         "$OUT" "Quitting Google Chrome"
unset STUB_CHROME_TABS_2 STUB_CHROME_CALLS

# The exit status is a contract with hide-idle-apps' escalate(), which gives an
# app its rung back on nonzero. main() used to end with `(( ${#slow_quit_set} >
# 0 )) && echo ...`, so the status reported whether the CONFIG listed a `slow:
# true` app - nothing to do with the run. That made the give-back a coin flip
# decided by one YAML line: with Spark Desktop present it was always 0 (a failed
# close still advanced to the quit rung), and without it always 1 (no app ever
# reached quit). test_hide_idle_apps.zsh's test 20 pins the give-back against a
# stub with a settable code, so only a check here can catch the real thing.
print -r -- "16. the exit status reports the run, not the config's shape"
export STUB_APP_LIST="Bear|net.shinyfrog.bear
"
# Earlier tests leave these set - window count at 0 (an app with no windows is
# closed by doing nothing, which would make the failure case below vacuous) and
# the AX return code at 1 (which would make the success cases fail). State that
# leaks between tests is exactly how a check stops testing what it claims to.
export STUB_WINDOW_COUNT=2 STUB_AX_RC=0
: > "$AXCAP"   # forget which apps were probed, so the AX path runs again
CONFIG_NO_SLOW="defaults:
  manual: quit
  auto: quit
apps:
  Bear: {manual: close}"
CONFIG_WITH_SLOW="$CONFIG_NO_SLOW
  Spark Desktop: {slow: true}"

print -r -- "$CONFIG_NO_SLOW" > "$ROOT/config/app-lifecycle.yaml"
run --only Bear
check "a clean close exits 0 with no slow app in the config" "$(( RC == 0 ))" "1"

print -r -- "$CONFIG_WITH_SLOW" > "$ROOT/config/app-lifecycle.yaml"
run --only Bear
check "and still exits 0 once a slow app is listed"          "$(( RC == 0 ))" "1"

# AX click fails, so it falls back to keystrokes; the stub answers those with
# nothing, which is not evidence the windows went away. Exported, because the
# stub reads it from the environment two processes down.
export STUB_AX_RC=1
run --only Bear
check "a close that left windows behind exits non-zero"      "$(( RC != 0 ))" "1"
check "and says which app"                                   "$OUT" "Bear still has windows"

print -r -- "$CONFIG_NO_SLOW" > "$ROOT/config/app-lifecycle.yaml"
run --only Bear
check "failure is reported without a slow app too"           "$(( RC != 0 ))" "1"
unset STUB_AX_RC

# The hide bucket is the one path that runs its action in a background job and
# then has to report it. `wait` with no arguments returns the status of the
# *shell's* last job bookkeeping, not the jobs', so a failed hide used to be
# indistinguishable from a clean run. Nothing else in this suite executes that
# loop - every other non-dry test lands in close or selective-close - so
# without this the PID collection and `local pid=""` are unexecuted code.
print -r -- "17. a failed hide is reported, not swallowed by bare `wait`"
export STUB_APP_LIST="Bear|net.shinyfrog.bear
"
print -r -- "defaults:
  manual: quit
  auto: quit
apps:
  Bear: {manual: hide}" > "$ROOT/config/app-lifecycle.yaml"

export STUB_HIDE_RC=0
run --only Bear
check     "the hide bucket is the one that ran"  "$OUT" "Hiding 1 apps in parallel"
check     "a hide that worked exits 0"           "$(( RC == 0 ))" "1"

export STUB_HIDE_RC=1
run --only Bear
check     "a hide that failed exits non-zero"    "$(( RC != 0 ))" "1"
unset STUB_HIDE_RC

# Codex, this round: with the run capped at close and the protected tab gone by
# the rescan, close_app_selectively called quit_app_capped, which refuses the
# quit and returns 0 - having closed nothing. escalate() reads 0 as "the close
# rung completed", keeps the `closed` phase it wrote before the call, and
# quit_after later quits an app whose windows are still open. A hidden app owns
# no onscreen window, so nothing ever drops it back a rung to self-heal.
#
# Test 15 asserted only that Chrome was not quit, which the false success also
# satisfies. The rung now does its actual job - close the windows - and reports
# whether that worked.
print -r -- "18. a capped selective-close closes, rather than reporting a refusal as success"
cp "$REPO/config/app-lifecycle.yaml" "$ROOT/config/app-lifecycle.yaml"
export STUB_APP_LIST="Google Chrome|com.google.Chrome
"
export STUB_CHROME_CALLS="$WORK/chrome.calls"
export STUB_CHROME_TABS_2="1|Inbox (3) - Gmail
"
export STUB_WINDOW_COUNT=2 STUB_AX_RC=0
: > "$AXCAP"

run --only "Google Chrome" --max-action close
check     "it closes instead of refusing"        "$OUT" "closing its windows instead"
check_not "and still never quits"                "$OUT" "Quitting Google Chrome"
check     "a close that worked exits 0"          "$(( RC == 0 ))" "1"

# Same path, but the close genuinely fails: AX click errors, the keystroke
# fallback tells us nothing, so the windows are still there.
export STUB_AX_RC=1
run --only "Google Chrome" --max-action close
check     "a close that failed exits non-zero"   "$(( RC != 0 ))" "1"
unset STUB_AX_RC STUB_CHROME_TABS_2 STUB_CHROME_CALLS

# The two callers want the same failure reported two different ways. The idle
# job passes --only and reads the status - that is the give-back signal, so it
# must survive. A bare run is the macOS Shortcut, where "Run Shell Script"
# turns any nonzero status into an error dialog, which is far too loud for one
# app keeping a window. Notify there and exit clean.
print -r -- "19. a manual run notifies; only the idle job's --only run exits non-zero"
export STUB_APP_LIST="Bear|net.shinyfrog.bear
"
export STUB_NOTIFY_LOG="$WORK/notify.log"
export STUB_WINDOW_COUNT=2 STUB_AX_RC=1   # AX fails, keystrokes prove nothing
: > "$AXCAP"
print -r -- "defaults:
  manual: quit
  auto: quit
apps:
  Bear: {manual: close}" > "$ROOT/config/app-lifecycle.yaml"

run
check     "a bare run exits 0 despite the failure" "$(( RC == 0 ))" "1"
check     "and posts a notification"               "$(cat "$STUB_NOTIFY_LOG")" "display notification"
check     "naming the rung and the app"            "$(cat "$STUB_NOTIFY_LOG")" "close: Bear"
check     "while still saying so on stdout"        "$OUT" "Failed actions: close: Bear"

run --only Bear
check     "the idle job's run still exits non-zero" "$(( RC != 0 ))" "1"
check_not "and does not notify"                     "$(cat "$STUB_NOTIFY_LOG")" "display notification"
unset STUB_AX_RC STUB_NOTIFY_LOG

# --- defaults.manual reaches apps the config never names -------------------
# Test 6 pins the `quit` default, which is also what an unlisted app got when
# the dispatch ignored defaults.manual entirely - so it cannot tell the two
# apart. These two configs can: under them, quitting Safari is the bug.
print -r -- "20. an unlisted app takes whatever defaults.manual says"
export STUB_APP_LIST="Ghostty|com.mitchellh.ghostty
Safari|com.apple.Safari
"
print -r -- "defaults:"$'\n'"  manual: close"$'\n'"apps:"$'\n'"  Ghostty: {manual: skip}" \
    > "$ROOT/config/app-lifecycle.yaml"
run --dry-run
check     "a close default closes it"      "$OUT" "Would CLOSE WINDOWS (1):
  - Safari"
check     "and quits nothing"              "$OUT" "Would QUIT (0):"
check     "a named app keeps its own value" "$OUT" "Would SKIP (no-touch):
  - Ghostty"

# The mirror of the bug above, and the one the first fix introduced. Only the
# skip/hide/close apps get their own bucket, so a listed app whose `manual:` is
# an explicit `quit` reaches the same fallback an unlisted app does - and reading
# defaults.manual there unconditionally let a gentler default overrule it.
print -r -- "defaults:"$'\n'"  manual: close"$'\n'"apps:"$'\n'"  Safari: {manual: quit}" \
    > "$ROOT/config/app-lifecycle.yaml"
run --dry-run
check     "an explicit quit outranks a gentler default" "$OUT" "Would QUIT (1):
  - Safari"
check     "and is not downgraded to close"              "$OUT" "Would CLOSE WINDOWS (1):
  - Ghostty"

print -r -- "defaults:"$'\n'"  manual: skip"$'\n'"protect_windows:"$'\n'"  - Google Meet" \
    > "$ROOT/config/app-lifecycle.yaml"
run --dry-run
check     "a skip default touches nothing" "$OUT" "Would QUIT (0):"
check     "not even to close"              "$OUT" "Would CLOSE WINDOWS (0):"
check     "both apps are skipped"          "$OUT" "Would SKIP (no-touch):
  - Ghostty
  - Safari"

# Test 18 covers the branch taken when NO window is worth keeping, which returns
# before pass 2 ever runs - so the ID-close itself went unchecked. It ended with a
# bare `|| true` and returned 0 whatever happened. The idle caller reads 0 as "the
# close rung completed" and keeps the `closed` phase it wrote before the call, so a
# window that never closed is quit by quit_after instead of being retried.
print -r -- "21. pass 2 reports whether the targeted windows actually closed"
cp "$REPO/config/app-lifecycle.yaml" "$ROOT/config/app-lifecycle.yaml"
export STUB_APP_LIST="Google Chrome|com.google.Chrome
"
export STUB_CHROME_CALLS="$WORK/chrome.calls"
# Both windows are still there at the rescan, so pass 2 runs for real: window 2 is
# protected, window 1 is the target. Test 15 drops the protected tab instead, which
# is why it lands in the other branch.
export STUB_CHROME_TABS_2="1|Inbox (3) - Gmail
2|Google Meet - standup
"
export STUB_CHROME_TABS_3="2|Google Meet - standup
"
run --only "Google Chrome" --max-action close
check     "a closed target exits 0"            "$(( RC == 0 ))" "1"
check_not "and the protected window survives"  "$OUT" "Quitting Google Chrome"

# Same path, target still open on the verification read.
export STUB_CHROME_TABS_3="$STUB_CHROME_TABS_2"
run --only "Google Chrome" --max-action close
check     "a target left open exits non-zero"  "$(( RC != 0 ))" "1"
unset STUB_CHROME_TABS_2 STUB_CHROME_TABS_3 STUB_CHROME_CALLS

# --- a broken config stops us dead -----------------------------------------
# The default action here is "quit", so a config we cannot read must abort
# rather than fall back to defaults and quit everything.
print -r -- "8. an unreadable config aborts instead of guessing"
print -r -- "defaults:"$'\n'"  close_after: abc" > "$ROOT/config/app-lifecycle.yaml"
run --dry-run
check     "exits non-zero"                 "$(( RC != 0 ))" "1"
check     "names the offending key"        "$ERR" "close_after"
check_not "acts on nothing"                "$OUT" "Would QUIT"

print -r -- ""
print -r -- "PASS=$PASS FAIL=$FAIL"
(( FAIL == 0 )) || exit 1
