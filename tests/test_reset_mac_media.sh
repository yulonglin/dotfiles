#!/usr/bin/env bash

set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/custom_bins/reset-mac-media"
TMP_BASE="${TMPDIR:-/tmp}"
WORK="$(mktemp -d "${TMP_BASE%/}/reset-mac-media-test.XXXXXX")" || {
    echo "FATAL: could not create test directory" >&2
    exit 1
}
trap '/bin/rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
RUN_RC=0
RUN_OUT=""

pass() {
    PASS=$((PASS + 1))
    echo "ok   - $1"
}

fail() {
    FAIL=$((FAIL + 1))
    echo "FAIL - $1" >&2
}

assert_contains() {
    local description="$1"
    local haystack="$2"
    local needle="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        pass "$description"
    else
        fail "$description (missing: $needle)"
    fi
}

assert_not_contains() {
    local description="$1"
    local haystack="$2"
    local needle="$3"
    if [[ "$haystack" != *"$needle"* ]]; then
        pass "$description"
    else
        fail "$description (unexpected: $needle)"
    fi
}

assert_success() {
    local description="$1"
    if (( RUN_RC == 0 )); then
        pass "$description"
    else
        fail "$description (rc=$RUN_RC, output: $RUN_OUT)"
    fi
}

assert_failure() {
    local description="$1"
    if (( RUN_RC != 0 )); then
        pass "$description"
    else
        fail "$description (unexpected success)"
    fi
}

BIN="$WORK/bin"
mkdir -p "$BIN"

