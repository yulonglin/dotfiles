#!/bin/bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT
FAILURES=0

fail() {
    echo "FAIL: $*" >&2
    FAILURES=$((FAILURES + 1))
}

cat > "$TEST_ROOT/manager" <<'EOF'
#!/bin/bash
printf '%s|%s|%s\n' "$*" "${CODEX_INSTALL_METHOD:-}" "${CODEX_REQUIRED_SUBCOMMANDS:-}" > "$TRACE_PATH"
exit "${MANAGER_EXIT:-0}"
EOF
chmod +x "$TEST_ROOT/manager"

run_helper() {
    local manager_exit="$1"
    set +e
    HELPER_OUTPUT="$(
        DOT_DIR="$REPO_ROOT" \
        HELPERS_PATH="$REPO_ROOT/scripts/shared/helpers.sh" \
        CODEX_INSTALL_MANAGER="$TEST_ROOT/manager" \
        TRACE_PATH="$TEST_ROOT/helper-trace" \
        MANAGER_EXIT="$manager_exit" \
        CODEX_INSTALL_METHOD=homebrew \
        CODEX_REQUIRED_SUBCOMMANDS=agents \
        zsh -c '
            PLATFORM=linux
            source "$HELPERS_PATH"
            log_warning() { print -r -- "$*" >&2; }
            install_codex_cli
        ' 2>&1
    )"
    HELPER_STATUS=$?
    set -e
}

run_helper 0
[[ "$HELPER_STATUS" -eq 0 ]] || fail "install helper should propagate manager success: $HELPER_OUTPUT"
[[ "$(cat "$TEST_ROOT/helper-trace")" == "--ensure|homebrew|agents" ]] || \
    fail "install helper did not pass configured owner and capability"

run_helper 4
[[ "$HELPER_STATUS" -eq 4 ]] || fail "install helper should propagate manager failure: $HELPER_OUTPUT"

mkdir -p "$TEST_ROOT/home"
run_updater() {
    local manager_exit="$1"
    set +e
    UPDATER_OUTPUT="$(
        HOME="$TEST_ROOT/home" \
        CODEX_INSTALL_MANAGER="$TEST_ROOT/manager" \
        TRACE_PATH="$TEST_ROOT/updater-trace" \
        MANAGER_EXIT="$manager_exit" \
        PATH="/usr/bin:/bin" \
        "$REPO_ROOT/custom_bins/update-ai-tools" --dry-run 2>&1
    )"
    UPDATER_STATUS=$?
    set -e
}

run_updater 0
[[ "$UPDATER_STATUS" -eq 0 ]] || fail "updater should propagate manager success: $UPDATER_OUTPUT"
[[ "$(cat "$TEST_ROOT/updater-trace")" == "--update --dry-run||" ]] || \
    fail "updater did not request non-switching dry-run update"

run_updater 3
[[ "$UPDATER_STATUS" -eq 3 ]] || fail "updater should propagate ownership mismatch"

((FAILURES == 0)) || exit 1
echo "PASS: Codex install and update entrypoints"
