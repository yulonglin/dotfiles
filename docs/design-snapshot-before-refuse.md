# Snapshot before refusing a destructive git command

Status: design for review, 2026-09-11. **Not implemented.** Nothing in `claude/hooks/block_destructive_git.sh` takes a snapshot today.

## Design doc beats rule or skill

A reviewer asked whether this belongs in `claude/rules/` or `claude/skills/` instead. It belongs in neither, because nothing here is a procedure Claude follows. The hook runs the snapshot in its own process before `deny()` returns; the agent never chooses to take one, never needs to remember the commands, and cannot skip it.

A rule is always-loaded context that costs budget every session. `claude/rules/safety.md` already carries the only sentence a session needs — that `block_destructive_git.sh` refuses these forms — and the recovery instruction reaches the agent through the hook's own refusal text at the exact moment it is refused, at zero always-on cost. A skill is activity-scoped procedure, and there is no activity: "recover from a snapshot I did not know existed" is not something a session goes looking for.

So the durable prose after implementation is one added clause in `claude/rules/safety.md` and the refusal string inside the hook. This file is the design, and it stays a design until the hook carries the mechanism.

## What exists today

`claude/hooks/block_destructive_git.sh` (153 lines) is a PreToolUse Bash hook. It splits compound commands on unquoted separators, and `deny()` exits 2 with a reason and a suggested alternative. It refuses `git reset --hard`, `git checkout -- <path>`, `git checkout .`, `git clean -f[d]`, bare `git stash` and `git stash pop`.

## A snapshot makes caught refusals recoverable

The refusal protects work by preventing the command, which is the right default and should stay. But it protects nothing once the command is reworded into a form the matcher does not catch — `git restore --worktree <path>`, `git checkout HEAD -- <path>` and `git reset --keep` all discard uncommitted work and none are blocked today. A snapshot turns the caught cases into recoverable ones, and costs nothing when it is never needed.

## The snapshot never touches the stash stack

This repo's rules already name the hazard: the stash stack is shared across every worktree, so an auto-`git stash push` could be popped by another session. Every mechanism below writes objects and one ref and nothing else — verified with `git stash list`, which stayed empty through the whole experiment, and `git status --porcelain`, which was byte-identical before and after a snapshot.

## Only a temp index captures untracked files

The open question was whether `git stash create` covers `git clean -f`, the one refusal where recovery matters most. It does not, and the obvious fix does not either. Measured on git 2.43.0 in a scratch repo with one modified tracked file (`tracked.txt`), two untracked files (`untracked.txt`, `sub/nested.txt`) and one gitignored file (`ignored.log`).

`git stash create "blocked: git clean -f"` printed `ffe0eff97f4f…`, and `git ls-tree -r --name-only ffe0eff` printed exactly `.gitignore` and `tracked.txt`. Both untracked files were absent. `git show --stat` confirmed a one-file change.

`git stash create -u "msg-u"` looks like the fix and is not. It exits 0 and prints a SHA, so a hook that trusted the exit code would silently ship nothing: `git log -1 --format=%s` on the result printed `On main: -u msg-u`, and `git rev-list --parents -n1` returned two parents rather than the three a `-u` stash carries. The `-u` was swallowed as message text. The synopsis in `git stash --help` is `git stash create [<message>]` — the subcommand takes no options at all.

What works is a throwaway index, which never touches the real one:

```sh
idx=$(mktemp -u); export GIT_INDEX_FILE="$idx"
git read-tree HEAD
git ls-files --others --exclude-standard -z | git update-index --add -z --stdin
git ls-files --modified --exclude-standard -z | git update-index --add -z --stdin
tree=$(git write-tree)
commit=$(git commit-tree "$tree" -p HEAD -m "blocked: <segment>")
rm -f "$idx"
git update-ref "refs/snapshots/<utc-timestamp>-<reason-slug>" "$commit"
```

`git ls-tree -r --name-only` on the result printed `.gitignore`, `sub/nested.txt`, `tracked.txt` and `untracked.txt`, and `git diff --stat HEAD <commit>` printed `3 files changed, 3 insertions(+), 1 deletion(-)`. Untracked and modified in one commit, no `git add -A`, explicit pathspecs only.