# One stub backs every external command. The sudo branch records its child but
# never executes it, so a broken test cannot reach the real killall.
STUB="$BIN/command-stub"
# The single-quoted lines are the source of the generated stub; expansion must
# happen when that stub runs, not while this test constructs it.
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -u' \
    'name=${0##*/}' \
    'printf "%s" "$name" >> "$STUB_EVENTS"' \
    'printf " %q" "$@" >> "$STUB_EVENTS"' \
    'printf "\n" >> "$STUB_EVENTS"' \
    'mark_killed() {' \
    '    local target="${1##*/}"' \
    '    [[ "$target" == "killall" ]] && target="${2:-}"' \
    '    [[ -n "$target" ]] && : > "$STUB_STATE/$target.killed"' \
    '}' \
    'case "$name" in' \
    '    uname) printf "%s\n" "${STUB_UNAME:-Darwin}" ;;' \
    '    date) printf "%s\n" "20260824-210000" ;;' \
    '    id) printf "501\n" ;;' \
    '    sw_vers) printf "ProductVersion: 15.6\n" ;;' \
    '    uptime) printf "up 3 days\n" ;;' \
    '    vm_stat) printf "Pages free: 100000.\n" ;;' \
    '    df) printf "Filesystem Size Used Avail Capacity Mounted on\n/dev/disk 1T 100G 900G 10%% /\n" ;;' \
    '    pmset) printf "No assertions.\n" ;;' \
    '    ps) printf "  PID STAT ELAPSED %%CPU %%MEM COMMAND\n  111 S 01:00 0.0 0.1 Spotify\n" ;;' \
    '    log)' \
    '        if [[ "${STUB_LOG_FAIL:-0}" == 1 ]]; then exit 9; fi' \
    '        printf "relevant log line\n"' \
    '        ;;' \
    '    sample)' \
    '        if [[ "${STUB_SAMPLE_FAIL:-0}" == 1 ]]; then exit 8; fi' \
    '        printf "sample for %s\n" "${1:-unknown}"' \
    '        ;;' \
    '    pgrep)' \
    '        target="${*: -1}"' \
    '        if [[ "$target" == avconferenced && "${STUB_AV_DORMANT:-1}" == 1 ]]; then exit 1; fi' \
    '        old=101; new=201' \
    '        case "$target" in audiomxd) old=102; new=202 ;; systemsoundserverd) old=103; new=203 ;; avconferenced) old=104; new=204 ;; esac' \
    '        if [[ -e "$STUB_STATE/$target.killed" && "${STUB_STALE_PROCESS:-}" != "$target" ]]; then printf "%s\n" "$new"; else printf "%s\n" "$old"; fi' \
    '        ;;' \
    '    launchctl)' \
    '        label="${2:-}"' \
    '        target=coreaudiod' \
    '        case "$label" in *audiomxd) target=audiomxd ;; *systemsoundserverd) target=systemsoundserverd ;; *videoconference.camera) target=avconferenced ;; esac' \
    '        if [[ "$target" == avconferenced && "${STUB_AV_DORMANT:-1}" == 1 ]]; then printf "state = not running\n"; exit 0; fi' \
    '        if [[ -e "$STUB_STATE/$target.killed" && "${STUB_CRASHED_PROCESS:-}" == "$target" ]]; then printf "state = not running\nlast exit code = 6\n"; exit 0; fi' \
    '        if [[ -e "$STUB_STATE/$target.killed" && "${STUB_DORMANT_PROCESS:-}" == "$target" ]]; then printf "state = not running\n"; exit 0; fi' \
    '        old=101; new=201' \
    '        case "$target" in audiomxd) old=102; new=202 ;; systemsoundserverd) old=103; new=203 ;; avconferenced) old=104; new=204 ;; esac' \
    '        if [[ -e "$STUB_STATE/$target.killed" && "${STUB_STALE_PROCESS:-}" != "$target" ]]; then pid=$new; else pid=$old; fi' \
    '        printf "state = running\npid = %s\n" "$pid"' \
    '        ;;' \
    '    sudo)' \
    '        if [[ "${1:-}" == -v ]]; then' \
    '            [[ "${STUB_SUDO_FAIL:-0}" == 1 ]] && exit 1' \
    '            exit 0' \
    '        fi' \
    '        sentinel=no' \
    '        compgen -G "$STUB_REPORT_ROOT/*/capture-complete" >/dev/null && sentinel=yes' \
    '        printf "sudo-sentinel %s\n" "$sentinel" >> "$STUB_EVENTS"' \
    '        mark_killed "${1:-}" "${2:-}"' \
    '        ;;' \
    '    killall)' \
    '        mark_killed "$name" "${1:-}"' \
    '        [[ "${1:-}" == avconferenced && "${STUB_AV_DORMANT:-1}" == 1 ]] && exit 1' \
    '        ;;' \
    '    sleep) ;;' \
    'esac' > "$STUB"
chmod +x "$STUB"

for command_name in uname date id sw_vers uptime vm_stat df pmset ps log sample pgrep launchctl sudo killall sleep; do
    ln -s command-stub "$BIN/$command_name"
done

setup_case() {
    CASE_ROOT="$WORK/case-$RANDOM-$RANDOM"
    STUB_STATE="$CASE_ROOT/state"
    STUB_REPORT_ROOT="$CASE_ROOT/reports"
    STUB_USER_DIAGNOSTICS="$CASE_ROOT/user-diagnostics"
    STUB_SYSTEM_DIAGNOSTICS="$CASE_ROOT/system-diagnostics"
    STUB_EVENTS="$CASE_ROOT/events"
    mkdir -p "$STUB_STATE" "$STUB_REPORT_ROOT" \
        "$STUB_USER_DIAGNOSTICS" "$STUB_SYSTEM_DIAGNOSTICS"
    : > "$STUB_EVENTS"
    export STUB_STATE STUB_REPORT_ROOT STUB_EVENTS
    unset STUB_UNAME STUB_LOG_FAIL STUB_SAMPLE_FAIL STUB_SUDO_FAIL \
        STUB_STALE_PROCESS STUB_DORMANT_PROCESS STUB_CRASHED_PROCESS
    export STUB_AV_DORMANT=1
}

run_helper() {
    RUN_RC=0
    RUN_OUT="$(
        RMM_UNAME_BIN="$BIN/uname" \
        RMM_DATE_BIN="$BIN/date" \
        RMM_ID_BIN="$BIN/id" \
        RMM_SW_VERS_BIN="$BIN/sw_vers" \
        RMM_UPTIME_BIN="$BIN/uptime" \
        RMM_VM_STAT_BIN="$BIN/vm_stat" \
        RMM_DF_BIN="$BIN/df" \
        RMM_PMSET_BIN="$BIN/pmset" \
        RMM_PS_BIN="$BIN/ps" \
        RMM_LOG_BIN="$BIN/log" \
        RMM_SAMPLE_BIN="$BIN/sample" \
        RMM_PGREP_BIN="$BIN/pgrep" \
        RMM_LAUNCHCTL_BIN="$BIN/launchctl" \
        RMM_USER_KILLALL_BIN="$BIN/killall" \
        RMM_SLEEP_BIN="$BIN/sleep" \
        RMM_USER_DIAGNOSTIC_DIR="$STUB_USER_DIAGNOSTICS" \
        RMM_SYSTEM_DIAGNOSTIC_DIR="$STUB_SYSTEM_DIAGNOSTICS" \
        TEST_SUDO_BIN="$BIN/sudo" \
        bash -c '
            source "$1"
            shift
            run_sudo() { "$TEST_SUDO_BIN" "$@"; }
            main "$@"
        ' reset-mac-media-test "$SCRIPT" "$@" 2>&1
    )" || RUN_RC=$?
}

