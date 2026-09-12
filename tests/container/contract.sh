#!/usr/bin/env bash
# shellcheck shell=bash
# The component contract, asserted against a real install.sh + deploy.sh run on
# a clean Ubuntu. Runs INSIDE the container built by tests/container/Dockerfile;
# drive it from the host with tests/test_installers_container.sh.
#
# The contract, in the README's own words: flags are ADDITIVE to the profile's
# defaults unless --minimal is used. Nothing here reads config.sh — every
# assertion reads the banner both scripts print before they do any work, which
# is the only statement of the resolved set a user ever sees.
#
# Deliberately NOT covered here, because a container cannot: macOS (a different
# code path in every platform branch), the menu drawing and being keyed (needs
# a pty nobody types at — tests/pty_drive.py in PR #134), and anything needing
# real credentials, a GUI or an App Store session.
set -uo pipefail

DOT_DIR=/home/tester/dotfiles
QUICK=false
[[ "${1:-}" == "--quick" ]] && QUICK=true

PASS=0
FAIL=0
declare -a FAILURES=()
pass() { PASS=$((PASS + 1)); printf '  \033[32mPASS\033[0m %s\n' "$1"; }
fail() {
    FAIL=$((FAIL + 1)); FAILURES+=("$1")
    printf '  \033[31mFAIL\033[0m %s\n' "$1"
    [[ -n "${2:-}" ]] && printf '        %s\n' "$2"
}

# Run one installer with a scratch HOME, capture combined output and exit code.
# Every run is --non-interactive: the menu is a separate contract with its own
# harness, and what this suite pins is what the scripts resolve, not how they ask.
LAST_OUT=""
LAST_RC=0
run_script() {
    local script="$1" home="$2"; shift 2
    mkdir -p "$home"
    LAST_OUT=$(cd "$DOT_DIR" && HOME="$home" timeout 900 zsh "./$script" --non-interactive "$@" 2>&1)
    LAST_RC=$?
}

# The banner line: "Components (N): a, b, c" or "Components: none".
banner() { printf '%s\n' "$LAST_OUT" | grep -m1 '^Components'; }
banner_count() {
    local b; b=$(banner)
    [[ "$b" == "Components: none" ]] && { echo 0; return; }
    printf '%s\n' "$b" | sed -n 's/^Components (\([0-9]*\)):.*/\1/p'
}
banner_has() { banner | grep -qE "[ :]${1}(,|$)"; }

echo "Installer component contract — clean Ubuntu container"
# shellcheck disable=SC1091  # /etc/os-release exists only inside the image
echo "$(. /etc/os-release && echo "$PRETTY_NAME"), $(uname -m), user $(id -un)"
echo ""

# ── 1. A fresh end-to-end run ────────────────────────────────────────────────
# The default profile, no flags: the "I cloned it and ran it" case. This is the
# leg that takes minutes; --quick skips it and runs only the contract legs.
echo "1. Fresh install.sh + deploy.sh, default profile"
if [[ "$QUICK" == "true" ]]; then
    echo "  SKIP (--quick)"
