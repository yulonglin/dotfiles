#!/usr/bin/env bash
# Tests for block_destructive_git.sh.
#
# Contract: exit 2 with a reason on stderr for each forbidden form; exit 0
# and silence for every legitimate command. The negatives matter more than
# the positives — a naive substring matcher passes all the blocks and fails
# every one of these.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="$DIR/block_destructive_git.sh"
PASS=0
FAIL=0

# bash_json <command> — value via argv, never interpolated into the program.
bash_json() {
    python3 -c "
import json, sys
print(json.dumps({'tool_name': 'Bash', 'tool_input': {'command': sys.argv[1]}}))
" "$1"
}

run() {
    local desc="$1" cmd="$2" expect="$3"
    local out err rc=0
    local errfile="$TMP/stderr.$$"

    out=$(bash_json "$cmd" | bash "$HOOK" 2>"$errfile") || rc=$?
    err=$(cat "$errfile")

    local got=allow
    [ "$rc" -eq 2 ] && got=block

    if [ "$rc" -ne 0 ] && [ "$rc" -ne 2 ]; then
        FAIL=$((FAIL + 1))
        printf 'FAIL: %s (exit %d — must be 0 or 2)\n' "$desc" "$rc"
        return
    fi

    if [ "$got" != "$expect" ]; then
        FAIL=$((FAIL + 1))
        printf 'FAIL: %s (expected %s, got %s) [%s]\n' "$desc" "$expect" "$got" "$cmd"
        return
    fi

    if [ "$expect" = block ]; then
        # the denial must name a safe alternative and the self-run escape
        if ! printf '%s' "$err" | grep -q 'Safe alternative:'; then
            FAIL=$((FAIL + 1))
            printf 'FAIL: %s (block has no "Safe alternative:" line)\n' "$desc"
            return
        fi
        if ! printf '%s' "$err" | grep -q '! <command>'; then
            FAIL=$((FAIL + 1))
            # shellcheck disable=SC2016  # literal backticks in the message
            printf 'FAIL: %s (block does not mention the `! <command>` escape)\n' "$desc"
            return
        fi
    elif [ -n "$out$err" ]; then
        FAIL=$((FAIL + 1))
        printf 'FAIL: %s (allowed but produced output)\n' "$desc"
        return
    fi

    PASS=$((PASS + 1))
}

TMP=""
for cand in "${TMPDIR:-}" /tmp/claude /tmp .; do
    [ -n "$cand" ] || continue
    if mkdir -p "$cand/destructive-git-tests.$$" 2>/dev/null; then
        TMP="$cand/destructive-git-tests.$$"
        break
    fi
done
[ -n "$TMP" ] || { echo "no writable temp dir found" >&2; exit 1; }
trap 'rm -rf "$TMP"' EXIT

echo "=== forbidden forms (must block) ==="
run "reset --hard"              'git reset --hard'                          block
run "reset --hard HEAD~1"       'git reset --hard HEAD~1'                   block
run "checkout -- path"          'git checkout -- src/main.py'               block
run "checkout ."                'git checkout .'                            block
run "clean -fd"                 'git clean -fd'                             block
run "bare stash"                'git stash'                                 block
run "stash pop"                 'git stash pop'                             block

echo "=== variants that must still block ==="
run "clean -f"                  'git clean -f'                              block
run "clean -fdx"                'git clean -fdx'                            block
run "clean --force"             'git clean --force -d'                      block
run "stash pop with index"      'git stash pop --index'                     block
run "reset --hard via -C"       'git -C /repo reset --hard'                 block
run "chained after cd"          'cd /repo && git reset --hard'              block
run "chained after other git"   'git fetch && git reset --hard origin/main' block
run "checkout HEAD -- path"     'git checkout HEAD -- a.txt'                block
run "sudo-prefixed"             'sudo git clean -fd'                        block
run "env-prefixed"              'GIT_DIR=/r/.git git reset --hard'          block

echo "=== legitimate commands (must pass) ==="
run "checkout branch"           'git checkout main'                         allow
run "checkout -b new"           'git checkout -b feature/x'                 allow
run "checkout branch dashdash"  'git checkout feature-branch'               allow
run "stash push -m"             'git stash push -u -m "my-tag"'             allow
run "stash apply"               'git stash apply abc1234'                   allow
run "stash list"                'git stash list --format="%H %gs"'          allow
run "stash show"                'git stash show -p stash@{0}'               allow
run "reset --soft"              'git reset --soft HEAD~1'                   allow
run "reset --mixed"             'git reset --mixed HEAD'                    allow
run "bare reset"                'git reset'                                 allow
run "clean dry run"             'git clean -n'                              allow
run "clean --dry-run"           'git clean --dry-run -d'                    allow
run "status"                    'git status --porcelain'                    allow
run "commit"                    'git commit -m "reset --hard the counter"'  allow
run "diff"                      'git diff -- src/main.py'                   allow
run "log"                       'git log --oneline -5'                      allow
run "non-git reset"             'systemctl reset-failed'                    allow
run "empty command"             ''                                          allow

echo
TOTAL=$((PASS + FAIL))
echo "Results: $PASS passed, $FAIL failed (total $TOTAL)"
[ "$FAIL" -eq 0 ] && echo "All tests passed!"
[ "$FAIL" -eq 0 ]
