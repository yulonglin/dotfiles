#!/usr/bin/env bash
# shellcheck shell=bash
# ═══════════════════════════════════════════════════════════════════════════════
# One command that runs every test suite in this repo and says which ones pass.
# ═══════════════════════════════════════════════════════════════════════════════
# The suites here have only ever been invoked by hand, one at a time, from the
# "Run:" line in each file's own docstring. There was no way to ask the repo
# "what is green right now", so the answer drifted unobserved — CI's only
# always-on job has been red on main since 2026-09-01 and nobody noticed.
#
# Discovery is by naming convention, so a new suite is picked up by name alone:
#
#   tests/test_*.sh             repo-level bash suites
#   tests/test_*.zsh            repo-level zsh suites
#   tests/test_*.py             repo-level Python suites (pytest and unittest)
#   claude/hooks/test_*.sh      hook suites, colocated with the hooks
#   scripts/tests/test-*.sh     script suites (note the hyphen)
#
# SKIP IS NOT FAILURE, and keeping the two apart is the whole point. Several
# suites legitimately cannot run everywhere: the Playwright browser tests want
# Chromium, the plotting tests want matplotlib, the gateway smoke test wants a
# running loopback router, a launchd/systemd user session and a tailnet. A
# runner that painted those red would be as uninformative as the CI it is meant
# to make visible. Four signals separate them:
#
#   1. exit 77  — the suite decided for itself that it cannot run here. This is
#                 already the repo's convention (tests/test_cw_resume_env.zsh).
#   2. missing interpreter — no zsh, no Python, no pytest anywhere.
#   3. a Python suite whose every test skipped (pytest's own importorskip and
#      skipif markers, which most optional-dependency suites already carry).
#   4. SKIP_WHEN below — a named environment gate for a suite that predates the
#      exit-77 convention and would otherwise fail loudly off its own machine.
#
# --strict turns SKIP into failure. That is for a machine you have provisioned
# to run everything; it is deliberately NOT the default, because the default
# has to be honest on a laptop.
#
# Usage: tests/run-all.sh --help
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO" || exit 1

# Per-suite wall-clock deadline. The suites under test include installers whose
# entire subject is hanging, so an unbounded runner can itself hang.
TIMEOUT="${RUN_ALL_TIMEOUT:-600}"

STRICT=0
VERBOSE=0
LIST=0
FILTER=""

usage() {
    cat <<'EOF'
Usage: tests/run-all.sh [options]

Runs every discovered test suite and reports PASS / FAIL / SKIP per suite.

Options:
  -k <substr>   run only suites whose path contains <substr>
  -v            stream suite output even when the suite passes
  -l, --list    list the discovered suites and exit, running nothing
  --strict      treat SKIP as failure (for a fully provisioned machine)
  -h, --help    this help

Environment:
  RUN_ALL_TIMEOUT   per-suite deadline in seconds (default 600)

Exit codes:
  0  every suite that ran passed
  1  at least one suite failed (or skipped, under --strict)
  2  usage error

A suite reports that it cannot run here by exiting 77; that is a SKIP, not a
failure. Python suites additionally count as SKIP when every test in them
skipped, which is how the optional-dependency suites already declare
themselves.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        -k) FILTER="${2:-}"; [ -z "$FILTER" ] && { echo "-k needs a value" >&2; exit 2; }; shift 2 ;;
        -v) VERBOSE=1; shift ;;
        -l|--list) LIST=1; shift ;;
        --strict) STRICT=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

if [ -t 1 ]; then
    RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'; BLD=$'\033[1m'; DIM=$'\033[2m'; OFF=$'\033[0m'
else
    RED=""; GRN=""; YEL=""; BLD=""; DIM=""; OFF=""
fi

# ─── environment gates ───────────────────────────────────────────────────────
# Suites that need a resource this machine may not have, and that predate the
# exit-77 convention so cannot say so themselves. Each entry names a probe; a
# failing probe is a SKIP with that reason. Migrating a suite to its own
# exit 77 is strictly better — then it can gate per-leg — so this list should
# shrink, not grow.
skip_reason() {
    case "$1" in
        tests/test_model_router_gateway.sh)
            # Its first leg asks the OS service manager whether the router is
            # running, so a box with neither launchd nor systemd cannot answer
            # at all. (Its tailnet leg already skips itself, and the Bash
            # sandbox blocks loopback — run this one with the sandbox off, or a
            # healthy router reads as down.)
            if ! command -v launchctl >/dev/null 2>&1 && ! command -v systemctl >/dev/null 2>&1; then
                echo "no launchd or systemd service manager"
            fi
            ;;
    esac
}

PASSED=(); FAILED=(); SKIPPED=()

report() {
    local status="$1" name="$2" note="${3:-}"
    case "$status" in
        pass) PASSED+=("$name");  printf '  %sPASS%s  %s%s%s%s\n' "$GRN" "$OFF" "$name" "$DIM" "${note:+  $note}" "$OFF" ;;
        fail) FAILED+=("$name");  printf '  %sFAIL%s  %s%s\n'     "$RED" "$OFF" "$name" "${note:+  ($note)}" ;;
        skip) SKIPPED+=("$name"); printf '  %sSKIP%s  %s%s\n'     "$YEL" "$OFF" "$name" "${note:+  ($note)}" ;;
    esac
}

