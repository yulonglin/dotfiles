#!/usr/bin/env bash
# shellcheck shell=bash
# ═══════════════════════════════════════════════════════════════════════════════
# Stall canary — the installers must finish, or fail, but never hang.
# ═══════════════════════════════════════════════════════════════════════════════
# This stalling class has been declared fixed before and came back, because the
# earlier fixes were reasoned about rather than reproduced. So every check here
# either RUNS the real code under a hard wall-clock deadline, or proves the
# canary itself can still catch a stall.
#
# Two things make a check trustworthy here:
#   1. It fails when the guard is removed. test_canary_detects_a_real_stall
#      plants an actual sleeping command and asserts the harness reports a
#      timeout — if that check ever passes vacuously, every other check below
#      is worthless, so it runs first.
#   2. It never depends on network, sudo, or the machine's own state.
#
# The failure mode being guarded is specifically "a TTY exists but nobody is
# watching it": tmux panes, agent ptys, `ssh host ./deploy.sh`, cron. Those
# runs have historically hung at the component menu, at sudo, at chsh, and —
# the one that outlived the prompt fixes — inside a silent `cargo build`.
#
# Usage: tests/test_no_stall.sh [--verbose]
set -uo pipefail

DOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERBOSE=false
[[ "${1:-}" == "--verbose" ]] && VERBOSE=true

PASS=0
FAIL=0
declare -a FAILURES=()

pass() { PASS=$((PASS + 1)); printf '  \033[32mPASS\033[0m %s\n' "$1"; }
fail() {
    FAIL=$((FAIL + 1))
    FAILURES+=("$1")
    printf '  \033[31mFAIL\033[0m %s\n' "$1"
    [[ -n "${2:-}" ]] && printf '       %s\n' "$2"
}

# Run a command with stdin closed under a hard deadline.
# Prints the exit status; 124 means the deadline fired (i.e. it stalled).
run_bounded() {
    local secs="$1"; shift
    local out
    out=$(timeout --foreground "$secs" "$@" 2>&1)
    local rc=$?
    [[ "$VERBOSE" == true ]] && printf '%s\n' "$out" | tail -5
    echo "$rc"
}

require_timeout_cmd() {
    # This used to `exit 0`, which made the whole canary report success on
    # macOS — the one platform where the guards were weakest and CI never runs.
    # A suite that passes by not running is worse than no suite, so a missing
    # timeout(1) is now a hard failure that names its own fix.
    if ! command -v timeout >/dev/null 2>&1 && ! command -v gtimeout >/dev/null 2>&1; then
        echo "FAIL: neither timeout(1) nor gtimeout is available, so this suite" >&2
        echo "      cannot bound anything and would pass vacuously." >&2
        echo "      On macOS: brew install coreutils (provides gtimeout)." >&2
        exit 1
    fi
    # gtimeout-only (a Mac with coreutils) still runs everything below; the
    # harness itself needs a bounding binary, so alias the name it uses.
    if ! command -v timeout >/dev/null 2>&1; then
        timeout() { gtimeout "$@"; }
    fi
}

# ─── 0. The canary must be able to fail ──────────────────────────────────────

test_canary_detects_a_real_stall() {
    # A guard that cannot fail proves nothing. Plant a real 30s sleep behind a
    # 2s deadline and require the harness to report the timeout.
    local rc
    rc=$(run_bounded 2 sleep 30)
    if [[ "$rc" == "124" ]]; then
        pass "canary itself detects a real stall (sleep 30 under a 2s deadline → 124)"
    else
        fail "canary cannot detect a stall — every other check here is vacuous" "expected 124, got $rc"
    fi
}

# ─── 1. The deadline helpers behave ──────────────────────────────────────────

helper_probe() {
    # Source helpers.sh in a zsh subshell and run one expression against it.
    zsh -c "
        DOT_DIR='$DOT_DIR'
        source '$DOT_DIR/config.sh' >/dev/null 2>&1
        source '$DOT_DIR/scripts/shared/helpers.sh' >/dev/null 2>&1
        $1
    "
}

