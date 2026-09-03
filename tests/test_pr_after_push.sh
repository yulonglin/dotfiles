#!/usr/bin/env bash
# Pins claude/hooks/pr_after_push.sh — the PostToolUse(Bash) hook that opens a
# draft PR after a successful push of a non-default branch and injects the
# review-then-merge-if-simple instruction.
#
# `gh` is stubbed on PATH: the stub records every invocation and answers
# `pr list` from a file the test controls, so both the "PR exists" and the
# "create one" branches are exercised without a network. Both directions are
# asserted: a hook that fires on every git command is as useless as one that
# never fires.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="${HOOK:-$REPO_ROOT/claude/hooks/pr_after_push.sh}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/pr-after-push-test.XXXXXX")"
trap 'command rm -rf "$WORK"' EXIT

PASS=0
fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { PASS=$((PASS + 1)); }

# A repo on a feature branch with a GitHub remote.
REPO="$WORK/repo"
mkdir -p "$REPO"
git init -q -b main "$REPO"
git -C "$REPO" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git -C "$REPO" remote add origin git@github.com:someone/repo.git
git -C "$REPO" checkout -q -b feature-x

FEATCONF="$WORK/features.conf"
printf 'git.pr-after-push = on\n' > "$FEATCONF"

# gh stub: logs args; `pr list` prints $WORK/pr-list; `pr create` prints a URL.
STUB="$WORK/stub"
mkdir -p "$STUB"
cat > "$STUB/gh" <<'SH'
#!/bin/sh
echo "$*" >> "$GH_LOG"
case "$1 $2" in
  "pr list") cat "$GH_PR_LIST" 2>/dev/null ;;
  "pr create") echo "https://github.com/someone/repo/pull/42" ;;
esac
SH
chmod +x "$STUB/gh"
export GH_LOG="$WORK/gh.log" GH_PR_LIST="$WORK/pr-list"

run_hook() {
    # $1 = command, $2 = tool response text
    command rm -f "$GH_LOG"
    python3 - "$1" "$2" "$REPO" <<'PY' | PATH="$STUB:$PATH" CLAUDE_HOOK_FEATURES_FILE="$FEATCONF" bash "$HOOK" 2>/dev/null || true
import json, sys
cmd, resp, cwd = sys.argv[1:4]
print(json.dumps({"tool_name": "Bash", "cwd": cwd,
                  "tool_input": {"command": cmd},
                  "tool_response": {"stdout": resp, "stderr": ""}}))
PY
}

# --- creates a draft PR when none exists ------------------------------------
: > "$GH_PR_LIST"
OUT="$(run_hook "git add x && git commit -m m && git push -u origin feature-x" "branch 'feature-x' set up to track")"
grep -q "pull/42" <<<"$OUT" || fail "no PR url in nudge after push: $OUT"
grep -q "additionalContext" <<<"$OUT" || fail "not PostToolUse additionalContext"
grep -q "pr create --draft --fill --head feature-x" "$GH_LOG" || fail "gh pr create not called as draft --fill: $(cat "$GH_LOG")"
grep -qi "merge it yourself" <<<"$OUT" || fail "review/merge instruction missing"
grep -q "AskUserQuestion" <<<"$OUT" || fail "fallback to asking the user missing"
ok

# --- reports an existing PR instead of creating another ---------------------
echo 7 > "$GH_PR_LIST"
OUT="$(run_hook "git push" "Everything up-to-date")"
grep -q "PR #7" <<<"$OUT" || fail "existing PR not reported: $OUT"
grep -q "pr create" "$GH_LOG" && fail "created a second PR when one was open"
ok

# --- silent cases ------------------------------------------------------------
: > "$GH_PR_LIST"
[ -z "$(run_hook "git status" "")" ] || fail "fired on a non-push"
[ -z "$(run_hook "git push origin --delete feature-x" "")" ] || fail "fired on a branch delete"
[ -z "$(run_hook "git push --tags" "")" ] || fail "fired on a tags-only push"
[ -z "$(run_hook "git push" "! [rejected] feature-x -> feature-x (fetch first)")" ] || fail "fired on a rejected push"
[ -z "$(run_hook "git push" "fatal: could not read from remote repository")" ] || fail "fired on a failed push"
ok

git -C "$REPO" checkout -q main
[ -z "$(run_hook "git push" "main -> main")" ] || fail "fired on a push of main"
git -C "$REPO" checkout -q feature-x
ok

# --- feature flag off is silent ---------------------------------------------
printf 'git.pr-after-push = off\n' > "$FEATCONF"
[ -z "$(run_hook "git push" "ok")" ] || fail "fired with git.pr-after-push = off"
printf 'git.pr-after-push = on\n' > "$FEATCONF"
ok

echo "test_pr_after_push: $PASS groups passed"