selected() {
    [ -z "$FILTER" ] && return 0
    case "$1" in *"$FILTER"*) return 0 ;; *) return 1 ;; esac
}

# Run one command as a suite and fold the result into the tally. Output is
# buffered and replayed only on failure (or under -v): a green run should be a
# readable list, not thousands of lines of per-assertion chatter.
#
# Every suite gets stdin from /dev/null. That is load-bearing twice over: the
# discovery loop is draining a pipe on fd 0, so a suite that reads stdin
# swallows the rest of the suite list and the run ends early with a green
# summary (claude/hooks/test_hook_features.sh does exactly this); and the
# suites are meant to run unattended, so anything that would prompt must see
# EOF rather than hang until the deadline.
run_cmd() {
    local name="$1"; shift
    local out rc=0 started elapsed
    started=$SECONDS
    if command -v timeout >/dev/null 2>&1; then
        out="$(timeout --foreground "$TIMEOUT" "$@" 2>&1 </dev/null)" || rc=$?
    else
        out="$("$@" 2>&1 </dev/null)" || rc=$?
    fi
    elapsed=$((SECONDS - started))

    case "$rc" in
        0)   report pass "$name" "${elapsed}s"
             [ "$VERBOSE" -eq 1 ] && printf '%s\n' "$out" | sed 's/^/        /' ;;
        77)  report skip "$name" "$(printf '%s' "$out" | grep -i -m1 'skip' | sed 's/^ *//' || true)" ;;
        124) report fail "$name" "timed out after ${TIMEOUT}s"
             printf '%s\n' "$out" | tail -20 | sed 's/^/        | /' ;;
        *)   report fail "$name" "exit $rc, ${elapsed}s"
             printf '%s\n' "$out" | sed 's/^/        | /' ;;
    esac
    return 0
}

# ─── discovery ───────────────────────────────────────────────────────────────
# `find` rather than a glob, so a directory with no matches yields nothing
# instead of the literal pattern.
shell_suites() {
    {
        find tests -maxdepth 1 \( -name 'test_*.sh' -o -name 'test_*.zsh' \) -type f
        find claude/hooks -maxdepth 1 -name 'test_*.sh' -type f
        find scripts/tests -maxdepth 1 -name 'test-*.sh' -type f
    } 2>/dev/null | LC_ALL=C sort
}

python_suites() {
    find tests -maxdepth 1 -name 'test_*.py' -type f 2>/dev/null | LC_ALL=C sort
}

if [ "$LIST" -eq 1 ]; then
    { shell_suites; python_suites; } | while IFS= read -r s; do
        selected "$s" && printf '%s\n' "$s"
    done
    exit 0
fi

# ─── how to run a Python suite ───────────────────────────────────────────────
# There is no virtualenv in this repo and no pytest on the system interpreter,
# so uv is the normal path. Probe all three forms the suites are documented
# under; pytest also collects the plain unittest.TestCase suites, so one
# resolved command covers both styles.
SYS_PY="$(command -v python3 || true)"
PYTEST=()
if python3 -c 'import pytest' >/dev/null 2>&1; then
    PYTEST=(python3 -m pytest)
elif command -v pytest >/dev/null 2>&1; then
    PYTEST=(pytest)
elif command -v uv >/dev/null 2>&1; then
    # Pin uv to the system interpreter rather than letting it fetch its own.
    # Several suites reach their optional dependencies through whatever
    # `python3` resolves to — test_md2artifact_*.py probe /usr/bin/python3 for
    # markdown-it-py by name — so an unpinned `uv run` lands on a freshly
    # downloaded interpreter that carries none of them, and turns "the
    # dependency is installed on this machine" into a spurious FAIL.
    if [ -n "$SYS_PY" ]; then
        PYTEST=(uv run --quiet --no-project --python "$SYS_PY" --with pytest python -m pytest)
    else
        PYTEST=(uv run --quiet --no-project --with pytest python -m pytest)
    fi
fi

# Colour is decided by OUR stdout, not pytest's: suite output is captured into a
# variable (never a terminal), so pytest would otherwise strip colour even when
# the runner is being watched — and an ambient FORCE_COLOR would smear escape
# codes through a redirected log.
if [ -t 1 ]; then PYTEST_COLOR=--color=yes; else PYTEST_COLOR=--color=no; fi

