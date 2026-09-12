#!/bin/bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCTOR="$REPO_ROOT/custom_bins/codex-install-doctor"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

[[ -x "$DOCTOR" ]] || fail "missing executable: $DOCTOR"

make_codex() {
    local destination="$1"
    local version="$2"
    local supports_agents="${3:-true}"
    mkdir -p "$(dirname "$destination")"
    cat > "$destination" <<EOF
#!/bin/bash
if [[ "\${1:-}" == "--version" ]]; then
    echo "codex-cli $version"
elif [[ "\${1:-}" == "agents" && "\${2:-}" == "--help" && "$supports_agents" == "true" ]]; then
    echo "Browse agent sessions"
else
    exit 2
fi
EOF
    chmod +x "$destination"
}

run_doctor() {
    local home_dir="$1"
    local codex_home="$2"
    local test_path="$3"
    local system_prefixes="${4:-/nonexistent}"
    set +e
    DOCTOR_OUTPUT="$(HOME="$home_dir" CODEX_HOME="$codex_home" PATH="$test_path" \
        CODEX_INSTALL_METHOD="${CODEX_INSTALL_METHOD:-homebrew}" \
        CODEX_REQUIRED_SUBCOMMANDS="${CODEX_REQUIRED_SUBCOMMANDS:-agents}" \
        CODEX_DOCTOR_SYSTEM_PREFIXES="$system_prefixes" "$DOCTOR" 2>&1)"
    DOCTOR_STATUS=$?
    set -e
}

empty_root="$TEST_ROOT/empty"
mkdir -p "$empty_root/home" "$empty_root/codex-home"
run_doctor "$empty_root/home" "$empty_root/codex-home" "/usr/bin:/bin"
[[ "$DOCTOR_STATUS" -eq 1 ]] || fail "no installation should exit 1, got $DOCTOR_STATUS"
[[ "$DOCTOR_OUTPUT" == *"No Codex installation found"* ]] || fail "missing no-install diagnostic"

brew_root="$TEST_ROOT/brew"
make_codex "$brew_root/prefix/Caskroom/codex/1.2.3/bin/codex" "1.2.3"
mkdir -p "$brew_root/prefix/bin" "$brew_root/home" "$brew_root/codex-home"
ln -s "$brew_root/prefix/Caskroom/codex/1.2.3/bin/codex" "$brew_root/prefix/bin/codex"
run_doctor "$brew_root/home" "$brew_root/codex-home" \
    "$brew_root/prefix/bin:$brew_root/prefix/bin:/usr/bin:/bin"
[[ "$DOCTOR_STATUS" -eq 0 ]] || fail "one Homebrew installation should exit 0, got $DOCTOR_STATUS"
[[ "$DOCTOR_OUTPUT" == *"1 distinct Codex installation"* ]] || fail "Homebrew copy was not deduplicated"
[[ "$DOCTOR_OUTPUT" == *"homebrew"* ]] || fail "Homebrew owner was not reported"

CODEX_INSTALL_METHOD=standalone run_doctor "$brew_root/home" "$brew_root/codex-home" \
    "$brew_root/prefix/bin:/usr/bin:/bin"
[[ "$DOCTOR_STATUS" -eq 3 ]] || fail "wrong configured owner should exit 3, got $DOCTOR_STATUS"
[[ "$DOCTOR_OUTPUT" == *"configured owner is standalone"* ]] || fail "owner mismatch was not reported"
unset CODEX_INSTALL_METHOD

system_brew_root="$TEST_ROOT/system-brew"
make_codex "$system_brew_root/prefix/Caskroom/codex/1.2.3/bin/codex" "1.2.3"
mkdir -p "$system_brew_root/prefix/bin" "$system_brew_root/home" "$system_brew_root/codex-home"
ln -s "$system_brew_root/prefix/Caskroom/codex/1.2.3/bin/codex" \
    "$system_brew_root/prefix/bin/codex"
run_doctor "$system_brew_root/home" "$system_brew_root/codex-home" "/usr/bin:/bin" \
    "$system_brew_root/prefix"
[[ "$DOCTOR_STATUS" -eq 0 ]] || fail "Homebrew outside PATH should exit 0, got $DOCTOR_STATUS"
[[ "$DOCTOR_OUTPUT" == *"homebrew"* ]] || fail "standard Homebrew prefix was not scanned"

