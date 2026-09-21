#!/usr/bin/env zsh
# Pins the caffeinate-ssh deploy component.
#
# The failure this guards against is silent: if the registry entry and the
# deploy.sh branch disagree about the component name, DEPLOY_CAFFEINATE_SSH is
# never set, the branch never fires, and deploy reports success having installed
# nothing — the same shape as the openrouter-drift units that sat uninstalled
# for a month (docs/deploy-components.md § Extending).
set -euo pipefail

REPO_ROOT="${0:A:h:h}"
DOT_DIR="$REPO_ROOT"
export DOT_DIR

source "$REPO_ROOT/config.sh"

fail() { print -u2 "FAIL: $1"; exit 1 }

# --- the registry entry produces the variable deploy.sh actually reads --------
[[ -n "${DEPLOY_CAFFEINATE_SSH+x}" ]] || \
    fail "DEPLOY_CAFFEINATE_SSH is unset — the registry name and deploy.sh disagree"

# Assert the registry's own default field, not the live variable: sourcing
# config.sh applies a profile (standard, here) that sets every component false,
# so the runtime value says nothing about how the component is declared.
registry_default=""
for entry in "${DEPLOY_REGISTRY[@]}"; do
    [[ "${entry%%|*}" == "caffeinate-ssh" ]] || continue
    rest="${entry#*|}"; rest="${rest#*|}"; rest="${rest#*|}"
    registry_default="${rest%%|*}"
done
[[ -n "$registry_default" ]] || fail "caffeinate-ssh is not in DEPLOY_REGISTRY"
[[ "$registry_default" == "true" ]] || \
    fail "expected caffeinate-ssh to be declared on-by-default, got '$registry_default'"

grep -q 'DEPLOY_CAFFEINATE_SSH' "$REPO_ROOT/deploy.sh" || \
    fail "deploy.sh never reads DEPLOY_CAFFEINATE_SSH"

# --- the script the branch points at exists and is executable ----------------
setup="$REPO_ROOT/scripts/power/setup_caffeinate_ssh.sh"
[[ -f "$setup" ]] || fail "missing $setup"
[[ -x "$setup" ]] || fail "$setup is not executable; queue_scheduled_job would run a non-executable"

grep -q 'scripts/power/setup_caffeinate_ssh.sh' "$REPO_ROOT/deploy.sh" || \
    fail "deploy.sh does not queue the setup script"

# --- battery behaviour is the whole point, so pin the flag -------------------
# `caffeinate -s` is AC-only by construction (man caffeinate). `-i` is not, and
# swapping it would hold the laptop awake on battery and flatten it.
grep -qE '<string>-s</string>' "$setup" || \
    fail "setup script does not pass -s; battery would no longer sleep"

grep -qE '<string>-i</string>' "$setup" && \
    fail "setup script passes -i, which holds the machine awake on battery too"

# --- opting out must unload, not merely skip ---------------------------------
grep -q 'setup_caffeinate_ssh.sh" --uninstall' "$REPO_ROOT/deploy.sh" || \
    fail "--no-caffeinate-ssh does not unload the agent, leaving the Mac awake forever"

grep -q 'uninstall' "$setup" || fail "setup script has no --uninstall path"

# --- syntax -------------------------------------------------------------------
zsh -n "$setup" || fail "$setup has a syntax error"

print "PASS: caffeinate-ssh component registers, queues, and stays AC-only"