else
    run_script install.sh /home/tester
    install_banner=$(banner)
    if [[ $LAST_RC -eq 0 ]]; then
        pass "install.sh exits 0 on a clean machine"
    else
        fail "install.sh exited $LAST_RC" "$(printf '%s\n' "$LAST_OUT" | tail -15)"
    fi
    if [[ -n "$install_banner" ]]; then
        pass "install.sh prints its resolved set before doing work — $install_banner"
    else
        fail "install.sh printed no Components banner" "$(printf '%s\n' "$LAST_OUT" | head -15)"
    fi

    run_script deploy.sh /home/tester
    deploy_banner=$(banner)
    deploy_count=$(banner_count)
    if [[ $LAST_RC -eq 0 ]]; then
        pass "deploy.sh exits 0 after install.sh"
    else
        fail "deploy.sh exited $LAST_RC" "$(printf '%s\n' "$LAST_OUT" | tail -15)"
    fi
    if [[ -n "$deploy_banner" ]]; then
        pass "deploy.sh prints its resolved set — $deploy_banner"
    else
        fail "deploy.sh printed no Components banner" "$(printf '%s\n' "$LAST_OUT" | head -15)"
    fi
    # The completion line carries the count, so "complete!" can no longer mean
    # "completed having done nothing" — the failure mode this PR is named for.
    if printf '%s\n' "$LAST_OUT" | grep -q "Deployment complete! (${deploy_count} components)"; then
        pass "the completion line agrees with the banner (${deploy_count} components)"
    else
        fail "completion line does not carry the resolved count" \
             "$(printf '%s\n' "$LAST_OUT" | grep -c 'Deployment complete' ) 'Deployment complete' lines, none matching ${deploy_count}"
    fi
    # A component the standard profile deploys, verified on disk rather than in
    # the log: a banner that lies is exactly what a banner-only test cannot see.
    if [[ -L /home/tester/.zshrc || -f /home/tester/.zshrc ]]; then
        pass "deploy.sh actually placed ~/.zshrc"
    else
        fail "no ~/.zshrc after a deploy whose banner claims the shell component"
    fi

    # ── 2. Idempotency ───────────────────────────────────────────────────────
    echo ""
    echo "2. Re-run over the existing install"
    run_script install.sh /home/tester
    if [[ $LAST_RC -eq 0 && "$(banner)" == "$install_banner" ]]; then
        pass "install.sh re-runs clean and resolves identically"
    else
        fail "install.sh second run: rc=$LAST_RC, banner '$(banner)' vs '$install_banner'" \
             "$(printf '%s\n' "$LAST_OUT" | tail -10)"
    fi
    run_script deploy.sh /home/tester
    if [[ $LAST_RC -eq 0 && "$(banner)" == "$deploy_banner" ]]; then
        pass "deploy.sh re-runs clean and resolves identically"
    else
        fail "deploy.sh second run: rc=$LAST_RC, banner '$(banner)' vs '$deploy_banner'" \
             "$(printf '%s\n' "$LAST_OUT" | tail -10)"
    fi
fi

# ── 3. --minimal means nothing, and says so ──────────────────────────────────
# From here on every leg uses its own scratch HOME, so the cases cannot
# contaminate each other, and deploy.sh rather than install.sh, because deploy
# is seconds and install is minutes while the resolution logic is shared.
echo ""
echo "3. --minimal"
run_script deploy.sh /tmp/h-minimal --minimal
if [[ $LAST_RC -eq 0 ]]; then
    pass "--minimal exits 0 (an empty run asked for by name is legal)"
else
    fail "--minimal exited $LAST_RC" "$(printf '%s\n' "$LAST_OUT" | tail -10)"
fi
if [[ "$(banner)" == "Components: none" ]]; then
    pass "--minimal resolves to no components, and the banner says none"
else
    fail "--minimal banner is '$(banner)', expected 'Components: none'"
fi
if printf '%s\n' "$LAST_OUT" | grep -q 'Deployment complete! (0 components)'; then
    pass "--minimal reports 0 components rather than a bare 'complete!'"
else
    fail "--minimal completion line does not say 0 components" \
         "$(printf '%s\n' "$LAST_OUT" | grep 'complete' | head -3)"
fi

# ── 4. --no-<component> removes exactly one ──────────────────────────────────
echo ""
echo "4. --no-<component> subtracts one from the profile's set"
run_script deploy.sh /tmp/h-base
base_count=$(banner_count)
base_banner=$(banner)
run_script deploy.sh /tmp/h-novim --no-vim
novim_count=$(banner_count)
if [[ "$base_banner" == *vim* ]]; then
    pass "the default profile deploys vim, so --no-vim is a real subtraction"
else
    fail "the default profile does not deploy vim — this case tests nothing" "$base_banner"
fi
if ! banner_has vim; then
    pass "--no-vim drops vim from the resolved set"