test_run_with_timeout_bounds_a_hang() {
    # Exit code cannot discriminate here: the inner deadline and the outer
    # harness deadline both surface as 124. Elapsed time can — the inner
    # deadline is 2s, the outer is 20s, so anything under 10s proves the inner
    # one fired. (An earlier version of this check asserted on the exit code
    # and failed against a working implementation.)
    local start elapsed
    start=$SECONDS
    timeout --foreground 20 zsh -c "
        DOT_DIR='$DOT_DIR'
        source '$DOT_DIR/config.sh' >/dev/null 2>&1
        source '$DOT_DIR/scripts/shared/helpers.sh' >/dev/null 2>&1
        run_with_timeout 2 sleep 60
    " >/dev/null 2>&1
    elapsed=$((SECONDS - start))
    if (( elapsed < 10 )); then
        pass "run_with_timeout bounds a hanging command (returned in ${elapsed}s, not 60s)"
    else
        fail "run_with_timeout did not bound a 60s sleep" "took ${elapsed}s — outer deadline fired instead"
    fi
}

test_run_with_timeout_zero_disables() {
    local out
    out=$(helper_probe 'run_with_timeout 0 echo ran-without-deadline' 2>&1)
    if [[ "$out" == *"ran-without-deadline"* ]]; then
        pass "run_with_timeout 0 runs the command without a deadline"
    else
        fail "run_with_timeout 0 did not run the command" "$out"
    fi
}

test_fetch_carries_deadlines() {
    # Assert the flags, not a live request: the canary must not need network.
    local out
    out=$(helper_probe 'functions fetch' 2>&1)
    if [[ "$out" == *"--connect-timeout"* && "$out" == *"--max-time"* ]]; then
        pass "fetch() carries --connect-timeout and --max-time"
    else
        fail "fetch() is missing connect/overall deadlines" "$out"
    fi
}

test_claude_tools_fetch_is_bounded() {
    # The specific untimed curl that ran at the top of every install.
    local out
    out=$(helper_probe 'functions _fetch_claude_tools' 2>&1)
    if [[ "$out" == *"--max-time"* ]]; then
        pass "_fetch_claude_tools' curl carries a deadline"
    else
        fail "_fetch_claude_tools still has an untimed curl" "this is the top-of-run stall"
    fi
}