echo "1. help is non-destructive"
setup_case
run_helper --help
assert_success "--help exits successfully"
assert_contains "help documents dry-run" "$RUN_OUT" "--dry-run"
assert_contains "help documents report location" "$RUN_OUT" "--report-dir"
if [[ ! -s "$STUB_EVENTS" ]]; then
    pass "--help invokes no external commands"
else
    fail "--help invoked external commands"
fi

echo "2. non-macOS fails closed"
setup_case
export STUB_UNAME=Linux
run_helper --yes --report-dir "$STUB_REPORT_ROOT"
assert_failure "non-macOS exits nonzero"
assert_contains "non-macOS error is explicit" "$RUN_OUT" "macOS only"
assert_not_contains "non-macOS does not authenticate" "$(<"$STUB_EVENTS")" "sudo"

echo "3. dry-run describes the bounded action without writing or restarting"
setup_case
run_helper --dry-run --report-dir "$STUB_REPORT_ROOT"
assert_success "dry-run exits successfully"
assert_contains "dry-run names CoreAudio" "$RUN_OUT" "coreaudiod"
assert_contains "dry-run names the report root" "$RUN_OUT" "$STUB_REPORT_ROOT"
if [[ -z "$(rg --files "$STUB_REPORT_ROOT")" ]]; then
    pass "dry-run creates no report"
else
    fail "dry-run created files"
fi
assert_not_contains "dry-run does not authenticate" "$(<"$STUB_EVENTS")" "sudo"

echo "4. happy path captures first, restarts only four services, and verifies"
setup_case
run_helper --yes --report-dir "$STUB_REPORT_ROOT"
assert_success "healthy restart exits successfully"
REPORT="$(dirname "$(rg --files "$STUB_REPORT_ROOT" -g capture-complete | head -1)")"
if [[ -n "$REPORT" && -f "$REPORT/capture-complete" ]]; then
    pass "capture sentinel exists"
else
    fail "capture sentinel missing"
fi
if [[ -n "$REPORT" && "$(stat -f '%Lp' "$REPORT")" == 700 ]]; then
    pass "report directory is mode 0700"
else
    fail "report directory mode is not 0700"
fi
EVENTS="$(<"$STUB_EVENTS")"
assert_contains "first privileged restart sees completed capture" "$EVENTS" "sudo-sentinel yes"
assert_contains "coreaudiod is restarted as root" "$EVENTS" "sudo /usr/bin/killall coreaudiod"
assert_contains "audiomxd is restarted as root" "$EVENTS" "sudo /usr/bin/killall audiomxd"
assert_contains "system sound server is restarted as root" "$EVENTS" "sudo /usr/bin/killall systemsoundserverd"
assert_contains "avconferenced is restarted unprivileged" "$EVENTS" "killall avconferenced"
KILL_EVENTS="$(printf '%s\n' "$EVENTS" | rg '(^killall |^sudo .*killall )')"
assert_not_contains "restart scope excludes Spotify" "$KILL_EVENTS" "Spotify"
assert_not_contains "restart scope excludes FaceTime" "$KILL_EVENTS" "FaceTime"
assert_not_contains "restart scope excludes FineTune" "$KILL_EVENTS" "FineTune"
assert_not_contains "restart scope excludes Bluetooth" "$KILL_EVENTS" "bluetoothd"
assert_contains "FaceTime launchd job is verified by its real label" "$EVENTS" "gui/501/com.apple.videoconference.camera"