else
    fail "--no-vim left vim in the set" "$(banner)"
fi
if [[ -n "$base_count" && "$novim_count" -eq $((base_count - 1)) ]]; then
    pass "--no-vim removes exactly one component ($base_count → $novim_count)"
else
    fail "--no-vim changed the count by more than one ($base_count → $novim_count)"
fi

# ── 5. A bare --<component> flag is ADDITIVE ─────────────────────────────────
# The README's rule, and the one nothing tested before: --<x> adds x to the
# profile's set, it does not reduce the set to x. Uses --bare, whose set is
# small enough that a reduction would be unmistakable.
echo ""
echo "5. --<component> is additive to the profile, not a replacement"
run_script deploy.sh /tmp/h-bare --bare
bare_count=$(banner_count)
bare_banner=$(banner)
run_script deploy.sh /tmp/h-bare-vim --bare --vim
barevim_count=$(banner_count)
if banner_has vim; then
    pass "--bare --vim adds vim"
else
    fail "--bare --vim did not add vim" "$(banner)"
fi
if [[ -n "$bare_count" && "$barevim_count" -eq $((bare_count + 1)) ]]; then
    pass "--bare --vim keeps the profile's set and adds one ($bare_count → $barevim_count)"
else
    fail "--<component> was not additive ($bare_count → $barevim_count)" \
         "profile set was: $bare_banner; with --vim: $(banner)"
fi

# ── 6. --minimal is the documented exception ─────────────────────────────────
echo ""
echo "6. --minimal --<component> yields exactly that one component"
run_script deploy.sh /tmp/h-min-vim --minimal --vim
if [[ "$(banner_count)" == "1" ]] && banner_has vim; then
    pass "--minimal --vim resolves to exactly vim"
else
    fail "--minimal --vim resolved to '$(banner)'"
fi

# ── 7. An empty resolved set is refused ──────────────────────────────────────
# --only <a macOS-only component> on Linux resolves to nothing. Before this
# change the run printed "complete!" having done nothing, which is how a broken
# menu hid for eleven weeks.
echo ""
echo "7. A run that would do nothing by accident is refused"
run_script deploy.sh /tmp/h-empty --only finicky
if [[ $LAST_RC -eq 1 ]]; then
    pass "--only finicky (macOS-only, on Linux) exits 1"
else
    fail "--only finicky exited $LAST_RC, expected 1" "$(printf '%s\n' "$LAST_OUT" | tail -8)"
fi
if printf '%s\n' "$LAST_OUT" | grep -q 'refusing to run an empty'; then
    pass "the refusal says what happened rather than reporting success"
else
    fail "no 'refusing to run an empty' message" "$(printf '%s\n' "$LAST_OUT" | tail -8)"
fi
if ! printf '%s\n' "$LAST_OUT" | grep -q 'Deployment complete'; then
    pass "a refused run never prints 'Deployment complete'"
else
    fail "a refused run still printed 'Deployment complete'"
fi

# ── 8. The menu is skipped without a terminal, silently and safely ───────────
echo ""
echo "8. No terminal, no menu, no stall"
run_script deploy.sh /tmp/h-notty --bare
if ! printf '%s\n' "$LAST_OUT" | grep -q 'Component menu unanswered'; then
    pass "no idle-deadline warning: the menu was skipped, not waited on"
else
    fail "the menu deadline fired even with no terminal and --non-interactive"
fi
if [[ "$(banner)" == "$bare_banner" ]]; then
    pass "a skipped menu keeps the profile's set unchanged"
else
    fail "a skipped menu changed the set" "$(banner) vs $bare_banner"
fi

echo ""
echo "─────────────────────────────────────────"
printf 'passed: %d   failed: %d\n' "$PASS" "$FAIL"
if (( FAIL > 0 )); then
    printf '\nfailures:\n'
    for f in "${FAILURES[@]}"; do printf '  - %s\n' "$f"; done
    exit 1
fi
