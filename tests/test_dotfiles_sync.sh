#!/usr/bin/env bash
# Pins custom_bins/dotfiles-sync against a bare fake remote and two clones.
#
# Cases, each asserted on the remote's state and on the working tree being left
# intact:
#   1. no-op        : clean and in sync -> nothing committed, nothing pushed
#   2. dirty        : dirty tree -> one "sync: <host> <utc>" commit reaches the remote
#   3. behind       : remote moved -> local rebased, local commit pushed on top
#   4. conflict     : both sides edit one line -> rebase aborted, tree untouched,
#                     state file says failed, exit 1
#   5. held back    : pre-commit rejects claude/settings.json -> the other file
#                     is committed and pushed, settings.json stays dirty, state
#                     records held_back
#   6. dry-run      : nothing changes anywhere
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SYNC="$REPO_ROOT/custom_bins/dotfiles-sync"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-sync-test.XXXXXX")"
# A trailing slash in TMPDIR yields a "//" path the macOS sandbox refuses to create under.
WORK="${WORK//\/\///}"
trap 'rm -rf "$WORK"' EXIT

export DOTFILES_SYNC_NOTIFY=0
export DOTFILES_SYNC_STATE_DIR="$WORK/state"
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
# The user's global hooks (core.hooksPath) must not fire on these throwaway repos.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
# An empty template: `git init`/`clone` otherwise copy sample hooks into .git/hooks,
# and the Claude Code sandbox refuses every write under a .git/hooks directory.
mkdir -p "$WORK/template"
export GIT_TEMPLATE_DIR="$WORK/template"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok - $*"; }

state_field() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$DOTFILES_SYNC_STATE_DIR/$1.json" "$2"; }

fresh_remote() {
    # $1 = name; creates $WORK/$1.git (bare, main), $WORK/$1 (clone A), $WORK/$1-b (clone B)
    local n="$1"
    rm -rf "${WORK:?}/$n.git" "${WORK:?}/$n" "${WORK:?}/$n-b"
    git init -q --bare -b main "$WORK/$n.git"
    git clone -q "$WORK/$n.git" "$WORK/$n" 2>/dev/null
    git -C "$WORK/$n" checkout -q -b main
    echo one >"$WORK/$n/file.txt"
    git -C "$WORK/$n" add file.txt
    git -C "$WORK/$n" commit -q -m init
    git -C "$WORK/$n" push -q -u origin main
    git clone -q "$WORK/$n.git" "$WORK/$n-b" 2>/dev/null
}

# 1. no-op
fresh_remote noop
"$SYNC" "$WORK/noop" >/dev/null || fail "no-op run exited non-zero"
[ "$(git -C "$WORK/noop.git" rev-list --count main)" = 1 ] || fail "no-op pushed something"
[ "$(state_field noop status)" = ok ] || fail "no-op state not ok"
pass "no-op leaves the remote alone"

# 2. dirty -> commit -> push
fresh_remote dirty
echo two >"$WORK/dirty/file.txt"
echo new >"$WORK/dirty/untracked.txt"
mkfifo "$WORK/dirty/a-fifo"   # not a regular file: must not be staged
"$SYNC" "$WORK/dirty" >/dev/null || fail "dirty run exited non-zero"
subj="$(git -C "$WORK/dirty.git" log -1 --format=%s main)"
[[ "$subj" == sync:\ *T*Z ]] || fail "remote subject is '$subj'"
git -C "$WORK/dirty.git" ls-tree --name-only main | grep -qx untracked.txt || fail "untracked file not committed"
git -C "$WORK/dirty.git" ls-tree --name-only main | grep -qx a-fifo && fail "fifo was staged"
[ -z "$(git -C "$WORK/dirty" status --porcelain --untracked-files=no)" ] || fail "tree still dirty after sync"
[ "$(state_field dirty pushed)" = 1 ] || fail "state pushed != 1"
pass "dirty tree becomes one sync commit on the remote"

