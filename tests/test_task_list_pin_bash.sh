#!/usr/bin/env bash
# shellcheck shell=bash
# The task-list contract must hold UNDER BASH too.
#
# deploy.sh writes a ~/.bashrc that sources config/aliases/*.sh, so claude()
# genuinely runs under bash on bash-default hosts — but every other suite here
# is zsh, so bash/zsh divergence in the wrapper is otherwise invisible. That
# blind spot already cost one real bug: `local +x` does not shadow a globally
# exported variable under bash, so a previous version leaked the pin to the
# child in bash while the zsh suite stayed green.
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
} > "$fakebin/claude"
chmod +x "$fakebin/claude"
export PATH="$fakebin:$PATH"

activate_venv() { :; }
unset DOTFILES_TELEGRAM_BOT_SECRET 2>/dev/null || true
unset CLAUDE_CODE_TASK_LIST_ID 2>/dev/null || true

# Do NOT pipe this: a pipeline runs `source` in a subshell, so the wrapper is
# never defined here, `claude` silently resolves to the fake binary, and every
# assertion below passes vacuously. A reviewer hit exactly that.
# shellcheck source=/dev/null
source config/aliases/claude.sh || { echo "FAIL: could not source claude.sh"; exit 1; }
activate_venv() { :; }

if ! declare -F claude >/dev/null; then
  echo "FAIL: claude() is not defined after sourcing — harness broken"
  exit 1
fi

pass=0; fail=0
check() { if [[ "$3" == *"$2"* ]]; then echo "PASS: $1"; ((pass++))
  else echo "FAIL: $1 — expected [$2] in [$3]"; ((fail++)); fi }
refute() { if [[ "$3" == *"$2"* ]]; then echo "FAIL: $1 — [$2] should be absent from [$3]"; ((fail++))
  else echo "PASS: $1"; ((pass++)); fi }

# 1. Bare launch invents nothing, under bash.
claude >"$outfile" 2>&1
got=$(cat "$outfile")
check "bash: bare launch leaves the ID unset for the child" "LAUNCHED_WITH=[unset]" "$got"
refute "bash: bare launch mints no dir-named ID" "_UTC_" "$got"
check "bash: nothing persists after launch" "unset" "[${CLAUDE_CODE_TASK_LIST_ID-unset}]"

# 2. A GLOBALLY EXPORTED, UNPINNED ID is residue and must be dropped. This is
#    the exact shape that reappeared after a `source ~/.zshrc` — sourcing
#    cannot unset what an older wrapper exported. It is also the shape where
#    bash and zsh diverged before (`local +x` does not shadow a global export
#    under bash), which is why the wrapper uses `env -u` here.
export CLAUDE_CODE_TASK_LIST_ID="GLOBAL_RESIDUE"
claude >"$outfile" 2>&1
got=$(cat "$outfile")
check "bash: unpinned global ID dropped for the child" "LAUNCHED_WITH=[unset]" "$got"
refute "bash: residue never reaches the child" "GLOBAL_RESIDUE" "$got"
check "bash: shell's ID survives the call" "GLOBAL_RESIDUE" "${CLAUDE_CODE_TASK_LIST_ID}"

# 2b. The pin mechanism is gone: an inherited ID is dropped under bash even if
#     something still sets the old marker. Nothing legitimate passes an ID in.
export CLAUDE_CODE_TASK_LIST_PIN=1
claude >"$outfile" 2>&1
got=$(cat "$outfile")
check "bash: inherited ID dropped despite the legacy pin" "LAUNCHED_WITH=[unset]" "$got"
unset CLAUDE_CODE_TASK_LIST_PIN

# 3. -t overrides a globally exported ID for the launch, then restores it.
claude -t bashtask >"$outfile" 2>&1
got=$(cat "$outfile")
check "bash: -t names the list" "_UTC_bashtask" "$got"
refute "bash: -t does not pass the global ID" "GLOBAL_RESIDUE" "$got"
check "bash: -t restores the global ID after" "GLOBAL_RESIDUE" "${CLAUDE_CODE_TASK_LIST_ID}"
unset CLAUDE_CODE_TASK_LIST_ID

echo "---"
echo "pass=$pass fail=$fail"
(( fail == 0 ))
