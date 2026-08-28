#!/usr/bin/env bash
# shellcheck shell=bash
# The pin must not reach the child UNDER BASH either.
#
# deploy.sh writes a ~/.bashrc that sources config/aliases/*.sh, so claude()
# genuinely runs under bash on bash-default hosts — but every other suite here
# is zsh, so bash/zsh divergence in the wrapper is otherwise invisible.
#
# The specific divergence this guards: `local +x VAR` does NOT shadow a
# GLOBALLY EXPORTED variable under bash (measured — bash: child saw PIN=[1];
# zsh: PIN=[unset]). If someone "simplifies" the blanking on the launch line
# back to `local +x`, this test fails under bash while the zsh suite stays
# green.
#
# Run from the repo root: bash tests/test_task_list_pin_bash.sh
set -u
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root" || exit 1

scratch="$root/tmp/.pinbash-$$"
fakebin="$scratch/bin"
outfile="$scratch/out"
mkdir -p "$fakebin"
trap 'rm -rf "$scratch"' EXIT

# shellcheck disable=SC2016  # the ${...} must reach the fake binary unexpanded
{
  echo '#!/bin/sh'
  echo 'echo "LAUNCHED_WITH=[${CLAUDE_CODE_TASK_LIST_ID-unset}]"'
  echo 'echo "CHILD_PIN=[${CLAUDE_CODE_TASK_LIST_PIN-unset}]"'
} > "$fakebin/claude"
chmod +x "$fakebin/claude"
export PATH="$fakebin:$PATH"

activate_venv() { :; }
unset DOTFILES_TELEGRAM_BOT_SECRET 2>/dev/null || true
unset CLAUDE_CODE_TASK_LIST_ID 2>/dev/null || true
unset CLAUDE_CODE_TASK_LIST_PIN 2>/dev/null || true

# Do NOT pipe this: a pipeline runs `source` in a subshell and the wrapper is
# never defined in this shell, so `claude` would silently resolve to the fake
# binary and every assertion below would pass vacuously.
# shellcheck source=/dev/null
source config/aliases/claude.sh || { echo "FAIL: could not source claude.sh"; exit 1; }
activate_venv() { :; }

if ! declare -F claude >/dev/null; then
  echo "FAIL: claude() is not defined after sourcing — harness broken"
  exit 1
fi

pass=0; fail=0
refute() {  # refute <name> <forbidden-substring> <actual>
  if [[ "$3" == *"$2"* ]]; then echo "FAIL: $1 — [$2] should be absent from [$3]"; ((fail++))
  else echo "PASS: $1"; ((pass++)); fi
}
check() {  # check <name> <expected-substring> <actual>
  if [[ "$3" == *"$2"* ]]; then echo "PASS: $1"; ((pass++))
  else echo "FAIL: $1 — expected [$2] in [$3]"; ((fail++)); fi
}

# Globally exported pin + ID: the shape that leaked under bash.
export CLAUDE_CODE_TASK_LIST_PIN=1
export CLAUDE_CODE_TASK_LIST_ID="GLOBAL_PINNED"
claude >"$outfile" 2>&1
got=$(cat "$outfile")
refute "bash: globally-exported pin not propagated to child" "CHILD_PIN=[1]" "$got"
check "bash: globally-exported pin honored for this launch" "LAUNCHED_WITH=[GLOBAL_PINNED]" "$got"
check "bash: shell's pin survives the call" "1" "${CLAUDE_CODE_TASK_LIST_PIN}"
check "bash: shell's ID survives the call" "GLOBAL_PINNED" "${CLAUDE_CODE_TASK_LIST_ID}"
unset CLAUDE_CODE_TASK_LIST_PIN
unset CLAUDE_CODE_TASK_LIST_ID

# Unpinned: mints fresh and leaves nothing behind, under bash too.
claude >"$outfile" 2>&1
got=$(cat "$outfile")
check "bash: unpinned launch mints an ID" "_UTC_" "$got"
check "bash: nothing persists after launch" "unset" "[${CLAUDE_CODE_TASK_LIST_ID-unset}]"

echo "---"
echo "pass=$pass fail=$fail"
(( fail == 0 ))
