#!/bin/bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANAGER="$REPO_ROOT/custom_bins/codex-install-manager"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT
FAILURES=0

fail() {
    echo "FAIL: $*" >&2
    FAILURES=$((FAILURES + 1))
}

[[ -x "$MANAGER" ]] || fail "missing executable: $MANAGER"

cat > "$TEST_ROOT/doctor" <<'EOF'
#!/bin/bash
if [[ "${1:-}" == "--owner-only" ]]; then
    printf '%s\n' "${TEST_CODEX_OWNERS:-}"
    exit "${TEST_CODEX_OWNER_STATUS:-0}"
fi
exit "${TEST_CODEX_STATUS:-0}"
EOF
chmod +x "$TEST_ROOT/doctor"

run_manager() {
    set +e
    MANAGER_OUTPUT="$(
        HOME="$TEST_ROOT/home" \
        CODEX_HOME="$TEST_ROOT/codex-home" \
        CODEX_INSTALL_CONFIG=/nonexistent \
        CODEX_DOCTOR="$TEST_ROOT/doctor" \
        CODEX_INSTALL_METHOD="${CODEX_INSTALL_METHOD:-homebrew}" \
        CODEX_REQUIRED_SUBCOMMANDS=agents \
        CODEX_THREAD_ID="${TEST_ACTIVE_THREAD:-}" \
        TEST_CODEX_STATUS="${TEST_CODEX_STATUS:-0}" \
        TEST_CODEX_OWNER_STATUS="${TEST_CODEX_OWNER_STATUS:-0}" \
        TEST_CODEX_OWNERS="${TEST_CODEX_OWNERS:-}" \
        "$MANAGER" "$@" 2>&1
    )"
    MANAGER_STATUS=$?
    set -e
}

TEST_CODEX_STATUS=1 run_manager --ensure --dry-run
[[ "$MANAGER_STATUS" -eq 0 ]] || fail "dry-run Homebrew install failed: $MANAGER_OUTPUT"
[[ "$MANAGER_OUTPUT" == *"brew install --cask codex"* ]] || fail "Homebrew install was not planned"

TEST_CODEX_STATUS=3 TEST_CODEX_OWNERS=standalone run_manager --ensure --dry-run
[[ "$MANAGER_STATUS" -eq 0 ]] || fail "dry-run standalone-to-Homebrew switch failed: $MANAGER_OUTPUT"
[[ "$MANAGER_OUTPUT" == *"install configured homebrew Codex"* ]] || fail "configured owner was not installed first"
[[ "$MANAGER_OUTPUT" == *"remove standalone Codex"* ]] || fail "old standalone owner was not removed"

TEST_CODEX_STATUS=3 TEST_CODEX_OWNERS=standalone TEST_ACTIVE_THREAD=test-thread \
    run_manager --ensure --dry-run
[[ "$MANAGER_STATUS" -ne 0 ]] || fail "active Codex session should block owner switching"
[[ "$MANAGER_OUTPUT" == *"Exit Codex before switching"* ]] || fail "active-session remediation missing"
unset TEST_ACTIVE_THREAD

TEST_CODEX_STATUS=3 TEST_CODEX_OWNERS=standalone run_manager --update --dry-run
[[ "$MANAGER_STATUS" -eq 3 ]] || fail "scheduled update should fail on wrong owner"
[[ "$MANAGER_OUTPUT" == *"rerun install.sh"* ]] || fail "wrong-owner update remediation missing"
[[ "$MANAGER_OUTPUT" != *"remove standalone Codex"* ]] || fail "scheduled update attempted an owner switch"

TEST_CODEX_STATUS=4 TEST_CODEX_OWNERS=homebrew run_manager --ensure --dry-run
[[ "$MANAGER_STATUS" -eq 0 ]] || fail "capability repair dry-run failed: $MANAGER_OUTPUT"
[[ "$MANAGER_OUTPUT" == *"brew upgrade --cask codex"* ]] || fail "Homebrew capability repair was not planned"
[[ "$MANAGER_OUTPUT" == *"If Homebrew still lacks agents"* ]] || fail "standalone fallback instruction missing"

CODEX_INSTALL_METHOD=standalone TEST_CODEX_STATUS=0 TEST_CODEX_OWNERS=standalone \
    run_manager --update --dry-run
[[ "$MANAGER_STATUS" -eq 0 ]] || fail "standalone update dry-run failed: $MANAGER_OUTPUT"
[[ "$MANAGER_OUTPUT" == *"https://chatgpt.com/codex/install.sh"* ]] || fail "official standalone installer was not planned"

real_root="$TEST_ROOT/real-switch"
real_home="$real_root/home"
real_codex_home="$real_root/codex-home"
real_prefix="$real_root/prefix"
mkdir -p "$real_home/.local/bin" "$real_codex_home/packages/standalone/releases/0.9.0/bin" \
    "$real_prefix/bin" "$real_root/stubs"
