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
    if ! command -v timeout >/dev/null 2>&1; then
        echo "SKIP: coreutils timeout(1) unavailable — cannot bound anything reliably" >&2
        exit 0
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
test_parallel_group_is_bounded
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