# pytest's own exit codes and summary line, translated into our three states.
# A file whose every test skipped exits 0 with a summary that mentions no
# passes — that is the optional-dependency case (matplotlib, Playwright,
# markdown-it-py), and calling it PASS would overstate what was checked.
run_pytest_suite() {
    local name="$1" out rc=0 started elapsed summary
    started=$SECONDS
    if command -v timeout >/dev/null 2>&1; then
        out="$(timeout --foreground "$TIMEOUT" "${PYTEST[@]}" -q -rs -p no:cacheprovider "$PYTEST_COLOR" "$name" 2>&1 </dev/null)" || rc=$?
    else
        out="$("${PYTEST[@]}" -q -rs -p no:cacheprovider "$PYTEST_COLOR" "$name" 2>&1 </dev/null)" || rc=$?
    fi
    elapsed=$((SECONDS - started))
    summary="$(printf '%s\n' "$out" | grep -E '^[0-9]+ (passed|skipped|failed)|passed|skipped' | tail -1)"
    # -rs prints one "SKIPPED [n] file:line: reason" line per skip. The first
    # reason is what a reader wants ("matplotlib not installed"), not the bare
    # count, so lift it when the whole suite skipped.
    reason="$(printf '%s\n' "$out" | sed -n 's/^SKIPPED \[[0-9]*\] [^ ]*: //p' | head -1)"

    if [ "$rc" -eq 5 ] && grep -q '^if __name__ == "__main__"' "$name"; then
        # Not every tests/*.py is a pytest module. A few are standalone scripts
        # that own their own assertions and exit codes — the PTY suites, which
        # need a real terminal that no collector can hand them. pytest collects
        # nothing from those (exit 5), which is the signal to run the file the
        # way its own docstring says to. Only rc 5 falls through here, so a
        # suite pytest CAN collect is never quietly run some other way.
        run_cmd "$name" "${SYS_PY:-python3}" "$name"
    elif [ "$rc" -eq 5 ]; then
        report skip "$name" "${reason:-no tests collected}"
    elif [ "$rc" -eq 0 ]; then
        case "$summary" in
            *passed*) report pass "$name" "${elapsed}s  ${summary% in *}" ;;
            *skipped*) report skip "$name" "${summary% in *}${reason:+ — $reason}" ;;
            *) report pass "$name" "${elapsed}s" ;;
        esac
        [ "$VERBOSE" -eq 1 ] && printf '%s\n' "$out" | sed 's/^/        /'
    elif [ "$rc" -eq 124 ]; then
        report fail "$name" "timed out after ${TIMEOUT}s"
        printf '%s\n' "$out" | tail -20 | sed 's/^/        | /'
    else
        report fail "$name" "exit $rc, ${elapsed}s  ${summary% in *}"
        printf '%s\n' "$out" | tail -40 | sed 's/^/        | /'
    fi
    return 0
}

# ─── run ─────────────────────────────────────────────────────────────────────
printf '%s== shell suites ==%s\n' "$BLD" "$OFF"
while IFS= read -r suite; do
    selected "$suite" || continue
    gate="$(skip_reason "$suite")"
    if [ -n "$gate" ]; then
        report skip "$suite" "$gate"
        continue
    fi
    case "$suite" in
        *.zsh)
            if command -v zsh >/dev/null 2>&1; then
                run_cmd "$suite" zsh "$suite"
            else
                report skip "$suite" "zsh not installed"
            fi
            ;;
        *) run_cmd "$suite" bash "$suite" ;;
    esac
done < <(shell_suites)

printf '\n%s== python suites ==%s\n' "$BLD" "$OFF"
if [ ${#PYTEST[@]} -eq 0 ]; then
    while IFS= read -r suite; do
        selected "$suite" && report skip "$suite" "no pytest and no uv"
    done < <(python_suites)
else
    while IFS= read -r suite; do
        selected "$suite" || continue
        run_pytest_suite "$suite"
    done < <(python_suites)
fi

# ─── summary ─────────────────────────────────────────────────────────────────
printf '\n%s== summary ==%s\n' "$BLD" "$OFF"
printf '  %spassed%s   %d\n' "$GRN" "$OFF" "${#PASSED[@]}"
printf '  %sfailed%s   %d\n' "$RED" "$OFF" "${#FAILED[@]}"
printf '  %sskipped%s  %d\n' "$YEL" "$OFF" "${#SKIPPED[@]}"

if [ "${#FAILED[@]}" -gt 0 ]; then
    printf '\n%sFailing suites:%s\n' "$RED" "$OFF"
    printf '  %s\n' "${FAILED[@]}"
fi

if [ "${#FAILED[@]}" -gt 0 ]; then
    exit 1
fi

if [ "$STRICT" -eq 1 ] && [ "${#SKIPPED[@]}" -gt 0 ]; then
    printf '\n%s--strict: a skipped suite counts as a failure%s\n' "$RED" "$OFF"
    printf '  %s\n' "${SKIPPED[@]}"
    exit 1
fi

printf '\n%sEvery suite that ran passed.%s\n' "$GRN" "$OFF"
