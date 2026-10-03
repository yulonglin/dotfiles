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
#   5b-5e. codex    : the same for codex/config.toml (alone, together with
#                     settings.json, an accepted edit that is not held, and a
#                     held codex config that must not starve settings.json)
#   5f. zed         : with the zed-ssh clean filter, a Zed edit carrying
#                     ssh_connections ships without the block, nothing held
#   5g. zed, no filter: the real pre-commit hook rejects, only the Zed file is
#                     held back and the rest ships
#   5h-5j. zed rebase : a pulled Zed change keeps the local ssh_connections; no
#                     Zed change is byte-identical; a failed restore keeps the backup
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

# 5b-5d. codex/config.toml is on the same hold-back list. The fake hook stands
# in for the real trust-table guard: it rejects a staged [projects. table only.
fresh_remote codex
mkdir -p "$WORK/codex/claude" "$WORK/codex/codex" "$WORK/codex/.hooks"
echo '{"a":1}' >"$WORK/codex/claude/settings.json"
printf 'model = "m"\n' >"$WORK/codex/codex/config.toml"
git -C "$WORK/codex" add claude codex && git -C "$WORK/codex" commit -q -m base && git -C "$WORK/codex" push -q
cat >"$WORK/codex/.hooks/pre-commit" <<'H'
#!/bin/sh
staged=$(git diff --cached --name-only)
echo "$staged" | grep -qx claude/settings.json && { echo "gateway guard: refusing claude/settings.json" >&2; exit 1; }
if echo "$staged" | grep -qx codex/config.toml && git show :codex/config.toml | grep -q '^\[projects\.'; then
    echo "trust-table guard: refusing codex/config.toml" >&2; exit 1
fi
exit 0
H
chmod +x "$WORK/codex/.hooks/pre-commit"
git -C "$WORK/codex" config core.hooksPath .hooks

# 5b. only codex/config.toml is rejected -> held back alone, the rest ships
printf 'model = "m"\n\n[projects."/home/example/p"]\ntrust_level = "trusted"\n' >"$WORK/codex/codex/config.toml"
echo docs >"$WORK/codex/README.md"
"$SYNC" "$WORK/codex" >/dev/null || fail "codex held-back run exited non-zero"
git -C "$WORK/codex.git" ls-tree --name-only main | grep -qx README.md || fail "README not pushed alongside held codex config"
git -C "$WORK/codex.git" show main:codex/config.toml | grep -q projects && fail "trust table reached the remote"
git -C "$WORK/codex" status --porcelain | grep -q 'codex/config.toml' || fail "codex/config.toml no longer dirty locally"
[ "$(state_field codex held_back)" = codex/config.toml ] || fail "state held_back should name codex/config.toml, got: $(state_field codex held_back)"
[ "$(state_field codex status)" = ok ] || fail "codex held-back run should still be ok"
pass "rejected codex/config.toml is held back, everything else ships"

# 5c. both dirty and the hook rejects -> both held back, both recorded
echo '{"a":2}' >"$WORK/codex/claude/settings.json"
echo more >>"$WORK/codex/README.md"
"$SYNC" "$WORK/codex" >/dev/null || fail "two-file held-back run exited non-zero"
[ "$(git -C "$WORK/codex.git" show main:README.md | tail -1)" = more ] || fail "README edit not pushed while both files were held"
[ "$(git -C "$WORK/codex.git" show main:claude/settings.json)" = '{"a":1}' ] || fail "settings.json reached the remote"
[ "$(state_field codex held_back)" = "claude/settings.json codex/config.toml" ] \
    || fail "state held_back should list both paths, got: $(state_field codex held_back)"
pass "both hold-back files are held when the hook rejects"

# 5d. a codex/config.toml edit the hook accepts is committed, not held
git -C "$WORK/codex" restore claude/settings.json
printf 'model = "m2"\n' >"$WORK/codex/codex/config.toml"
"$SYNC" "$WORK/codex" >/dev/null || fail "clean codex run exited non-zero"
[ "$(git -C "$WORK/codex.git" show main:codex/config.toml)" = 'model = "m2"' ] || fail "accepted codex/config.toml edit was not pushed"
[ "$(state_field codex held_back)" = "" ] || fail "nothing should be held when the hook accepts"
pass "an accepted codex/config.toml edit ships"

# 5e. a permanently dirty codex/config.toml must not starve settings.json. Here
# the hook rejects settings.json only when it carries the "secret" marker, as
# the real gateway guard rejects only the gateway keys. Both files are dirty, the
# hook rejects the whole commit, and the settings.json edit must still ship.
fresh_remote starve
mkdir -p "$WORK/starve/claude" "$WORK/starve/codex" "$WORK/starve/.hooks"
echo '{"a":1}' >"$WORK/starve/claude/settings.json"
printf 'model = "m"\n' >"$WORK/starve/codex/config.toml"
git -C "$WORK/starve" add claude codex && git -C "$WORK/starve" commit -q -m base && git -C "$WORK/starve" push -q
cat >"$WORK/starve/.hooks/pre-commit" <<'H'
#!/bin/sh
staged=$(git diff --cached --name-only)
if echo "$staged" | grep -qx claude/settings.json && git show :claude/settings.json | grep -q secret; then
    echo "gateway guard: refusing claude/settings.json" >&2; exit 1
