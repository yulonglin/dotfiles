#!/usr/bin/env bash
# Single entry point for every test suite in this repo.
#
# The suites long predate this runner and were invoked by hand, which is how
# eight of them came to be failing on main at once with nobody noticing. The
# point of this script is to make "did I break something" a single command, and
# to give CI one thing to call.
#
# Discovery is by convention, so a new suite is picked up by naming alone:
#
#   tests/test_*.{sh,zsh}          repo-level shell suites
#   tests/test_*.py                repo-level pytest suites (run as one batch)
#   claude/hooks/test_*.sh         hook suites, colocated with the hooks
#   scripts/tests/test-*.sh        script suites
#
# Interpreters are resolved per suite rather than assumed. A suite whose
# interpreter is missing is reported SKIP, never silently dropped — and
# --strict turns those skips into failures, which is what CI runs so that a
# missing zsh degrades into a red build rather than into invisible coverage.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO" || exit 1

STRICT=0
VERBOSE=0
FILTER=""

usage() {
    cat <<'EOF'
Usage: tests/run-all.sh [options]

  -k <substr>   run only suites whose path contains <substr>
  -v            stream suite output even when the suite passes
  --strict      treat SKIP as failure (CI mode)
  -h            this help
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        -k) FILTER="${2:-}"; shift 2 ;;
        -v) VERBOSE=1; shift ;;
        --strict) STRICT=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

# Colour only when attached to a terminal, so CI logs stay readable.
if [ -t 1 ]; then
    R=$'\033[31m'; G=$'\033[32m'; Y=$'\033[33m'; B=$'\033[1m'; N=$'\033[0m'
else
    R=""; G=""; Y=""; B=""; N=""
fi

PASSED=(); FAILED=(); SKIPPED=()

# Resolve pytest once. The repo has no virtualenv and pytest is commonly a
# standalone binary rather than an importable module (python3 -m pytest then
# fails), so probe all three forms the suites are actually run under.
PYTEST_CMD=()
if python3 -m pytest --version >/dev/null 2>&1; then
    PYTEST_CMD=(python3 -m pytest)
elif command -v pytest >/dev/null 2>&1; then
    PYTEST_CMD=(pytest)
elif command -v uv >/dev/null 2>&1; then
    PYTEST_CMD=(uv run --no-project --with pytest python -m pytest)
fi

report() {
    local status="$1" name="$2" note="${3:-}"
    case "$status" in
        pass) PASSED+=("$name"); printf '%s  PASS%s  %s\n' "$G" "$N" "$name" ;;
        fail) FAILED+=("$name"); printf '%s  FAIL%s  %s%s\n' "$R" "$N" "$name" "${note:+ ($note)}" ;;
        skip) SKIPPED+=("$name"); printf '%s  SKIP%s  %s%s\n' "$Y" "$N" "$name" "${note:+ ($note)}" ;;
    esac
}

# Run one suite and fold its result into the tally. Output is buffered and
# replayed only on failure (or under -v): a green run should be a short list,
# not thousands of lines of per-assertion chatter.
run_suite() {
    local name="$1"; shift
    [ -n "$FILTER" ] && [[ "$name" != *"$FILTER"* ]] && return 0

    local out rc=0
    out="$("$@" 2>&1)" || rc=$?
    if [ "$rc" -eq 0 ]; then
        report pass "$name"
        [ "$VERBOSE" -eq 1 ] && printf '%s\n' "$out"
    else
        report fail "$name" "exit $rc"
        printf '%s\n' "$out" | sed 's/^/      | /'
    fi
    return 0
}

skip_suite() {
    local name="$1" why="$2"
    [ -n "$FILTER" ] && [[ "$name" != *"$FILTER"* ]] && return 0
    report skip "$name" "$why"
}

printf '%s== shell suites ==%s\n' "$B" "$N"

# `find` rather than a glob so a directory with no matches is simply empty
# instead of yielding the literal pattern.
while IFS= read -r suite; do
    case "$suite" in
        *.zsh)
            if command -v zsh >/dev/null 2>&1; then
                run_suite "$suite" zsh "$suite"
            else
                skip_suite "$suite" "zsh not installed"
            fi
            ;;
        *)
            run_suite "$suite" bash "$suite"
            ;;
    esac
done < <(
    {
        find tests -maxdepth 1 -name 'test_*.sh' -o -maxdepth 1 -name 'test_*.zsh'
        find claude/hooks -maxdepth 1 -name 'test_*.sh'
        find scripts/tests -maxdepth 1 -name 'test-*.sh'
    } 2>/dev/null | sort
)

printf '\n%s== pytest suites ==%s\n' "$B" "$N"

PY_SUITES=$(find tests -maxdepth 1 -name 'test_*.py' 2>/dev/null | sort)
if [ -z "$PY_SUITES" ]; then
    printf '  (none)\n'
elif [ ${#PYTEST_CMD[@]} -eq 0 ]; then
    while IFS= read -r suite; do
        skip_suite "$suite" "pytest unavailable"
    done <<<"$PY_SUITES"
else
    # One invocation for the whole batch: collection is the slow part, and the
    # suites share no state that would make batching change a result.
    run_suite "tests/*.py" "${PYTEST_CMD[@]}" -q tests/
fi

printf '\n%s== summary ==%s\n' "$B" "$N"
printf '  passed  %d\n' "${#PASSED[@]}"
printf '  failed  %d\n' "${#FAILED[@]}"
printf '  skipped %d\n' "${#SKIPPED[@]}"

if [ ${#FAILED[@]} -gt 0 ]; then
    printf '\n%sFailing suites:%s\n' "$R" "$N"
    printf '  %s\n' "${FAILED[@]}"
    exit 1
fi

if [ "$STRICT" -eq 1 ] && [ ${#SKIPPED[@]} -gt 0 ]; then
    printf '\n%s--strict: skipped suites are failures%s\n' "$R" "$N"
    printf '  %s\n' "${SKIPPED[@]}"
    exit 1
fi

printf '\n%sAll suites passed.%s\n' "$G" "$N"