cat > "$real_codex_home/packages/standalone/releases/0.9.0/bin/codex" <<'EOF'
#!/bin/bash
if [[ "${1:-}" == "--version" ]]; then echo "codex-cli 0.9.0"; exit 0; fi
if [[ "${1:-}" == "agents" && "${2:-}" == "--help" ]]; then exit 0; fi
exit 2
EOF
chmod +x "$real_codex_home/packages/standalone/releases/0.9.0/bin/codex"
ln -s releases/0.9.0 "$real_codex_home/packages/standalone/current"
ln -s "$real_codex_home/packages/standalone/current/bin/codex" "$real_home/.local/bin/codex"

cat > "$real_root/stubs/brew" <<'EOF'
#!/bin/bash
set -euo pipefail
prefix="$FIXTURE_ROOT/prefix"
case "${1:-}" in
    --prefix) echo "$prefix" ;;
    install)
        mkdir -p "$prefix/Caskroom/codex/1.0.0/bin" "$prefix/bin"
        cat > "$prefix/Caskroom/codex/1.0.0/bin/codex" <<'CODEX'
#!/bin/bash
if [[ "${1:-}" == "--version" ]]; then echo "codex-cli 1.0.0"; exit 0; fi
if [[ "${1:-}" == "agents" && "${2:-}" == "--help" ]]; then exit 0; fi
exit 2
CODEX
        chmod +x "$prefix/Caskroom/codex/1.0.0/bin/codex"
        ln -sf "$prefix/Caskroom/codex/1.0.0/bin/codex" "$prefix/bin/codex"
        ;;
    uninstall) rm -f "$prefix/bin/codex" ;;
    upgrade) ;;
esac
EOF
chmod +x "$real_root/stubs/brew"

HOME="$real_home" CODEX_HOME="$real_codex_home" CODEX_INSTALL_CONFIG=/nonexistent \
CODEX_INSTALL_METHOD=homebrew CODEX_REQUIRED_SUBCOMMANDS=agents CODEX_THREAD_ID='' \
CODEX_DOCTOR_SYSTEM_PREFIXES="$real_prefix" FIXTURE_ROOT="$real_root" \
PATH="$real_root/stubs:$real_home/.local/bin:$real_prefix/bin:/usr/bin:/bin" \
    "$MANAGER" --ensure >/dev/null

[[ ! -e "$real_codex_home/packages/standalone" ]] || fail "standalone payload survived Homebrew switch"
HOME="$real_home" CODEX_HOME="$real_codex_home" CODEX_INSTALL_CONFIG=/nonexistent \
CODEX_INSTALL_METHOD=homebrew CODEX_REQUIRED_SUBCOMMANDS=agents \
CODEX_DOCTOR_SYSTEM_PREFIXES="$real_prefix" \
PATH="$real_prefix/bin:/usr/bin:/bin" "$REPO_ROOT/custom_bins/codex-install-doctor" --quiet || \
    fail "Homebrew switch did not converge"

cat > "$real_root/stubs/curl" <<'EOF'
#!/bin/bash
set -euo pipefail
output=""
while [[ $# -gt 0 ]]; do
    if [[ "$1" == "-o" ]]; then output="$2"; shift 2; else shift; fi
done
cat > "$output" <<'INSTALLER'
#!/bin/sh
set -eu
release="$CODEX_HOME/packages/standalone/releases/2.0.0"
mkdir -p "$release/bin" "$HOME/.local/bin"
cat > "$release/bin/codex" <<'CODEX'
#!/bin/bash
if [[ "${1:-}" == "--version" ]]; then echo "codex-cli 2.0.0"; exit 0; fi
if [[ "${1:-}" == "agents" && "${2:-}" == "--help" ]]; then exit 0; fi
exit 2
CODEX
chmod +x "$release/bin/codex"
ln -sfn releases/2.0.0 "$CODEX_HOME/packages/standalone/current"
ln -sfn "$CODEX_HOME/packages/standalone/current/bin/codex" "$HOME/.local/bin/codex"
INSTALLER
EOF
chmod +x "$real_root/stubs/curl"

HOME="$real_home" CODEX_HOME="$real_codex_home" CODEX_INSTALL_CONFIG=/nonexistent \
CODEX_INSTALL_METHOD=standalone CODEX_REQUIRED_SUBCOMMANDS=agents CODEX_THREAD_ID='' \
CODEX_DOCTOR_SYSTEM_PREFIXES="$real_prefix" FIXTURE_ROOT="$real_root" \
PATH="$real_root/stubs:$real_prefix/bin:$real_home/.local/bin:/usr/bin:/bin" \
    "$MANAGER" --ensure >/dev/null

[[ ! -e "$real_prefix/bin/codex" ]] || fail "Homebrew launcher survived standalone switch"
HOME="$real_home" CODEX_HOME="$real_codex_home" CODEX_INSTALL_CONFIG=/nonexistent \
CODEX_INSTALL_METHOD=standalone CODEX_REQUIRED_SUBCOMMANDS=agents \
CODEX_DOCTOR_SYSTEM_PREFIXES="$real_prefix" \
PATH="$real_home/.local/bin:/usr/bin:/bin" "$REPO_ROOT/custom_bins/codex-install-doctor" --quiet || \
    fail "standalone switch did not converge"

((FAILURES == 0)) || exit 1
echo "PASS: Codex install manager"
