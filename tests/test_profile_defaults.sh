#!/usr/bin/env bash
# shellcheck shell=bash
# Pins what each profile resolves to, so a default flip cannot silently change
# a machine's component set. The fixtures in tests/golden/ were captured BEFORE
# the standard-default flip, which is what makes the devbox check meaningful:
# devbox must reproduce the old full `personal` set byte for byte.
#
# Fixtures are Linux-resolved (config.sh applies platform overrides at the end),
# so the byte-comparisons run on Linux only; the invariants below run anywhere.
#
# Usage: tests/test_profile_defaults.sh
set -uo pipefail

DOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GOLDEN="$DOT_DIR/tests/golden"
DUMP="$DOT_DIR/tests/dump_components.zsh"

PASS=0
FAIL=0
declare -a FAILURES=()
pass() { PASS=$((PASS + 1)); printf '  \033[32mPASS\033[0m %s\n' "$1"; }
fail() {
    FAIL=$((FAIL + 1)); FAILURES+=("$1")
    printf '  \033[31mFAIL\033[0m %s\n' "$1"
    [[ -n "${2:-}" ]] && printf '%s\n' "$2" | head -12
}

dump() { zsh "$DUMP" "$1" "$DOT_DIR"; }
enabled_count() { dump "$1" | grep -c '=true'; }
is_on() { dump "$1" | grep -qx "$2=true"; }

is_linux() { [[ "$(uname -s)" == "Linux" ]]; }

# ─── 1. Byte-for-byte fixtures (Linux) ───────────────────────────────────────

test_fixtures() {
    if ! is_linux; then
        echo "  SKIP fixture comparison (fixtures are Linux-resolved)"
        return
    fi
    for profile in personal devbox standard agent bare server cloud; do
        local fixture="$GOLDEN/profile-${profile}-linux.txt"
        # devbox and personal share one fixture: devbox must equal the old full set.
        [[ "$profile" == "devbox" ]] && fixture="$GOLDEN/profile-personal-linux.txt"
        if [[ ! -f "$fixture" ]]; then
            fail "no fixture for profile '$profile'" "expected $fixture"
            continue
        fi
        local diff_out
        if diff_out=$(diff "$fixture" <(dump "$profile") 2>&1); then
            pass "profile '$profile' matches its pinned component set"
        else
            fail "profile '$profile' drifted from its pinned set" "$diff_out"
        fi
    done
}

# ─── 2. Invariants that must hold on any platform ────────────────────────────

test_default_is_standard_not_full() {
    # The flip itself: a bare invocation must NOT be the full set.
    local std full
    std=$(enabled_count standard)
    full=$(enabled_count devbox)
    if (( std < full )); then
        pass "default 'standard' ($std enabled) is smaller than 'devbox' ($full)"
    else
        fail "default profile is not narrower than devbox" "standard=$std devbox=$full"
    fi
}

test_ladder_is_ordered() {
    # bare ⊂ standard ⊂ agent ⊂ devbox, by size at least.
    local bare std agent full
    bare=$(enabled_count bare); std=$(enabled_count standard)
    agent=$(enabled_count agent); full=$(enabled_count devbox)
    if (( bare < std && std <= agent && agent < full )); then
        pass "profile ladder is ordered: bare=$bare < standard=$std <= agent=$agent < devbox=$full"
    else
        fail "profile ladder is not ordered" "bare=$bare standard=$std agent=$agent devbox=$full"
    fi
}

test_defenses_are_never_opt_in() {
    # A defense you must remember to enable is not a defense. Every profile that
    # deploys any config at all must carry the secret-scan hook and the
    # package-manager quarantine.
    for profile in standard agent devbox; do
        if is_on "$profile" DEPLOY_GIT_HOOKS && is_on "$profile" DEPLOY_PKG_CONFIGS; then
            pass "profile '$profile' keeps git-hooks + pkg-configs enabled"
        else
            fail "profile '$profile' makes a security defense opt-in" \
                 "git-hooks and pkg-configs must be on"
        fi
    done
}

test_no_scheduled_jobs_in_ephemeral_profiles() {
    # Nothing on a throwaway box should install launchd/cron jobs.
    local scheduled=(DEPLOY_CLEANUP DEPLOY_CLAUDE_CLEANUP DEPLOY_AI_UPDATE
                     DEPLOY_BREW_UPDATE DEPLOY_USAGE_PING DEPLOY_TMUX_RESUME
                     DEPLOY_MCP_SYNC DEPLOY_DEP_AUDIT DEPLOY_STALE_CLAIMS
                     DEPLOY_SECRETS)
    for profile in standard agent bare; do
        local bad=""
        for var in "${scheduled[@]}"; do
            is_on "$profile" "$var" && bad+="$var "
        done
        if [[ -z "$bad" ]]; then
            pass "profile '$profile' schedules no background jobs"
        else
            fail "profile '$profile' schedules background jobs" "$bad"
        fi
    done
}

test_agent_can_actually_code() {
    # The profile exists to run Claude Code with per-project secrets.
    local need=(INSTALL_AI_TOOLS DEPLOY_CLAUDE DEPLOY_CODEX DEPLOY_TMUX
                DEPLOY_GIT_CONFIG DEPLOY_SECRETS_ENV DEPLOY_BWS)
    local missing=""
    for var in "${need[@]}"; do
        is_on agent "$var" || missing+="$var "
    done
    if [[ -z "$missing" ]]; then
        pass "profile 'agent' carries what coding on a throwaway box needs"
    else
        fail "profile 'agent' is missing coding essentials" "$missing"
    fi
}

test_bare_installs_no_ai_tools() {
    if ! is_on bare INSTALL_AI_TOOLS && ! is_on bare DEPLOY_CLAUDE; then
        pass "profile 'bare' installs no AI tooling"
    else
        fail "profile 'bare' pulls in AI tooling" "it is the no-coding profile"
    fi
}

test_unknown_profile_falls_back_loudly() {
    local out
    out=$(zsh -c "
        DOT_DIR='$DOT_DIR'; PROFILE=not-a-profile
        source '$DOT_DIR/config.sh'
    " 2>&1 >/dev/null)
    if [[ "$out" == *"Unknown profile"* ]]; then
        pass "an unknown profile warns instead of silently doing something"
    else
        fail "unknown profile is silent" "$out"
    fi
}

# ─── Run ─────────────────────────────────────────────────────────────────────

echo "Profile defaults — pinned component sets and invariants"
echo ""
echo "1. Pinned fixtures"
test_fixtures
echo ""
echo "2. Invariants"
test_default_is_standard_not_full
test_ladder_is_ordered
test_defenses_are_never_opt_in
test_no_scheduled_jobs_in_ephemeral_profiles
test_agent_can_actually_code
test_bare_installs_no_ai_tools
test_unknown_profile_falls_back_loudly

echo ""
echo "─────────────────────────────────────────"
printf 'passed: %d   failed: %d\n' "$PASS" "$FAIL"
if (( FAIL > 0 )); then
    printf 'failures:\n'
    for f in "${FAILURES[@]}"; do printf '  - %s\n' "$f"; done
    exit 1
fi
exit 0
