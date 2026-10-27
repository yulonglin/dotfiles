#!/usr/bin/env bash
# Tests custom_bins/coreaudio-watch with a fake probe, a fake notifier and a
# temporary state directory, so nothing here talks to CoreAudio or posts a real
# notification. The positive report is the header of the real 2026-10-26
# Telegram hang report that named "Deadlock: coreaudiod".

set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/custom_bins/coreaudio-watch"
FIXTURE="$REPO_ROOT/tests/fixtures/coreaudio-watch/coreaudiod-deadlock.hang.header"
TMP_BASE="${TMPDIR:-/tmp}"
WORK="$(mktemp -d "${TMP_BASE%/}/coreaudio-watch-test.XXXXXX")" || {
    echo "FATAL: could not create test directory" >&2
    exit 1
}
trap '/bin/rm -rf "$WORK"' EXIT

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "FAIL - $1" >&2; }

if [[ "$(uname -s)" != Darwin ]]; then
    echo "skip - coreaudio-watch is macOS-only"
    exit 0
fi

STATE="$WORK/state"
REPORTS="$WORK/reports"
NOTES="$WORK/notifications.txt"
NOTE_ARGS="$WORK/notification-args.txt"
PROBE_RC_FILE="$WORK/probe-rc"
PROBE_CALLS="$WORK/probe-calls"
mkdir -p "$STATE" "$REPORTS"
: > "$NOTES"
: > "$PROBE_CALLS"

# The fake probe exits with whatever code the test wrote, and prints a crash
# list for exit 3 the way reset-mac-media --check does.
FAKE_PROBE="$WORK/reset-mac-media"
cat > "$FAKE_PROBE" <<EOF
#!/bin/bash
echo "\$*" >> "$PROBE_CALLS"
rc=\$(cat "$PROBE_RC_FILE")
if [[ \$rc == 3 ]]; then
    echo "reset-mac-media: CoreAudio answered in 1s"
    echo "reset-mac-media: 1 media-daemon crash report(s) in the last 20 min:"
    echo "  avconferenced-2026-10-26-150000.ips"
