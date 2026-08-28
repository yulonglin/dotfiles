# shellcheck shell=bash
# Regression test: CLAUDE_CODE_TASK_LIST_ID is scoped to the launch.
#
# The claude() wrapper must (a) mint a fresh dir-named ID per launch, (b) ignore
# an inherited unpinned ID (a stale leak from an old shell or the tmux server
# env), (c) honor a pinned ID (claude-new/claude-with/claude-last), and
# (d) leave the shell's variable state exactly as it found it. Regression for
# the 2026-08 cross-repo task-list leak, where one exported ID followed the
# shell across `cd`s for days and unrelated repos shared a task list.
#
# Run from the repo root: zsh tests/test_claude_task_list_scope.zsh
set -u
root=${0:a:h:h}
cd "$root" || exit 1

# Fake `claude` binary on PATH: reports the task list ID it received.
# Repo-local scratch (not mktemp): sandboxed sessions can't write $TMPDIR.
scratch="$root/tmp/.tlid-test-$$"
fakebin="$scratch/bin"
mkdir -p "$fakebin"
trap 'rm -rf "$scratch"' EXIT
printf '%s\n' '#!/bin/sh' 'echo "LAUNCHED_WITH=[${CLAUDE_CODE_TASK_LIST_ID-unset}]"' > "$fakebin/claude"
chmod +x "$fakebin/claude"
export PATH="$fakebin:$PATH"

# Stubs for functions other alias files define; neutralise channel detection.
activate_venv() { :; }
unset DOTFILES_TELEGRAM_BOT_SECRET 2>/dev/null || true
unset CLAUDE_CODE_TASK_LIST_ID 2>/dev/null || true
unset CLAUDE_CODE_TASK_LIST_PIN 2>/dev/null || true

source config/aliases/claude.sh || { echo "FAIL: could not source claude.sh"; exit 1; }
activate_venv() { :; }  # re-assert in case the sourced file redefined it

expected_suffix="_UTC_$(basename "$root" | tr ' ' '_')"

pass=0; fail=0
check() {  # check <name> <expected-substring> <actual>
  if [[ "$3" == *"$2"* ]]; then echo "PASS: $1"; ((pass++)); else echo "FAIL: $1 — expected [$2] in [$3]"; ((fail++)); fi
}

# 1. Fresh launch: generates an ID from dir basename, restores to unset after.
out=$(claude 2>&1)
check "fresh launch mints dir-named ID" "$expected_suffix" "$out"
check "fresh launch restores unset" "unset" "[${CLAUDE_CODE_TASK_LIST_ID-unset}]"

# 2. Stale inherited (unpinned) ID: ignored for the launch, shell value untouched.
export CLAUDE_CODE_TASK_LIST_ID="STALE_FROM_OTHER_REPO"
out=$(claude 2>&1)
check "stale unpinned ID not used for launch" "$expected_suffix" "$out"
if [[ "$out" == *"STALE_FROM_OTHER_REPO"* ]]; then echo "FAIL: stale ID leaked into launch"; ((fail++)); else echo "PASS: stale ID absent from launch"; ((pass++)); fi
check "pre-existing shell value restored" "STALE_FROM_OTHER_REPO" "$CLAUDE_CODE_TASK_LIST_ID"
unset CLAUDE_CODE_TASK_LIST_ID

# 3. Pinned ID (claude-new/claude-with path): honored for the launch, nothing persists.
out=$(CLAUDE_CODE_TASK_LIST_ID="PINNED_LIST" CLAUDE_CODE_TASK_LIST_PIN=1 claude 2>&1)
check "pinned ID honored" "LAUNCHED_WITH=[PINNED_LIST]" "$out"
check "nothing persists after pinned launch" "unset" "[${CLAUDE_CODE_TASK_LIST_ID-unset}]"

# 4. claude-with end-to-end: uses the named list, leaves no state behind.
out=$(claude-with "MY_SHARED_LIST" 2>&1)
check "claude-with uses named list" "LAUNCHED_WITH=[MY_SHARED_LIST]" "$out"
check "claude-with leaves no state" "unset" "[${CLAUDE_CODE_TASK_LIST_ID-unset}]"

# 5. claude-last parses the pointer file and pins it for the launch.
tmpdir="$scratch/lastdir"
mkdir -p "$tmpdir"
( cd "$tmpdir" || exit 1
  echo "export CLAUDE_CODE_TASK_LIST_ID=SAVED_LIST" > .claude_task_list_id
  out=$(claude-last 2>&1)
  [[ "$out" == *"LAUNCHED_WITH=[SAVED_LIST]"* ]]
)
if [ $? -eq 0 ]; then echo "PASS: claude-last resumes saved list"; ((pass++)); else echo "FAIL: claude-last resumes saved list"; ((fail++)); fi

echo "---"
echo "pass=$pass fail=$fail"
(( fail == 0 ))