The gitignored `ignored.log` was absent, and that is the right coverage rather than a gap: `git clean -f` honours the standard ignore rules, so the snapshot covers exactly what the refused command would have deleted. `git clean -fx` reaches further — per `git-clean(1)`, `-x` means "don't use the standard ignore rules" — so that one form is snapshotted incompletely and its refusal text must say so.

## Recovery is git restore, not git stash apply

The earlier draft named `git stash apply <sha>` as the recovery. That is wrong for a temp-index commit: `git stash apply refs/snapshots/<ref>` printed `fatal: 'refs/snapshots/…' is not a stash-like commit`, because the commit has one parent, not the two or three `apply` expects.

The verified recovery is `git restore --source=<ref> --worktree -- .`. Round trip: deleting `untracked.txt` and `sub/`, and reverting `tracked.txt`, left `find` reporting only `.gitignore`, `ignored.log` and `tracked.txt`; after the restore, `git status --short` printed ` M tracked.txt`, `?? sub/` and `?? untracked.txt`, and the three files held `tracked-v2`, `nested` and `untracked-content` again.

## The hook blocks its own recovery command

`git checkout <ref> -- .` is the reflexive way to restore from a ref, and this hook refuses it. Running it against the snapshot ref produced `BLOCKED — destructive git command … git checkout -- <path> overwrites the working-tree copy with HEAD` — the `checkout` matcher fires on the bare `--` without checking whether a source ref precedes it, so a read-only restore reads as a discard.

Two things follow. The refusal text must offer the `git restore --source=` form, which the hook does not match and which was verified to work. Separately, the `checkout` matcher should learn to allow a `<tree-ish> --` form; that is a fix to the existing hook and is out of scope for this design.

## What the snapshot costs

Measured with `/usr/bin/time` on scratch repos, cold meaning the objects were not yet in the store.

| Working tree | Cold | Warm | Peak RSS |
|---|---|---|---|
| Clean (nothing to capture) | 0.01 s | — | — |
| 2000 untracked files, 24 MB | 0.66 s | 0.11 s | 5.2 MB |
| 10 untracked files, 250 MB | 6.64 s | — | 30 MB |

Throughput is roughly 38 MB/s, and the warm case is near-free because identical content hashes to the same SHA — the second run of the 2000-file snapshot returned the same commit id, `18cf0646…`, and the object store did not grow. Gitignored paths are excluded, so the usual blowup cases (`node_modules`, `out/`, `.venv`) never enter the count.

A clean tree needs an explicit check rather than an empty-output test. `git stash create` prints nothing on a clean tree, but the temp-index path still produces a commit whose tree equals `HEAD^{tree}` — verified equal on a clean repo. So the skip condition is comparing `git write-tree` against `git rev-parse HEAD^{tree}`, before `commit-tree`.

## Failure modes the implementation must honour

- A snapshot failure must never turn a refusal into an allow. Refuse first, snapshot best-effort, and check the tree rather than the exit code, since `stash create -u` proved an exit code can be 0 for a snapshot that captured nothing.
- Not a git repository, or a tree whose snapshot equals `HEAD^{tree}`: skip silently, still refuse.
- Give the snapshot a time budget and skip with a note in the refusal rather than blowing the PreToolUse timeout. At 38 MB/s the budget is the thing that matters for a large untracked tree.
- `refs/snapshots/` accumulates, and so do its objects — the 24 MB tree left a 17 MB `.git`. Prune with the existing weekly `dotfiles-prune` job: drop refs older than 90 days, keep at most 100, then let `git gc` reclaim the objects.

## Test plan

There is no test for this hook today, which is its own gap. `tests/test_block_destructive_git.sh` should feed the hook its JSON input in a scratch repo and assert: each blocked form still exits 2; a ref appears under `refs/snapshots/` and nothing appears in `git stash list`; the snapshot restores a deleted untracked file through `git restore --source=`; a gitignored file is absent from the snapshot tree; a clean tree creates no ref; a non-repo working directory still refuses; and a forced snapshot failure still refuses.

## Explicitly not proposed

- **Auto-stash and allow.** That changes policy from "refuse" to "permit with a net", and re-introduces the shared-stack hazard.
- **Snapshotting on every Bash call.** The cost is real and the benefit is confined to the handful of destructive forms.
- **Copying untracked files outside the repo**, to `~/.cache/` or similar. The temp index keeps everything in the object store, where `gc` already knows how to reclaim it.