# 3. behind -> rebase -> push
fresh_remote behind
echo remote-only >"$WORK/behind-b/other.txt"
git -C "$WORK/behind-b" add other.txt && git -C "$WORK/behind-b" commit -q -m remote && git -C "$WORK/behind-b" push -q
echo local >"$WORK/behind/local.txt"
git -C "$WORK/behind" add local.txt && git -C "$WORK/behind" commit -q -m local
"$SYNC" "$WORK/behind" >/dev/null || fail "behind run exited non-zero"
[ "$(git -C "$WORK/behind.git" rev-list --count main)" = 3 ] || fail "remote does not have 3 commits"
[ "$(git -C "$WORK/behind.git" log -1 --format=%s main)" = local ] || fail "local commit not on top after rebase"
[ "$(git -C "$WORK/behind.git" rev-list --merges --count main)" = 0 ] || fail "a merge commit was created"
[ "$(state_field behind pulled)" = 1 ] || fail "state pulled != 1"
pass "behind rebases and pushes without a merge commit"

# 4. conflict -> abort
fresh_remote conflict
echo remote-line >"$WORK/conflict-b/file.txt"
git -C "$WORK/conflict-b" commit -q -am remote && git -C "$WORK/conflict-b" push -q
echo local-line >"$WORK/conflict/file.txt"
before="$(git -C "$WORK/conflict" rev-parse HEAD)"
if "$SYNC" "$WORK/conflict" >/dev/null 2>&1; then fail "conflict run exited 0"; fi
[ ! -e "$WORK/conflict/.git/rebase-merge" ] && [ ! -e "$WORK/conflict/.git/rebase-apply" ] || fail "rebase left in progress"
grep -q local-line "$WORK/conflict/file.txt" || fail "local edit lost"
[ "$(git -C "$WORK/conflict.git" rev-list --count main)" = 2 ] || fail "something was pushed despite conflict"
[ "$(state_field conflict status)" = failed ] || fail "state not failed"
state_field conflict message | grep -q conflicted || fail "state message does not say conflicted"
# The local sync commit exists (commit precedes rebase) but HEAD is still on the local line, not the remote's.
[ "$(git -C "$WORK/conflict" rev-parse HEAD)" != "$before" ] || fail "expected a local sync commit before the aborted rebase"
pass "conflict aborts the rebase and leaves the tree untouched"

# 5. pre-commit rejects claude/settings.json -> held back
fresh_remote held
mkdir -p "$WORK/held/claude" "$WORK/held/.hooks"
echo '{"a":1}' >"$WORK/held/claude/settings.json"
git -C "$WORK/held" add claude && git -C "$WORK/held" commit -q -m settings && git -C "$WORK/held" push -q
cat >"$WORK/held/.hooks/pre-commit" <<'H'
#!/bin/sh
git diff --cached --name-only | grep -qx claude/settings.json && { echo "gateway guard: refusing claude/settings.json" >&2; exit 1; }
exit 0
H
chmod +x "$WORK/held/.hooks/pre-commit"
git -C "$WORK/held" config core.hooksPath .hooks
echo '{"a":2,"secret":true}' >"$WORK/held/claude/settings.json"
echo docs >"$WORK/held/README.md"
"$SYNC" "$WORK/held" >/dev/null || fail "held-back run exited non-zero"
git -C "$WORK/held.git" ls-tree --name-only main | grep -qx README.md || fail "README not pushed"
[ "$(git -C "$WORK/held.git" show main:claude/settings.json)" = '{"a":1}' ] || fail "settings.json reached the remote"
git -C "$WORK/held" status --porcelain | grep -q 'claude/settings.json' || fail "settings.json no longer dirty locally"
[ "$(state_field held held_back)" = claude/settings.json ] || fail "state held_back not recorded"
[ "$(state_field held status)" = ok ] || fail "held-back run should still be ok"
pass "rejected settings.json is held back, everything else ships"

# 6. dry-run changes nothing
fresh_remote dry
echo two >"$WORK/dry/file.txt"
"$SYNC" --dry-run "$WORK/dry" >/dev/null || fail "dry-run exited non-zero"
[ "$(git -C "$WORK/dry.git" rev-list --count main)" = 1 ] || fail "dry-run pushed"
[ "$(git -C "$WORK/dry" rev-list --count HEAD)" = 1 ] || fail "dry-run committed"
[ ! -e "$DOTFILES_SYNC_STATE_DIR/dry.json" ] || fail "dry-run wrote state"
pass "dry-run is inert"

