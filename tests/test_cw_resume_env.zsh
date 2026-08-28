# shellcheck shell=bash
# `cw <existing-worktree>` must launch through the claude() wrapper with the
# task-list environment blanked.
#
# tmux runs a bare command string under a NON-interactive shell, which sources
# no aliases — so `claude` there is the raw binary, bypassing the wrapper and
# its task-list scoping. If the tmux SERVER was started from a contaminated
# shell, that raw child inherits the stale ID and unrelated repos share a list
# again. This test starts an isolated tmux server whose environment carries a
# stale ID, resumes a worktree through cw, and asserts the launched process
# did NOT inherit it.
#
# Run from the repo root: zsh tests/test_cw_resume_env.zsh
set -u
root=${0:a:h:h}
cd "$root" || exit 1

if ! command -v tmux >/dev/null 2>&1; then echo "SKIP: tmux not available"; exit 77; fi

scratch="$root/tmp/.cw-test-$$"
fakebin="$scratch/bin"
result="$scratch/result"
mkdir -p "$fakebin"
# Isolated tmux server: never touch the user's sessions.
sock="$scratch/sock"
cleanup() { tmux -S "$sock" kill-server 2>/dev/null; rm -rf "$scratch"; }
trap cleanup EXIT

# Fake `claude` records the task-list env it was launched with, then exits.
{
  echo '#!/bin/sh'
  echo "printf 'ID=[%s]\\nPIN=[%s]\\n' \"\${CLAUDE_CODE_TASK_LIST_ID-unset}\" \"\${CLAUDE_CODE_TASK_LIST_PIN-unset}\" > $result"
} > "$fakebin/claude"
chmod +x "$fakebin/claude"

# An interactive-shell rc that defines the wrapper, so `zsh -ic` finds it.
zdot="$scratch/zdot"
mkdir -p "$zdot"
{
  echo "export PATH=$fakebin:\$PATH"
  echo 'activate_venv() { :; }'
  echo 'unset DOTFILES_TELEGRAM_BOT_SECRET'
  echo "source $root/config/aliases/claude.sh"
  echo 'activate_venv() { :; }'
} > "$zdot/.zshrc"

# A worktree directory for cw to find.
wt="$root/.claude/worktrees/__cwtest__"
mkdir -p "$wt"
cleanup_wt() { rmdir "$wt" 2>/dev/null; }

# The tmux SERVER inherits the environment of whichever shell starts it, and
# `-e` on new-session does NOT override PATH for the session's initial command
# (measured: the real `claude` ran instead of the fake). So the fake must be on
# PATH here, before the server exists.
export PATH="$fakebin:$PATH"

# Start the isolated server carrying STALE residue, as a pre-fix shell would.
tmux -S "$sock" new-session -d -s bootstrap -e "CLAUDE_CODE_TASK_LIST_ID=STALE_SERVER_ID" \
  -e "ZDOTDIR=$zdot" "sleep 30" 2>/dev/null
tmux -S "$sock" set-environment -g CLAUDE_CODE_TASK_LIST_ID STALE_SERVER_ID 2>/dev/null
tmux -S "$sock" set-environment -g ZDOTDIR "$zdot" 2>/dev/null

# Build the same invocation _cw_launch does, against the isolated server.
inner='claude; exec $SHELL'
if [[ "${CW_TEST_MUTATE:-}" == 1 ]]; then
  # Mutation mode: the pre-fix shape — bare command string, no env blanking.
  # Proves this test can actually fail. Must NOT be the default.
  tmux -S "$sock" new-session -d -s worktree-__cwtest__ -c "$wt" \
    -e "ZDOTDIR=$zdot" "$inner"
else
  shell_cmd="zsh -ic $(printf '%q' "$inner")"
  tmux -S "$sock" new-session -d -s worktree-__cwtest__ -c "$wt" \
    -e "CLAUDE_CODE_TASK_LIST_ID=" -e "CLAUDE_CODE_TASK_LIST_PIN=" \
    -e "ZDOTDIR=$zdot" "$shell_cmd"
fi

# Wait for the fake claude to record what it saw.
for _ in {1..40}; do [[ -s "$result" ]] && break; sleep 0.25; done
cleanup_wt

pass=0; fail=0
if [[ ! -s "$result" ]]; then
  echo "FAIL: launched process never ran — harness broken"
  exit 1
fi
got=$(cat "$result")

if [[ "$got" == *"STALE_SERVER_ID"* ]]; then
  echo "FAIL: cw resume inherited the stale tmux server ID — $got"; ((fail++))
else
  echo "PASS: cw resume did not inherit the stale server ID"; ((pass++))
fi

# It must still have gone through the wrapper, which mints
# <timestamp>_UTC_<dir>_<pid>-<random>. The raw binary would have received
# whatever the tmux env held (here: empty), never a minted ID. The directory
# component is not asserted: the wrapper auto-cds to the git root first, so a
# scratch directory under an existing repo reports that repo's basename.
if printf '%s\n' "$got" | grep -Eq '^ID=\[[0-9]{8}_[0-9]{6}_UTC_.+_[0-9]+-[0-9]+\]$'; then
  echo "PASS: cw resume ran through the claude() wrapper"; ((pass++))
else
  echo "FAIL: cw resume bypassed the wrapper (no minted ID) — $got"; ((fail++))
fi

echo "---"
echo "pass=$pass fail=$fail"
(( fail == 0 ))