fi
if echo "$staged" | grep -qx codex/config.toml && git show :codex/config.toml | grep -q '^\[projects\.'; then
    echo "trust-table guard: refusing codex/config.toml" >&2; exit 1
fi
exit 0
H
chmod +x "$WORK/starve/.hooks/pre-commit"
git -C "$WORK/starve" config core.hooksPath .hooks
printf 'model = "m"\n\n[projects."/home/example/p"]\ntrust_level = "trusted"\n' >"$WORK/starve/codex/config.toml"
echo '{"a":2}' >"$WORK/starve/claude/settings.json"
"$SYNC" "$WORK/starve" >/dev/null || fail "starvation run exited non-zero"
[ "$(git -C "$WORK/starve.git" show main:claude/settings.json)" = '{"a":2}' ] || fail "clean settings.json edit was starved by a held codex/config.toml"
git -C "$WORK/starve.git" show main:codex/config.toml | grep -q projects && fail "trust table reached the remote"
[ "$(state_field starve held_back)" = codex/config.toml ] || fail "only codex/config.toml should be held, got: $(state_field starve held_back)"
[ "$(git -C "$WORK/starve.git" rev-list --count main)" = 3 ] || fail "expected one sync commit, not one per retried file"
pass "a held codex/config.toml does not starve an accepted settings.json edit"

# 5f. config/zed/settings.json is NOT on the default list: the zed-ssh clean
# filter strips ssh_connections before git stores the file, so the rest of a
# Zed edit ships. These cases run the REAL pre-commit hook and filter.
zed_repo() {
    # $1 = name; a repo with the real .gitattributes line and a Zed settings file
    fresh_remote "$1"
    mkdir -p "$WORK/$1/config/zed"
    grep -F 'filter=zed-ssh' "$REPO_ROOT/.gitattributes" >"$WORK/$1/.gitattributes"
    printf '{\n  // editor\n  "vim_mode": true,\n}\n' >"$WORK/$1/config/zed/settings.json"
    git -C "$WORK/$1" add .gitattributes config && git -C "$WORK/$1" commit -q -m base && git -C "$WORK/$1" push -q
    git -C "$WORK/$1" config core.hooksPath "$REPO_ROOT/config/git-hooks"
    printf '{\n  // editor\n  "vim_mode": false,\n  "ssh_connections": [{ "host": "example-host", "projects": [] }],\n}\n' >"$WORK/$1/config/zed/settings.json"
    echo docs >"$WORK/$1/README.md"
}
zed_repo zed
git -C "$WORK/zed" config filter.zed-ssh.clean "$REPO_ROOT/scripts/git-filters/zed-strip-ssh-connections"
"$SYNC" "$WORK/zed" >/dev/null || fail "zed filtered run exited non-zero"
git -C "$WORK/zed.git" ls-tree --name-only main | grep -qx README.md || fail "README not pushed alongside the Zed settings"
git -C "$WORK/zed.git" show main:config/zed/settings.json | grep -q '"vim_mode": false' || fail "the Zed vim_mode edit did not ship"
git -C "$WORK/zed.git" show main:config/zed/settings.json | grep -q ssh_connections && fail "ssh_connections reached the remote"
grep -q example-host "$WORK/zed/config/zed/settings.json" || fail "the local Zed settings lost their ssh_connections"
[ -z "$(git -C "$WORK/zed" status --porcelain)" ] || fail "tree not clean after sync: $(git -C "$WORK/zed" status --porcelain)"
[ "$(state_field zed status)" = ok ] || fail "filtered Zed run should be ok"
[ -z "$(state_field zed held_back)" ] || fail "nothing should be held, got: $(state_field zed held_back)"
pass "with the clean filter, a Zed edit ships without ssh_connections and nothing is held"

# 5g. Without the filter configured the guard rejects; the Zed file is still a
# hold-back path as a fallback, so only it is held and the rest ships.
zed_repo zednofilter
"$SYNC" "$WORK/zednofilter" >/dev/null || fail "unfiltered Zed run exited non-zero"
git -C "$WORK/zednofilter.git" ls-tree --name-only main | grep -qx README.md || fail "README not pushed alongside the held Zed settings"
git -C "$WORK/zednofilter.git" show main:config/zed/settings.json | grep -q ssh_connections && fail "ssh_connections reached the remote"
grep -q example-host "$WORK/zednofilter/config/zed/settings.json" || fail "the held run touched the local Zed settings"
[ "$(state_field zednofilter held_back)" = config/zed/settings.json ] || fail "state held_back should name only the Zed settings, got: $(state_field zednofilter held_back)"
pass "without the clean filter, only the Zed settings are held and the rest ships"