test_every_cargo_build_is_bounded() {
    # The probe below covers ONE helper. deploy.sh had its own
    # `cargo build --release --quiet`, backgrounded and reaped by a bare
    # `wait` with no deadline — the same stall class, in the shipped path,
    # while the guard stayed green. Check the class: every cargo build in the
    # install path must be wrapped in a deadline.
    local hits
    hits=$(grep -nE 'cargo build' \
        "$DOT_DIR"/install.sh "$DOT_DIR"/deploy.sh "$DOT_DIR"/scripts/shared/helpers.sh 2>/dev/null \
        | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' \
        | grep -v 'run_with_timeout' || true)
    if [[ -z "$hits" ]]; then
        pass "every cargo build in the install path carries a deadline"
    else
        fail "unbounded cargo build(s) found" "$hits"
    fi
}

test_run_parallel_pid_capture_is_quoted() {
    # In zsh an UNQUOTED $! on the RHS of an array-subscript assignment is not
    # expanded — `pids[$name]=$!` stores the literal string "$!", every later
    # `kill -0` fails, and the whole bounded-wait block becomes dead code while
    # test_parallel_group_is_bounded still passes (run_parallel just returns
    # instantly). Verified on zsh 5.9: unquoted -> [$!], quoted -> [12345].
    if grep -qE 'pids\[\$name\]="\$!"' "$DOT_DIR/scripts/shared/helpers.sh"; then
        pass "run_parallel captures its child PIDs (quoted \$!)"
    else
        fail "run_parallel's PID capture is unquoted" "the bounded wait is dead code in zsh"
    fi
}

test_bounded_menu_does_not_abort_the_script() {
    # Both scripts run under `set -euo pipefail`, and in zsh a failing command
    # substitution in a plain assignment aborts the script right there. Without
    # `|| rc=$?` the 124 branch is unreachable and an unattended TTY run dies
    # silently after the timeout, having installed nothing — the inverse of
    # what the deadline was added to do. Verified under a pty.
    local out
    out=$(grep -A2 'claude-tools select' "$DOT_DIR/scripts/shared/helpers.sh" | grep 'items_file')
    if [[ "$out" == *'|| rc=$?'* ]]; then
        pass "the component menu's timeout is caught, not fatal under set -e"
    else
        fail "menu timeout aborts the script under set -e" "$out"
    fi
}

test_watchdog_child_keeps_the_terminal() {
    # zsh points a backgrounded job's stdin at /dev/null even when the shell's
    # stdin is a TTY, and `<&0` does not undo it. On the fresh-Mac path (no
    # timeout/gtimeout) that hands the component menu and chsh's PAM prompt an
    # instant EOF.
    local out
    out=$(helper_probe 'functions _watchdog_run' 2>&1)
    if [[ "$out" == *"/dev/tty"* ]]; then
        pass "_watchdog_run re-attaches the terminal for its child"
    else
        fail "_watchdog_run's child gets /dev/null stdin" "TTY-reading commands see instant EOF"
    fi
}

test_retry_does_not_multiply_the_deadline() {
    # `man curl`: --max-time is per TRANSFER, and "the maximum time counter is
    # reset each time the transfer is retried". So --max-time N --retry 2 is up
    # to 3N, not N. --retry-max-time is what bounds the sequence.
    local hits
    hits=$(grep -nE 'curl .*--retry [0-9]' \
        "$DOT_DIR"/install.sh "$DOT_DIR"/deploy.sh "$DOT_DIR"/scripts/shared/helpers.sh 2>/dev/null \
        | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' \
        | grep -v 'retry-max-time' || true)
    if [[ -z "$hits" ]]; then
        pass "every --retry is bounded by --retry-max-time"
    else
        fail "--retry without --retry-max-time multiplies the stated deadline" "$hits"
    fi
}

test_installer_fetches_are_checked_not_interpolated() {
    # `sh -c "$(fetch …)"` does not trip errexit when the fetch fails: sh runs
    # an empty script and exits 0. At one site that followed an `rm -rf`, so a
    # transient network failure deleted a working oh-my-zsh and installed
    # nothing. Every such installer must go through a checked variable.
    local hits
    hits=$(grep -nE '(ba)?sh -c "\$\((fetch|curl)' \
        "$DOT_DIR"/install.sh "$DOT_DIR"/deploy.sh "$DOT_DIR"/scripts/shared/helpers.sh 2>/dev/null \
        | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' || true)
    if [[ -z "$hits" ]]; then
        pass "no installer script is interpolated straight from an unchecked fetch"
    else
        fail "unchecked \$(fetch) piped into a shell" "$hits"
    fi
}

test_source_build_is_bounded_and_visible() {
    local out
    out=$(helper_probe 'functions _build_claude_tools_from_source' 2>&1)
    if [[ "$out" != *"--quiet"* && "$out" == *"run_with_timeout"* ]]; then
        pass "cargo build fallback is bounded and shows its own progress (no --quiet)"
    else
        fail "cargo build fallback is silent or unbounded" "the stall that outlived the prompt fixes"
    fi
}

test_parallel_group_is_bounded() {
    # One hung job must not hang the group. 3 jobs, one sleeping 60s, group
    # deadline 3s: run_parallel must return within the outer 30s deadline.
    local rc
    rc=$(run_bounded 30 zsh -c "
        DOT_DIR='$DOT_DIR'
        source '$DOT_DIR/config.sh' >/dev/null 2>&1
        source '$DOT_DIR/scripts/shared/helpers.sh' >/dev/null 2>&1
        DOTFILES_JOB_TIMEOUT=3 run_parallel 'canary' 'quick|true' 'stuck|sleep 60' 'quick2|true'
    ")
    if [[ "$rc" != "124" ]]; then
        pass "run_parallel bounds a hung job instead of waiting on it forever"
    else
        fail "run_parallel hung on a stuck job" "bare wait regression"
    fi
}

# ─── 2. The real scripts, unattended ─────────────────────────────────────────

test_help_is_instant() {
    for script in install.sh deploy.sh; do
        local rc
        rc=$(run_bounded 20 zsh "$DOT_DIR/$script" --help)
        if [[ "$rc" == "0" ]]; then
            pass "$script --help completes promptly"
        else
            fail "$script --help did not complete" "exit $rc (124 = stalled)"
        fi
    done
}

test_scripts_parse_without_prompting() {
    # --only with a nonexistent component must fail fast on validation. This
    # exercises config.sh + helpers.sh sourcing and parse_args end to end with
    # stdin closed — the path where a prompt at the top would hang.
    for script in install.sh deploy.sh; do
        local rc
        rc=$(run_bounded 30 zsh "$DOT_DIR/$script" --allow-worktree --allow-worktree-deploy --only definitely-not-a-component </dev/null)
        if [[ "$rc" != "124" ]]; then
            pass "$script rejects a bad --only without stalling (exit $rc)"
        else
            fail "$script stalled while parsing arguments" "something prompts before validation"
        fi
    done
}

test_no_untimed_curl_pipe_installers() {
    # The class, not the three instances: any `curl … | bash|sh` that carries no
    # deadline can hang a fresh install forever. Deadlines come from fetch() or
    # from an explicit --max-time, so a bare `curl` piped to a shell is a
    # regression. (Checks source files only, not this test or docs.)
    local hits
    # Two shapes, because only catching the pipe lets the other one back in:
    #   curl … | sh          (the pipe)
    #   sh -c "$(curl …)"    (command substitution — Homebrew's own installer)
    hits=$(grep -nE "curl [^|]*\\|[^|]*(ba)?sh( |$|-)|(ba)?sh -c .*\\\$\\(curl" \
        "$DOT_DIR"/install.sh "$DOT_DIR"/deploy.sh "$DOT_DIR"/scripts/shared/helpers.sh 2>/dev/null \
        | grep -v -- '--max-time' || true)
    if [[ -z "$hits" ]]; then
        pass "no untimed 'curl | sh' or 'sh -c \$(curl …)' installers in the install path"
    else
        fail "untimed curl-pipe installer(s) found" "$hits"
    fi
}

test_deadline_holds_without_coreutils() {
    # The fresh-Mac case, and the one an adversarial review flagged: macOS ships
    # no `timeout`, and `gtimeout` only arrives with coreutils — which install.sh
    # installs AFTER the component menu and the sudo prompt have already run. So
    # the deadline must survive with neither binary available, or the very first
    # run on every new Mac is unbounded.
    local start elapsed
    start=$SECONDS
    timeout --foreground 30 zsh -c "
        DOT_DIR='$DOT_DIR'
        source '$DOT_DIR/config.sh' >/dev/null 2>&1
        source '$DOT_DIR/scripts/shared/helpers.sh' >/dev/null 2>&1
        # Hide both binaries from the lookup the helper uses.
        cmd_exists() { [[ \"\$1\" != timeout && \"\$1\" != gtimeout ]] && command -v \"\$1\" &>/dev/null }
        run_with_timeout 2 sleep 60
    " >/dev/null 2>&1
    elapsed=$((SECONDS - start))
    if (( elapsed < 15 )); then
        pass "deadline still bounds a hang with no timeout/gtimeout (${elapsed}s, not 60s)"
    else
        fail "no deadline without coreutils — every guard no-ops on a fresh Mac" "took ${elapsed}s"
    fi
}

test_git_and_apt_are_bounded() {
    # The curl-pipe check covers only the curl class. GIT_TERMINAL_PROMPT stops
    # a credential prompt but not a stalled TCP connection, and
    # DEBIAN_FRONTEND stops needrestart but not the dpkg lock — on a fresh box
    # with unattended-upgrades running at boot, apt blocks indefinitely.
    local missing=""
    for script in install.sh deploy.sh; do
        grep -q 'GIT_HTTP_LOW_SPEED_TIME' "$DOT_DIR/$script" || missing+="$script:git "
        grep -q 'APT_LOCK_TIMEOUT' "$DOT_DIR/$script" || missing+="$script:apt "
    done
    grep -q 'DPkg::Lock::Timeout' "$DOT_DIR/scripts/shared/helpers.sh" || missing+="helpers:dpkg-lock "

    # Per CALL SITE, not per file: one bounded apt call used to satisfy a bare
    # `grep -q`, while eight others waited on the dpkg lock forever. Every
    # apt/apt-get install|update must carry the lock bound.
    local unbounded
    unbounded=$(grep -nE '(^|[^-[:alnum:]])(sudo |\$SUDO )?apt(-get)? (install|update)' \
        "$DOT_DIR"/install.sh "$DOT_DIR"/deploy.sh "$DOT_DIR"/scripts/shared/helpers.sh 2>/dev/null \
        | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' \
        | grep -v 'APT_LOCK_OPT' | grep -v 'DPkg::Lock::Timeout' || true)
    [[ -n "$unbounded" ]] && missing+="unbounded-apt-call-sites "

    if [[ -z "$missing" ]]; then
        pass "every apt call site and git fetch carries a deadline"
    else
        fail "git/apt can still block indefinitely" "$missing
$unbounded"
    fi
}

test_timeout_fallback_covers_macos() {
    # macOS ships no coreutils `timeout`; PACKAGES_MACOS installs coreutils,
    # which provides `gtimeout`. run_with_timeout must try both, or every guard
    # here silently becomes a no-op on a Mac.
    local out
    out=$(helper_probe 'functions run_with_timeout' 2>&1)
    if [[ "$out" == *"gtimeout"* ]]; then
        pass "run_with_timeout falls back to gtimeout (macOS via coreutils)"
    else
        fail "run_with_timeout has no macOS fallback" "all deadlines no-op on a Mac"
    fi
}

test_no_unguarded_bare_sudo_v() {
    # deploy.sh:1274 aborted the whole run under set -euo pipefail on non-TTY.
    # Any bare `sudo -v` that is not inside a guard function is a regression.
    local hits
    hits=$(grep -n '^\s*sudo -v' "$DOT_DIR/deploy.sh" "$DOT_DIR/install.sh" 2>/dev/null || true)
    if [[ -z "$hits" ]]; then
        pass "no bare 'sudo -v' at statement level in either script"
    else
        fail "bare 'sudo -v' found — aborts non-TTY runs under set -e" "$hits"
    fi
}

test_noninteractive_env_hardening_present() {
    local missing=""
    for script in install.sh deploy.sh; do
        for var in GIT_TERMINAL_PROMPT DEBIAN_FRONTEND NEEDRESTART_MODE; do
            grep -q "export $var" "$DOT_DIR/$script" || missing+="$script:$var "
        done
    done
    if [[ -z "$missing" ]]; then
        pass "both scripts export the non-interactive environment hardening"
    else
        fail "missing non-interactive env hardening" "$missing"
    fi
}

test_menu_has_a_deadline() {
    local out
    out=$(helper_probe 'functions show_component_menu' 2>&1)
    if [[ "$out" == *"run_with_timeout"* && "$out" == *"DOTFILES_MENU_TIMEOUT"* ]]; then
        pass "component menu carries an idle deadline"
    else
        fail "component menu can wait forever on an unattended TTY" "the top-of-run prompt stall"
    fi
}

test_chsh_is_attended_only() {
    local out
    out=$(helper_probe 'functions set_zsh_default' 2>&1)
    if [[ "$out" == *"-t 0"* && "$out" == *"run_with_timeout"* ]]; then
        pass "chsh runs only attended and under a deadline"
    else
        fail "chsh can block on a PAM password prompt" "hangs mid-install where zsh is not the login shell"
    fi
}

# ─── Run ─────────────────────────────────────────────────────────────────────

require_timeout_cmd

echo "Stall canary — running the real code under hard deadlines"
echo ""
echo "0. The canary must be able to fail"
test_canary_detects_a_real_stall
echo ""
echo "1. Deadline helpers"
test_run_with_timeout_bounds_a_hang
test_run_with_timeout_zero_disables
test_fetch_carries_deadlines
test_claude_tools_fetch_is_bounded
test_source_build_is_bounded_and_visible
test_every_cargo_build_is_bounded
test_run_parallel_pid_capture_is_quoted
test_bounded_menu_does_not_abort_the_script
test_watchdog_child_keeps_the_terminal
test_retry_does_not_multiply_the_deadline
test_installer_fetches_are_checked_not_interpolated
test_parallel_group_is_bounded
test_no_untimed_curl_pipe_installers
test_git_and_apt_are_bounded
test_timeout_fallback_covers_macos
test_deadline_holds_without_coreutils
echo ""
echo "2. The real scripts, unattended"
test_help_is_instant
test_scripts_parse_without_prompting
test_no_unguarded_bare_sudo_v
test_noninteractive_env_hardening_present
test_menu_has_a_deadline
test_chsh_is_attended_only

echo ""
echo "─────────────────────────────────────────"
printf 'passed: %d   failed: %d\n' "$PASS" "$FAIL"
if (( FAIL > 0 )); then
    printf 'failures:\n'
    for f in "${FAILURES[@]}"; do printf '  - %s\n' "$f"; done
    exit 1
fi
exit 0