# 7. --prune: merged clean worktrees go, everything else stays and is reported
fresh_remote prune
P="$WORK/prune"; WT="$P/.claude/worktrees"; mkdir -p "$WT"
add_wt() {  # name, then optional commit subject on its branch
    git -C "$P" worktree add -q -b "worktree-$1" "$WT/$1" main 2>/dev/null
    if [ -n "${2:-}" ]; then
        echo "$2" >"$WT/$1/$1.txt"; git -C "$WT/$1" add "$1.txt"; git -C "$WT/$1" commit -q -m "$2"
    fi
}
add_wt merged                              # 0 ahead, clean         -> removed, branch deleted
add_wt dirty;    echo junk >"$WT/dirty/untracked.txt"   # 0 ahead, dirty -> kept
add_wt locked;   git -C "$P" worktree lock "$WT/locked" # 0 ahead, locked -> kept
add_wt fresh "fresh work"                  # unmerged, recent       -> kept, not stale
GIT_COMMITTER_DATE="$(date -u -v-30d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '30 days ago' +%Y-%m-%dT%H:%M:%SZ)" \
    add_wt old "old work"                  # unmerged, 30 days      -> kept, stale
git -C "$P" branch orphan-merged main      # merged, no worktree    -> branch deleted
git -C "$P" branch orphan-unmerged worktree-old   # unmerged, no worktree -> untouched
"$SYNC" --prune "$P" >"$WORK/prune.log" 2>&1 || fail "prune exited non-zero: $(cat "$WORK/prune.log")"
[ ! -d "$WT/merged" ] || fail "merged worktree not removed"
git -C "$P" rev-parse -q --verify worktree-merged >/dev/null && fail "merged branch not deleted"
git -C "$P" rev-parse -q --verify orphan-merged >/dev/null && fail "orphan merged branch not deleted"
for k in dirty locked fresh old; do [ -d "$WT/$k" ] || fail "$k worktree was removed"; done
git -C "$P" rev-parse -q --verify orphan-unmerged >/dev/null || fail "unmerged orphan branch deleted"
[ "$(git -C "$WT/old" log -1 --format=%s)" = "old work" ] || fail "old worktree lost its commit"
[ "$(state_field prune.prune status)" = ok ] || fail "prune state not ok"
python3 -c 'import json,sys; s=json.load(open(sys.argv[1])); assert s["removed"]==["merged","branch orphan-merged"], s["removed"]; assert len(s["stale"])==1 and s["stale"][0].startswith("old ("), s["stale"]; assert not any(k.startswith("fresh") for k in s["stale"]); assert any(k.startswith("locked: locked") for k in s["kept"]) and any(k.startswith("dirty: dirty") for k in s["kept"]), s["kept"]' "$DOTFILES_SYNC_STATE_DIR/prune.prune.json" || fail "prune state contents wrong"
pass "prune removes only merged clean worktrees and lists the stale unmerged one"

# 8. --prune --dry-run touches nothing
fresh_remote prunedry
mkdir -p "$WORK/prunedry/.claude/worktrees"
git -C "$WORK/prunedry" worktree add -q -b worktree-m "$WORK/prunedry/.claude/worktrees/m" main 2>/dev/null
"$SYNC" --prune --dry-run "$WORK/prunedry" >/dev/null || fail "prune dry-run exited non-zero"
[ -d "$WORK/prunedry/.claude/worktrees/m" ] || fail "prune dry-run removed a worktree"
[ ! -e "$DOTFILES_SYNC_STATE_DIR/prunedry.prune.json" ] || fail "prune dry-run wrote state"
pass "prune dry-run is inert"

# The nudge hook reads the state files written above: conflict must surface, noop must not.
NUDGE="$REPO_ROOT/claude/hooks/nudge_dotfiles_sync.sh"
out="$(CLAUDE_HOOK_FEATURES_FILE=/dev/null bash "$NUDGE" </dev/null)"
echo "$out" | grep -q 'conflict: last dotfiles-sync FAILED' || fail "nudge did not report the failed repo: $out"
echo "$out" | grep -q 'held: claude/settings.json was held back' || fail "nudge did not report the held-back file"
echo "$out" | grep -q 'prune: 1 worktree(s) with unmerged commits older than' || fail "nudge did not report the stale worktree: $out"
echo "$out" | grep -q '"hookEventName": "SessionStart"' || fail "nudge output is not a SessionStart payload"
echo "$out" | grep -q 'noop:' && fail "nudge mentioned the healthy repo"
pass "nudge surfaces failures, held-back files and stale worktrees only"

echo "all dotfiles-sync tests passed"
