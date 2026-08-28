# shellcheck shell=bash
# The claude() wrapper must NOT invent a task-list ID.
#
# Claude Code already gives every session its own list when
# CLAUDE_CODE_TASK_LIST_ID is unset — measured 2026-08-28 in ~/.claude/tasks/:
# 683 `session-<id>` lists it created itself vs 11 `<ts>_UTC_<dir>` from ~2
# months of this wrapper auto-generating. The auto-generated ID duplicated that
# isolation and cost a leak no wrapper can close: the ID must be exported into
# the claude process for Claude Code to read it, and every session that process
# spawns (the `claude agents` view included) inherits its environment.
#
# So the contract is now narrow:
#   - bare `claude` leaves the variable exactly as it found it, including unset
#   - `-t <name>` sets one for that launch only
#   - every inherited ID is dropped; nothing legitimate arrives that way
#   - nothing persists in the shell afterwards, on any path
#
# CRITICAL TEST-DESIGN NOTE — do not "tidy" this into command substitution.
# Assertions about SHELL STATE must call claude() in the CURRENT shell and
# redirect output to a file. `out=$(claude)` runs the wrapper in a subshell
# where its export cannot reach the test shell, so those assertions pass
# whether or not the code is correct. An earlier revision did exactly that and
# scored 10/10 with the entire mechanism deleted.
#
# Run from the repo root: zsh tests/test_claude_task_list_scope.zsh
set -u
root=${0:a:h:h}
cd "$root" || exit 1

scratch="$root/tmp/.tlid-test-$$"
fakebin="$scratch/bin"
outfile="$scratch/out"
mkdir -p "$fakebin"
trap 'rm -rf "$scratch"' EXIT

{
  echo '#!/bin/sh'
  echo 'echo "LAUNCHED_WITH=[${CLAUDE_CODE_TASK_LIST_ID-unset}]"'
  echo 'echo "CHILD_PIN=[${CLAUDE_CODE_TASK_LIST_PIN-unset}]"'
  echo 'exit ${FAKE_CLAUDE_RC:-0}'
} > "$fakebin/claude"
chmod +x "$fakebin/claude"
export PATH="$fakebin:$PATH"

activate_venv() { :; }
unset DOTFILES_TELEGRAM_BOT_SECRET 2>/dev/null || true
unset CLAUDE_CODE_TASK_LIST_ID 2>/dev/null || true

source config/aliases/claude.sh || { echo "FAIL: could not source claude.sh"; exit 1; }
activate_venv() { :; }

pass=0; fail=0
check() { if [[ "$3" == *"$2"* ]]; then echo "PASS: $1"; ((pass++))
  else echo "FAIL: $1 — expected [$2] in [$3]"; ((fail++)); fi }
refute() { if [[ "$3" == *"$2"* ]]; then echo "FAIL: $1 — [$2] should be absent from [$3]"; ((fail++))
  else echo "PASS: $1"; ((pass++)); fi }
run_claude() { claude "$@" >"$outfile" 2>&1; }
launched() { cat "$outfile"; }

# 1. Bare launch invents nothing — Claude Code assigns its own per-session list.
run_claude
check "bare launch leaves the ID unset for the child" "LAUNCHED_WITH=[unset]" "$(launched)"
refute "bare launch mints no dir-named ID" "_UTC_" "$(launched)"
check "bare launch leaves the shell unset" "unset" "[${CLAUDE_CODE_TASK_LIST_ID-unset}]"

# 2. An UNPINNED inherited ID is residue and must be dropped, not honored.
#    `source ~/.zshrc` cannot unset what an older wrapper exported, so a shell
#    that ran the pre-fix version still carries its ID indefinitely. Honoring
#    it is how the original cross-repo leak survived a re-source.
export CLAUDE_CODE_TASK_LIST_ID="STALE_RESIDUE"
run_claude
check "unpinned inherited ID dropped for the child" "LAUNCHED_WITH=[unset]" "$(launched)"
refute "stale residue never reaches the child" "STALE_RESIDUE" "$(launched)"
check "shell's own value left untouched" "STALE_RESIDUE" "${CLAUDE_CODE_TASK_LIST_ID-unset}"
unset CLAUDE_CODE_TASK_LIST_ID

# 2b. There is no pin any more: an inherited ID is dropped even if something
#     still sets the old marker, because nothing legitimate passes an ID in.
export CLAUDE_CODE_TASK_LIST_ID="SHARED_ON_PURPOSE"
export CLAUDE_CODE_TASK_LIST_PIN=1
run_claude
check "inherited ID dropped even with the legacy pin set" "LAUNCHED_WITH=[unset]" "$(launched)"
unset CLAUDE_CODE_TASK_LIST_ID CLAUDE_CODE_TASK_LIST_PIN

# 3. -t names a list for this launch only, and leaves nothing behind.
run_claude -t mytask
check "-t names the list" "_UTC_mytask" "$(launched)"
check "-t leaves the shell unset" "unset" "[${CLAUDE_CODE_TASK_LIST_ID-unset}]"

# 4. -t overrides an inherited ID, and restores it afterwards rather than
#    clobbering it — the binding is function-local.
export CLAUDE_CODE_TASK_LIST_ID="SOME_LIST"
run_claude -t override
check "-t beats an inherited ID" "_UTC_override" "$(launched)"
refute "-t does not pass the inherited ID" "SOME_LIST" "$(launched)"
check "-t restores the inherited ID after" "SOME_LIST" "${CLAUDE_CODE_TASK_LIST_ID-unset}"
unset CLAUDE_CODE_TASK_LIST_ID

# 5. Exit status is propagated, not swallowed.
FAKE_CLAUDE_RC=7 claude >"$outfile" 2>&1
rc=$?
if [[ "$rc" == 7 ]]; then echo "PASS: exit status propagated"; ((pass++))
else echo "FAIL: exit status propagated — expected 7, got $rc"; ((fail++)); fi

# 6. The removed helpers must stay removed: each was a way to set the ID, and
#    together they were the last surface from which the shared-list bug could
#    be reintroduced. Failing here means someone restored one.
for fn in claude-new claude-last claude-with claude-tasks-list; do
  if typeset -f "$fn" >/dev/null 2>&1; then
    echo "FAIL: $fn is defined again — it was deliberately removed"; ((fail++))
  else
    echo "PASS: $fn stays removed"; ((pass++))
  fi
done

echo "---"
echo "pass=$pass fail=$fail"
(( fail == 0 ))