# 5h-5j. The rebase keeps the local ssh_connections. Clone B pushes changes and
# the filtered clone from 5f syncs them in; its block exists only on disk.
ZA="$WORK/zed/config/zed/settings.json"
ZBAK="$DOTFILES_SYNC_STATE_DIR/zed.zed-ssh-connections.json"
git -C "$WORK/zed-b" pull -q --rebase
b_push() {  # $1 = commit subject; the change is already in clone B's tree
    git -C "$WORK/zed-b" add -A && git -C "$WORK/zed-b" commit -q -m "$1" && git -C "$WORK/zed-b" push -q
}

# 5h. B changes a Zed setting: the rebase rewrites A's file without the block.
printf '{\n  // editor\n  "vim_mode": false,\n  "theme": "Ayu",\n}\n' >"$WORK/zed-b/config/zed/settings.json"
b_push "zed theme"
"$SYNC" "$WORK/zed" >/dev/null || fail "zed pull run exited non-zero"
grep -q '"theme": "Ayu"' "$ZA" || fail "the pulled Zed change did not land"
grep -q example-host "$ZA" || fail "the rebase dropped the local ssh_connections"
grep -q example-host "$ZBAK" || fail "no backup of the block in the state dir"
git -C "$WORK/zed" diff --quiet || fail "the restored block shows up in git diff"
pass "a sync that pulls a Zed change keeps the local ssh_connections, with a backup"

# 5i. B changes something else: A's Zed file is byte-identical afterwards.
cp "$ZA" "$WORK/zed-before.json"
echo more >>"$WORK/zed-b/README.md"
b_push "readme"
"$SYNC" "$WORK/zed" >/dev/null || fail "zed no-change run exited non-zero"
cmp -s "$ZA" "$WORK/zed-before.json" || fail "a sync without a Zed change altered the Zed settings"
pass "a sync with no Zed change leaves the Zed settings byte-identical"

# 5j. B pushes a Zed file the restore cannot parse: A's file is left as the
# rebase wrote it, the backup stays, and the state says so.
printf '{\n  "vim_mode": tru\n' >"$WORK/zed-b/config/zed/settings.json"
b_push "broken zed"
"$SYNC" "$WORK/zed" >/dev/null || fail "zed failed-restore run exited non-zero"
cmp -s "$ZA" "$WORK/zed-b/config/zed/settings.json" || fail "a failed restore modified the Zed settings"
grep -q example-host "$ZBAK" || fail "a failed restore lost the backup"
state_field zed message | grep -q "not restored" || fail "state message does not report the failed restore: $(state_field zed message)"
pass "a failed restore leaves the file alone and keeps the backup"

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

# 9. A live lock holder is waited for, not bailed on; a dead holder is reclaimed.
fresh_remote lockwait
mkdir -p "$DOTFILES_SYNC_STATE_DIR/lock.d"
( sleep 8 ) & holder=$!
echo "$holder" >"$DOTFILES_SYNC_STATE_DIR/lock.d/pid"
start=$(date +%s)
DOTFILES_SYNC_LOCK_WAIT=60 "$SYNC" "$WORK/lockwait" >"$WORK/lockwait.log" 2>&1 || fail "lock-wait run exited non-zero: $(cat "$WORK/lockwait.log")"
(( $(date +%s) - start >= 5 )) || fail "did not wait for the live lock holder"
grep -q 'is running; waiting' "$WORK/lockwait.log" || fail "no waiting message: $(cat "$WORK/lockwait.log")"
[ "$(state_field lockwait status)" = ok ] || fail "run after lock release did not sync"
wait "$holder" 2>/dev/null || true
mkdir -p "$DOTFILES_SYNC_STATE_DIR/lock.d"; echo 999999 >"$DOTFILES_SYNC_STATE_DIR/lock.d/pid"
start=$(date +%s)
"$SYNC" "$WORK/lockwait" >/dev/null 2>&1 || fail "dead-lock run exited non-zero"
(( $(date +%s) - start < 5 )) || fail "waited on a dead lock holder"
mkdir -p "$DOTFILES_SYNC_STATE_DIR/lock.d"; ( sleep 20 ) & holder=$!; echo "$holder" >"$DOTFILES_SYNC_STATE_DIR/lock.d/pid"
if DOTFILES_SYNC_LOCK_WAIT=5 "$SYNC" "$WORK/lockwait" >"$WORK/lockwait2.log" 2>&1; then fail "gave up should exit non-zero"; fi
grep -q 'giving up' "$WORK/lockwait2.log" || fail "no giving-up message"
kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null || true; rm -rf "$DOTFILES_SYNC_STATE_DIR/lock.d"
pass "lock: waits for a live holder, reclaims a dead one, gives up at the cap"

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
