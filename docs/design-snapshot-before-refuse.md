# Snapshot before refusing a destructive git command

Status: design for review, 2026-09-11. Not implemented.

## What exists today

`claude/hooks/block_destructive_git.sh` (153 lines) is a PreToolUse Bash hook. It splits compound commands into segments, and `deny()` exits 2 with a reason and a suggested alternative. It refuses `git reset --hard`, `git checkout -- <path>`, `git checkout .`, `git clean -f`, bare `git stash` and `git stash pop`.

## Why add a snapshot

The refusal protects work by preventing the command, which is the right default and should stay. But it protects nothing once the command is reworded into a form the matcher does not catch — `git restore --worktree <path>`, `git checkout HEAD -- <path>` and `git reset --keep` all discard uncommitted work and none are blocked today. A snapshot turns the caught cases into recoverable ones, and costs nothing when it is never needed.

## The mechanism: a snapshot that never touches the shared stash stack

`git stash create [<message>]` builds a stash commit object and prints its SHA **without** storing a ref, touching the working tree, or pushing onto the stack. `git stash store` can file it later. That matters here because this repo's rules already name the hazard: the stash stack is shared across every worktree, so an auto-`git stash push` could be popped by another session.

So, before `deny()` returns:

1. `sha=$(git stash create "blocked: <segment>")` — empty output means a clean tree, so skip.
2. `git update-ref refs/snapshots/<utc-timestamp>-<reason-slug> "$sha"` — files it where nothing else looks, invisible to `git stash list`.
3. The refusal message names the recovery: `git stash apply <sha>`.

## The untracked-file gap needs a decision

`stash create` captures tracked modifications only. `git clean -f` destroys **untracked** files exclusively — so for the one command where recovery matters most, the snapshot would capture nothing. Three options:

- **(a) Accept the gap** and say so plainly in the `clean -f` refusal. Cheapest, honest, leaves the worst case uncovered.
- **(b) Temp-index snapshot.** Point `GIT_INDEX_FILE` at a throwaway index, stage the untracked files, `write-tree`, then `commit-tree`. Covers untracked files without touching the real index or the stash stack. Stage them from an explicit list — `git ls-files --others --exclude-standard` — and never `git add -A`, which under the sandbox stages denied paths as phantom character devices (already a documented rule in `claude/rules/safety.md`).
- **(c) Copy untracked files** to `~/.cache/claude/git-snapshots/`. Simple, but puts repo content outside the repo and needs its own cleanup.

Lean: **(b) with the explicit pathspec**, falling back to (a) when the file list is empty.

## Failure modes the implementation must honour

- A snapshot failure must **never** turn a refusal into an allow. Refuse first, snapshot best-effort.
- Not a git repository, or a clean tree: skip silently, still refuse.
- Hook latency is bounded by the PreToolUse timeout. Snapshot cost scales with the diff, so give it a time budget and skip with a note in the refusal rather than blowing the timeout on a huge tree.
- `refs/snapshots/` accumulates. Prune with the existing weekly `dotfiles-prune` job: drop refs older than 90 days, keep at most 100.

## Test plan

There is no test for this hook today, which is its own gap. `tests/test_block_destructive_git.sh` should feed the hook its JSON input in a scratch repo and assert: each blocked form still exits 2; a ref appears under `refs/snapshots/`; the snapshot actually restores the discarded modification; a clean tree creates no ref; a non-repo working directory still refuses; and a forced snapshot failure still refuses.

## Explicitly not proposed

- **Auto-stash and allow.** That changes policy from "refuse" to "permit with a net", and re-introduces the shared-stack hazard.
- **Snapshotting on every Bash call.** The cost is real and the benefit is confined to the handful of destructive forms.
