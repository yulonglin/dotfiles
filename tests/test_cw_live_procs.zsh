#!/usr/bin/env zsh
# Tests for _cw_live_procs and the cwrm guard that uses it.
#
# Removing a worktree does not kill processes running in it. In 2026-08 a vLLM
# health-check poller outlived its worktree by 16 days and held a Modal H100
# warm at $96/day because nothing looked. These tests pin the detection, and
# specifically that --force does NOT bypass it: --force is about gitignored
# artifacts you lose on purpose, orphaning a live process is a different and
# more expensive mistake.

emulate -L zsh
setopt no_unset pipefail

REPO_ROOT="${0:A:h:h}"
cd "$REPO_ROOT" || { echo "FAIL: cannot cd to repo root"; exit 1; }

source config/aliases/claude.sh || { echo "FAIL: could not source claude.sh"; exit 1; }

pass=0; fail=0
check() { if [[ "$3" == *"$2"* ]]; then echo "PASS: $1"; ((pass++))
  else echo "FAIL: $1 — expected [$2] in [$3]"; ((fail++)); fi }
refute() { if [[ "$3" == *"$2"* ]]; then echo "FAIL: $1 — [$2] should be absent from [$3]"; ((fail++))
  else echo "PASS: $1"; ((pass++)); fi }

if [[ ! -d /proc/1 ]] && ! command -v lsof >/dev/null 2>&1; then
  echo "SKIP: no /proc and no lsof — cannot read another process's cwd"
  exit 0
fi

TMP=$(mktemp -d)
mkdir -p "$TMP/inside/nested" "$TMP/elsewhere"
cleanup() {
  [[ -n "${here_pid:-}" ]] && kill "$here_pid" 2>/dev/null
  [[ -n "${nested_pid:-}" ]] && kill "$nested_pid" 2>/dev/null
  [[ -n "${outside_pid:-}" ]] && kill "$outside_pid" 2>/dev/null
  rm -rf "$TMP"
}
trap cleanup EXIT INT TERM

# A process sitting in the target directory.
( cd "$TMP/inside" && exec sleep 30 ) &
here_pid=$!
# One in a subdirectory of it.
( cd "$TMP/inside/nested" && exec sleep 30 ) &
nested_pid=$!
# And one outside, which must never be reported.
( cd "$TMP/elsewhere" && exec sleep 30 ) &
outside_pid=$!

# Give the forks a moment to land on their cwd before reading /proc.
sleep 1

found=$(_cw_live_procs "$TMP/inside")

check "finds a process whose cwd is the directory itself" "$here_pid" "$found"
check "finds a process in a subdirectory" "$nested_pid" "$found"
refute "does not report a process outside the directory" "$outside_pid" "$found"

empty=$(_cw_live_procs "$TMP/nonexistent-path")
if [[ -z "$empty" ]]; then
  echo "PASS: reports nothing for a path with no processes"; ((pass++))
else
  echo "FAIL: reports nothing for a path with no processes — got [$empty]"; ((fail++))
fi

# The output shape the callers parse: PID<TAB>command.
if [[ "$found" == *$'\t'* ]]; then
  echo "PASS: output is tab-separated pid and command"; ((pass++))
else
  echo "FAIL: output is tab-separated pid and command — got [$found]"; ((fail++))
fi

# cwrm must advertise the opt-out, and --force must not be it.
usage=$(cwrm 2>&1)
check "cwrm usage advertises --ignore-procs" "--ignore-procs" "$usage"

body=$(typeset -f cwrm)
check "cwrm consults _cw_live_procs" "_cw_live_procs" "$body"
refute "the process check is not gated on \$force" 'if $force; then
    local procs' "$body"

clean_body=$(typeset -f cwclean)
check "cwclean consults _cw_live_procs" "_cw_live_procs" "$clean_body"
check "cwclean reports a +procs worktree as kept" "has_procs" "$clean_body"

echo
echo "passed: $pass, failed: $fail"
[[ $fail -eq 0 ]]