echo "5. optional diagnostic failures are recorded but do not block recovery"
setup_case
export STUB_LOG_FAIL=1 STUB_SAMPLE_FAIL=1
run_helper --yes --report-dir "$STUB_REPORT_ROOT"
assert_success "collector failures do not block a healthy recovery"
REPORT="$(dirname "$(rg --files "$STUB_REPORT_ROOT" -g capture-complete | head -1)")"
assert_contains "collector failures are auditable" "$(<"$REPORT/collector-errors.txt")" "unified log"
assert_contains "restart still occurs after collector failure" "$(<"$STUB_EVENTS")" "sudo /usr/bin/killall coreaudiod"

echo "6. report setup failure and sudo failure both prevent restarts"
setup_case
BAD_ROOT="$CASE_ROOT/not-a-directory"
: > "$BAD_ROOT"
run_helper --yes --report-dir "$BAD_ROOT"
assert_failure "unwritable report root fails"
assert_not_contains "report failure causes no restart" "$(<"$STUB_EVENTS")" "killall"

setup_case
export STUB_SUDO_FAIL=1
run_helper --yes --report-dir "$STUB_REPORT_ROOT"
assert_failure "sudo authentication failure is reported"
EVENTS="$(<"$STUB_EVENTS")"
assert_contains "sudo authentication was attempted" "$EVENTS" "sudo -v"
assert_not_contains "sudo authentication failure causes no kill" "$EVENTS" "killall"

echo "7. stale CoreAudio PID fails verification without broader escalation"
setup_case
export STUB_STALE_PROCESS=coreaudiod
run_helper --yes --report-dir "$STUB_REPORT_ROOT"
assert_failure "stale coreaudiod fails recovery"
assert_contains "verification failure names coreaudiod" "$RUN_OUT" "coreaudiod"
EVENTS="$(<"$STUB_EVENTS")"
assert_not_contains "timeout never escalates to SIGKILL" "$EVENTS" "-KILL"
assert_not_contains "timeout never touches WindowServer" "$EVENTS" "WindowServer"

echo "8. a successfully stopped system job may remain loaded and dormant"
setup_case
export STUB_DORMANT_PROCESS=coreaudiod
run_helper --yes --report-dir "$STUB_REPORT_ROOT"
assert_success "loaded-but-dormant coreaudiod is accepted after its old PID disappears"

echo "9. crash-report capture is newest-first and count-bounded"
setup_case
printf 'old\n' > "$STUB_USER_DIAGNOSTICS/FaceTime-old.ips"
/usr/bin/touch -A -100000 "$STUB_USER_DIAGNOSTICS/FaceTime-old.ips"
for report_number in 1 2 3 4 5 6; do
    printf 'new %s\n' "$report_number" \
        > "$STUB_USER_DIAGNOSTICS/FaceTime-new-${report_number}.ips"
done
run_helper --yes --report-dir "$STUB_REPORT_ROOT"
assert_success "bounded crash-report capture completes"
REPORT="$(dirname "$(rg --files "$STUB_REPORT_ROOT" -g capture-complete | head -1)")"
assert_contains "at most six crash reports are copied" \
    "$(<"$REPORT/crash-reports/count.txt")" "6 recent crash report(s) copied"
if rg --files "$REPORT/crash-reports" | rg -q 'FaceTime-old\.ips$'; then
    fail "older crash report displaced a newer report"
else
    pass "newest reports are selected before the older report"
fi

echo "10. a crash-throttled dormant job is not reported as recovered"
setup_case
export STUB_AV_DORMANT=0 STUB_CRASHED_PROCESS=avconferenced
run_helper --yes --report-dir "$STUB_REPORT_ROOT"
assert_failure "nonzero avconferenced exit fails recovery verification"
assert_contains "crash verification names avconferenced" "$RUN_OUT" "avconferenced"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
(( FAIL == 0 ))