fi
exit \$rc
EOF
FAKE_NOTIFIER="$WORK/notifier"
cat > "$FAKE_NOTIFIER" <<EOF
#!/bin/bash
# Records the full argument list, then the title, which follows -title.
printf '%s\n' "\$*" >> "$NOTE_ARGS"
while (( \$# > 0 )); do
    [[ \$1 == -title ]] && { echo "\$2" >> "$NOTES"; break; }
    shift
done
EOF
chmod +x "$FAKE_PROBE" "$FAKE_NOTIFIER"

NOW=1800000000
run_watch() {
    CAW_STATE_DIR="$STATE" CAW_REPORT_DIRS="$REPORTS" CAW_RESET_BIN="$FAKE_PROBE" \
        CAW_NOTIFIER="$FAKE_NOTIFIER" CAW_OSASCRIPT=/usr/bin/false CAW_NOW="$NOW" \
        "$SCRIPT" "$@" > "$WORK/last-output" 2>&1
}
probe_count() { wc -l < "$PROBE_CALLS" | tr -d ' '; }
note_count() { wc -l < "$NOTES" | tr -d ' '; }
last_note() { tail -n 1 "$NOTES"; }
set_probe() { echo "$1" > "$PROBE_RC_FILE"; }
# Report mtimes must be strictly newer than the scan stamp.
add_report() { sleep 1; cp "$1" "$REPORTS/$2"; }

# 1. First run probes once and leaves the stamp, but never scans history.
cp "$FIXTURE" "$REPORTS/Telegram_old.hang"
set_probe 0
run_watch
[[ "$(probe_count)" == 1 ]] && pass "first run probes once" || fail "first run probes once (calls: $(probe_count))"
[[ -f "$STATE/scan-stamp" ]] && pass "first run writes the scan stamp" || fail "first run writes the scan stamp"
grep -q 'Telegram_old' "$WORK/last-output" && fail "first run must not scan old reports" || pass "first run does not scan old reports"
[[ "$(note_count)" == 0 ]] && pass "healthy first run posts nothing" || fail "healthy first run posts nothing"

# 2. Healthy, no new reports, inside the backstop window: no probe at all.
NOW=$((NOW + 120))
run_watch
[[ "$(probe_count)" == 1 ]] && pass "quiet healthy run skips the probe" || fail "quiet healthy run skips the probe (calls: $(probe_count))"

# 3. An unrelated hang report does not trigger a probe.
grep -v 'Deadlock' "$FIXTURE" > "$WORK/benign.hang"
add_report "$WORK/benign.hang" "Slack_benign.hang"
NOW=$((NOW + 120))
run_watch
[[ "$(probe_count)" == 1 ]] && pass "hang report without a coreaudiod deadlock is ignored" || fail "benign hang report triggered a probe"

# 4. The real deadlock header triggers a probe; a wedged answer notifies once.
add_report "$FIXTURE" "Telegram_deadlock.hang"
set_probe 1
NOW=$((NOW + 120))
run_watch
[[ "$(probe_count)" == 2 ]] && pass "coreaudiod deadlock report triggers a probe" || fail "coreaudiod deadlock report triggers a probe (calls: $(probe_count))"
[[ "$(last_note)" == "CoreAudio is wedged" ]] && pass "wedge posts a notification" || fail "wedge posts a notification (got: $(last_note))"
# The banner itself must say what to run, and a click must open the runbook.
wedge_args="$(tail -n 1 "$NOTE_ARGS")"
[[ "$wedge_args" == *"Run reset-mac-media in a terminal, type y, then your password"* ]] \
    && pass "wedge notification gives the fix steps" || fail "wedge notification gives the fix steps (got: $wedge_args)"
[[ "$wedge_args" == *"-open https://github.com/yulonglin/dotfiles/blob/main/docs/macos-media-wedge.md#fix-it-with-reset-mac-media"* ]] \
    && pass "wedge notification opens the runbook on click" || fail "wedge notification opens the runbook on click (got: $wedge_args)"
[[ "$(cat "$STATE/status")" == wedged ]] && pass "state is wedged" || fail "state is wedged"

# 5. Still wedged two minutes later: probed (state is wedged) but no repeat.
NOW=$((NOW + 120))
run_watch
[[ "$(probe_count)" == 3 ]] && pass "wedged state probes every run" || fail "wedged state probes every run (calls: $(probe_count))"
[[ "$(note_count)" == 1 ]] && pass "no duplicate notification inside the reminder window" || fail "duplicate notification (count: $(note_count))"

# 6. Still wedged an hour after the first notification: one reminder.
NOW=$((NOW + 3600))
run_watch
[[ "$(last_note)" == "CoreAudio still wedged" ]] && pass "hourly reminder while wedged" || fail "hourly reminder while wedged (got: $(last_note))"

# 7. Probe inconclusive: no state change, no notification.
set_probe 4
NOW=$((NOW + 120))
before=$(note_count)
run_watch
[[ "$(note_count)" == "$before" && "$(cat "$STATE/status")" == wedged ]] \
    && pass "inconclusive probe changes nothing" || fail "inconclusive probe changed state or notified"

# 8. Recovery notifies and returns to healthy.
set_probe 0
NOW=$((NOW + 120))
run_watch
[[ "$(last_note)" == "CoreAudio recovered" ]] && pass "recovery posts a notification" || fail "recovery posts a notification (got: $(last_note))"
[[ "$(tail -n 1 "$NOTE_ARGS")" != *"-open"* ]] && pass "recovery notification has no click action" || fail "recovery notification has no click action"
[[ "$(cat "$STATE/status")" == healthy ]] && pass "state is healthy after recovery" || fail "state is healthy after recovery"

# 9. Crash reports while audio answers notify once per new batch.
set_probe 3
NOW=$((NOW + 1000))
run_watch
[[ "$(last_note)" == "Media daemons crashed" ]] && pass "crash batch posts a notification" || fail "crash batch posts a notification (got: $(last_note))"
before=$(note_count)
NOW=$((NOW + 1000))
run_watch
[[ "$(note_count)" == "$before" ]] && pass "same crash batch is not re-notified" || fail "same crash batch re-notified"

# 10. --dry-run writes no state and posts nothing.
DRY_STATE="$WORK/dry-state"
set_probe 1
CAW_STATE_DIR="$DRY_STATE" CAW_REPORT_DIRS="$REPORTS" CAW_RESET_BIN="$FAKE_PROBE" \
    CAW_NOTIFIER="$FAKE_NOTIFIER" CAW_NOW="$NOW" "$SCRIPT" --dry-run > "$WORK/dry-output" 2>&1
before_dry=$(note_count)
[[ ! -e "$DRY_STATE" ]] && pass "dry run writes no state" || fail "dry run wrote state"
grep -q 'notify: CoreAudio is wedged' "$WORK/dry-output" && [[ "$(note_count)" == "$before_dry" ]] \
    && pass "dry run reports the notification without posting it" || fail "dry run notification handling"

echo
echo "passed: $PASS  failed: $FAIL"
(( FAIL == 0 ))
