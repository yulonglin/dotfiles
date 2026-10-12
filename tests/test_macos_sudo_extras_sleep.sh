#!/usr/bin/env bash
# Pins the AC sleep-timer logic in scripts/macos_sudo_extras.sh.
#
# Two things can go wrong silently here. The parser can pick the Battery value
# instead of the AC one — `pmset -g custom` prints both profiles with identically
# named keys — which would report a machine as already-configured when it is not.
# And the comparison can downgrade deliberate tuning: `sleep 0` means never, so a
# naive `current < want` test would treat never-sleep as "too low" and cut it to
# 30 minutes on a machine someone had pinned awake on purpose.
#
# The script itself needs root, so this exercises the parse and the decision
# against fixtures rather than running it.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/macos_sudo_extras.sh"
fails=0

fail() { echo "FAIL: $1" >&2; fails=$((fails + 1)); }
ok() { echo "  ok   $1"; }

[[ -f "$SCRIPT" ]] || { fail "missing $SCRIPT"; exit 1; }

# The parser, lifted verbatim from the script so drift breaks this test.
parse_ac_sleep() {
    awk '/AC Power/{f=1} f && $1=="sleep"{print $2; exit}'
}

grep -q '/AC Power/{f=1} f && \$1=="sleep"{print \$2; exit}' "$SCRIPT" \
    || fail "the awk in the script no longer matches the one this test pins"

# --- AC is picked, not Battery, even when Battery is listed first -------------
fixture_both() {
    cat <<'EOF'
Battery Power:
 Sleep On Power Button 1
 displaysleep         1
 sleep                1
AC Power:
 Sleep On Power Button 1
 displaysleep         1
 sleep                30
EOF
}

got=$(fixture_both | parse_ac_sleep)
[[ "$got" == "30" ]] && ok "picks the AC value (30), not the Battery value (1)" \
    || fail "expected AC sleep 30, got '$got'"

# "Sleep On Power Button" must not be mistaken for the sleep key.
got=$(printf 'AC Power:\n Sleep On Power Button 1\n sleep                45\n' | parse_ac_sleep)
[[ "$got" == "45" ]] && ok "ignores 'Sleep On Power Button'" \
    || fail "expected 45, got '$got'"

# --- the decision, mirroring the script --------------------------------------
decide() {
    local current="$1" want=30
    if [[ -z "$current" ]]; then echo "leave-unreadable"; return; fi
    if [[ "$current" == "0" ]]; then echo "leave-never"; return; fi
    if (( current >= want )); then echo "leave-already"; else echo "raise"; fi
}

[[ "$(decide 0)" == "leave-never" ]] && ok "sleep 0 (never) is preserved, not downgraded" \
    || fail "sleep 0 must be left alone, got $(decide 0)"

[[ "$(decide 1)" == "raise" ]] && ok "sleep 1 is raised" \
    || fail "sleep 1 must be raised, got $(decide 1)"

[[ "$(decide 30)" == "leave-already" ]] && ok "sleep 30 is already fine" \
    || fail "sleep 30 must be left, got $(decide 30)"

[[ "$(decide 60)" == "leave-already" ]] && ok "sleep 60 is not lowered to 30" \
    || fail "sleep 60 must be left, got $(decide 60)"

[[ "$(decide '')" == "leave-unreadable" ]] && ok "an unreadable value changes nothing" \
    || fail "empty must be left, got $(decide '')"

# --- mosh firewall rule resolves a prefix rather than hardcoding one ----------
grep -q '/opt/homebrew/bin/mosh-server /usr/local/bin/mosh-server' "$SCRIPT" \
    && ok "mosh-server path is resolved across Homebrew prefixes" \
    || fail "mosh-server firewall rule does not cover both Homebrew prefixes"

grep -q -- '--unblockapp' "$SCRIPT" && ok "firewall rule unblocks, not just adds" \
    || fail "--add without --unblockapp leaves mosh-server blocked"

if (( fails > 0 )); then
    echo "FAILED: $fails check(s)" >&2
    exit 1
fi
echo "PASS: AC sleep parse/decision and the mosh firewall rule hold"
