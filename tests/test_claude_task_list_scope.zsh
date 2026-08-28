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
# CRITICAL TEST-DESIGN NOTE — do not "tidy" this back into command substitution.
# Every assertion about SHELL STATE must call claude() in the CURRENT shell and
# redirect output to a file. Writing `out=$(claude)` puts the wrapper in a
# subshell, where its `export` cannot reach the test shell at all — so the
# state assertions pass whether or not the restore logic exists. An earlier
# revision of this file did exactly that and scored 10/10 with the entire
# restore block deleted. Mutation-check any change here: delete the restore
# block in claude() and confirm this test FAILS.
#
# Run from the repo root: zsh tests/test_claude_task_list_scope.zsh
set -u
root=${0:a:h:h}
cd "$root" || exit 1

# Repo-local scratch (not mktemp): sandboxed sessions can't write $TMPDIR.
scratch="$root/tmp/.tlid-test-$$"
fakebin="$scratch/bin"
outfile="$scratch/out"
mkdir -p "$fakebin"
trap 'rm -rf "$scratch"' EXIT

# Fake `claude` on PATH: reports the task-list vars it received, and exits with
# the code named by FAKE_CLAUDE_RC so exit-status passthrough is testable.
{
  echo '#!/bin/sh'
  echo 'echo "LAUNCHED_WITH=[${CLAUDE_CODE_TASK_LIST_ID-unset}]"'
  echo 'echo "CHILD_PIN=[${CLAUDE_CODE_TASK_LIST_PIN-unset}]"'
  echo 'exit ${FAKE_CLAUDE_RC:-0}'
} > "$fakebin/claude"
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
  if [[ "$3" == *"$2"* ]]; then echo "PASS: $1"; ((pass++))
  else echo "FAIL: $1 — expected [$2] in [$3]"; ((fail++)); fi
}
refute() {  # refute <name> <forbidden-substring> <actual>
  if [[ "$3" == *"$2"* ]]; then echo "FAIL: $1 — [$2] should be absent from [$3]"; ((fail++))
  else echo "PASS: $1"; ((pass++)); fi
}
# Run claude() IN THIS SHELL (never a subshell) so the state assertions are real.
run_claude() { claude "$@" >"$outfile" 2>&1; }
launched() { cat "$outfile"; }

# 1. Fresh launch: mints a dir-named ID for the child, restores to unset after.
run_claude
check "fresh launch mints dir-named ID" "$expected_suffix" "$(launched)"
check "fresh launch restores unset" "unset" "[${CLAUDE_CODE_TASK_LIST_ID-unset}]"

# 2. Stale inherited (unpinned) ID: ignored for the launch, shell value restored.
export CLAUDE_CODE_TASK_LIST_ID="STALE_FROM_OTHER_REPO"
run_claude
check "stale unpinned ID not used for launch" "$expected_suffix" "$(launched)"
refute "stale ID absent from launch" "STALE_FROM_OTHER_REPO" "$(launched)"
check "pre-existing shell value restored" "STALE_FROM_OTHER_REPO" "${CLAUDE_CODE_TASK_LIST_ID-unset}"
unset CLAUDE_CODE_TASK_LIST_ID

# 3. Pinned ID: honored for the launch, nothing persists in the shell.
CLAUDE_CODE_TASK_LIST_ID="PINNED_LIST" CLAUDE_CODE_TASK_LIST_PIN=1 run_claude
check "pinned ID honored" "LAUNCHED_WITH=[PINNED_LIST]" "$(launched)"
check "nothing persists after pinned launch" "unset" "[${CLAUDE_CODE_TASK_LIST_ID-unset}]"

# 4. The pin is consumed, not propagated: the child must not inherit permission
#    to reuse this ID for its own nested launches, forever.
CLAUDE_CODE_TASK_LIST_ID="PINNED_LIST" CLAUDE_CODE_TASK_LIST_PIN=1 run_claude
check "pin not propagated to child" "CHILD_PIN=[unset]" "$(launched)"

# 5. -t overrides even a pin, and names the list.
CLAUDE_CODE_TASK_LIST_ID="PINNED_LIST" CLAUDE_CODE_TASK_LIST_PIN=1 run_claude -t mytask
check "-t names the list" "_UTC_mytask" "$(launched)"
refute "-t beats an active pin" "PINNED_LIST" "$(launched)"

# 6. claude-spawn's contract: ID set-but-EMPTY forces a fresh list even with a
#    pin present (custom_bins/claude-spawn passes CLAUDE_CODE_TASK_LIST_ID=).
CLAUDE_CODE_TASK_LIST_ID="" CLAUDE_CODE_TASK_LIST_PIN=1 run_claude
check "empty pinned ID still mints fresh" "$expected_suffix" "$(launched)"

# 7. Two launches in the same second must not collide (parallel spawned agents).
run_claude; first=$(grep LAUNCHED_WITH "$outfile")
run_claude; second=$(grep LAUNCHED_WITH "$outfile")
if [[ "$first" == "$second" ]]; then
  echo "FAIL: consecutive launches share an ID — $first"; ((fail++))
else echo "PASS: consecutive launches get distinct IDs"; ((pass++)); fi

# 8. claude's exit status is propagated, not swallowed by the restore logic.
FAKE_CLAUDE_RC=7 claude >"$outfile" 2>&1
rc=$?
if [[ "$rc" == 7 ]]; then echo "PASS: exit status propagated"; ((pass++))
else echo "FAIL: exit status propagated — expected 7, got $rc"; ((fail++)); fi

# 9. claude-with end-to-end: uses the named list, leaves no state behind.
claude-with "MY_SHARED_LIST" >"$outfile" 2>&1
check "claude-with uses named list" "LAUNCHED_WITH=[MY_SHARED_LIST]" "$(launched)"
check "claude-with leaves no state" "unset" "[${CLAUDE_CODE_TASK_LIST_ID-unset}]"

# 10. claude-last parses its pointer file and pins it for the launch.
tmpdir="$scratch/lastdir"
mkdir -p "$tmpdir"
pushd "$tmpdir" >/dev/null || exit 1
echo "export CLAUDE_CODE_TASK_LIST_ID=SAVED_LIST" > .claude_task_list_id
claude-last >"$outfile" 2>&1
popd >/dev/null || exit 1
check "claude-last resumes saved list" "LAUNCHED_WITH=[SAVED_LIST]" "$(launched)"
check "claude-last leaves no state" "unset" "[${CLAUDE_CODE_TASK_LIST_ID-unset}]"

echo "---"
echo "pass=$pass fail=$fail"
(( fail == 0 ))