bun_root="$TEST_ROOT/bun"
make_codex "$bun_root/home/.bun/install/global/node_modules/@openai/codex/bin/codex.js" "2.3.4"
mkdir -p "$bun_root/home/.bun/bin" "$bun_root/codex-home"
ln -s ../install/global/node_modules/@openai/codex/bin/codex.js "$bun_root/home/.bun/bin/codex"
run_doctor "$bun_root/home" "$bun_root/codex-home" "$bun_root/home/.bun/bin:/usr/bin:/bin"
[[ "$DOCTOR_STATUS" -eq 3 ]] || fail "unconfigured Bun installation should exit 3, got $DOCTOR_STATUS"
[[ "$DOCTOR_OUTPUT" == *"bun"* ]] || fail "Bun owner was not reported"

standalone_root="$TEST_ROOT/standalone"
standalone_home="$standalone_root/codex-home"
make_codex "$standalone_home/packages/standalone/releases/3.4.5/bin/codex" "3.4.5"
mkdir -p "$standalone_root/home/.local/bin"
ln -s releases/3.4.5 "$standalone_home/packages/standalone/current"
ln -s "$standalone_home/packages/standalone/current/bin/codex" "$standalone_root/home/.local/bin/codex"
CODEX_INSTALL_METHOD=standalone run_doctor "$standalone_root/home" "$standalone_home" \
    "$standalone_root/home/.local/bin:$standalone_root/home/.local/bin:/usr/bin:/bin"
[[ "$DOCTOR_STATUS" -eq 0 ]] || fail "one standalone installation should exit 0, got $DOCTOR_STATUS"
[[ "$DOCTOR_OUTPUT" == *"1 distinct Codex installation"* ]] || fail "standalone launcher and payload were not deduplicated"
[[ "$DOCTOR_OUTPUT" == *"standalone"* ]] || fail "standalone owner was not reported"
unset CODEX_INSTALL_METHOD

incapable_root="$TEST_ROOT/incapable"
make_codex "$incapable_root/prefix/Caskroom/codex/1.2.3/bin/codex" "1.2.3" false
mkdir -p "$incapable_root/prefix/bin" "$incapable_root/home" "$incapable_root/codex-home"
ln -s "$incapable_root/prefix/Caskroom/codex/1.2.3/bin/codex" "$incapable_root/prefix/bin/codex"
run_doctor "$incapable_root/home" "$incapable_root/codex-home" \
    "$incapable_root/prefix/bin:/usr/bin:/bin"
[[ "$DOCTOR_STATUS" -eq 4 ]] || fail "missing required capability should exit 4, got $DOCTOR_STATUS"
[[ "$DOCTOR_OUTPUT" == *"missing required subcommand: agents"* ]] || fail "missing capability was not reported"

duplicate_root="$TEST_ROOT/duplicate"
duplicate_home="$duplicate_root/home"
duplicate_codex_home="$duplicate_root/codex-home"
make_codex "$duplicate_root/prefix/Caskroom/codex/4.5.6/bin/codex" "4.5.6"
make_codex "$duplicate_codex_home/packages/standalone/releases/3.4.5/bin/codex" "3.4.5"
mkdir -p "$duplicate_root/prefix/bin" "$duplicate_home/.local/bin"
ln -s "$duplicate_root/prefix/Caskroom/codex/4.5.6/bin/codex" "$duplicate_root/prefix/bin/codex"
ln -s releases/3.4.5 "$duplicate_codex_home/packages/standalone/current"
ln -s "$duplicate_codex_home/packages/standalone/current/bin/codex" "$duplicate_home/.local/bin/codex"
run_doctor "$duplicate_home" "$duplicate_codex_home" \
    "$duplicate_root/prefix/bin:$duplicate_home/.local/bin:/usr/bin:/bin"
[[ "$DOCTOR_STATUS" -eq 2 ]] || fail "duplicate installations should exit 2, got $DOCTOR_STATUS"
[[ "$DOCTOR_OUTPUT" == *"2 distinct Codex installations"* ]] || fail "duplicate count was not reported"
[[ "$DOCTOR_OUTPUT" == *"homebrew"* && "$DOCTOR_OUTPUT" == *"standalone"* ]] || \
    fail "duplicate owners were not both reported"

echo "PASS: Codex installation doctor"
