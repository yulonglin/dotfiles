#!/usr/bin/env bash
# AC7 behaviour spot-checks: for each rule sentence deleted from the memory
# tier, prove the replacement hook still produces the behaviour.
#
# SCOPE: script-level. Each hook is fed the JSON the harness would send and
# its exit code / stdout is inspected. This is NOT live session enforcement.
# Wiring is a post-merge step by necessity: ~/.claude/hooks resolves into the
# main checkout, where these scripts do not exist until this branch merges, so
# editing settings.json first would point live hooks at missing files. The
# wiring patch is in the PR body; these script-level tests are the pre-merge
# proof that the behaviour survives the prose deletions.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
H=claude/hooks

bash_json() { python3 -c "
import json, sys
print(json.dumps({'tool_name': 'Bash', 'tool_input': {'command': sys.argv[1]}}))
" "$1"; }

check() { # desc expected_rc actual_rc
    if [ "$2" = "$3" ]; then printf '  PASS  %s\n' "$1"
    else printf '  FAIL  %s (want rc=%s, got rc=%s)\n' "$1" "$2" "$3"; fi
}

echo "== deleted from safety.md: 'never git reset --hard / checkout -- / clean -fd' =="
for cmd in 'git reset --hard' 'git checkout -- src/a.py' 'git clean -fd'; do
    rc=0; bash_json "$cmd" | bash "$H/block_destructive_git.sh" >/dev/null 2>&1 || rc=$?
    check "blocks: $cmd" 2 "$rc"
done

echo "== deleted from safety.md: 'never bare git stash / stash pop' =="
for cmd in 'git stash' 'git stash pop'; do
    rc=0; bash_json "$cmd" | bash "$H/block_destructive_git.sh" >/dev/null 2>&1 || rc=$?
    check "blocks: $cmd" 2 "$rc"
done

echo "== kept in prose, must NOT be blocked (the safe stash workflow) =="
for cmd in 'git stash push -u -m "wip"' 'git stash apply abc123' 'git stash show -p stash@{0}'; do
    rc=0; bash_json "$cmd" | bash "$H/block_destructive_git.sh" >/dev/null 2>&1 || rc=$?
    check "allows: $cmd" 0 "$rc"
done
