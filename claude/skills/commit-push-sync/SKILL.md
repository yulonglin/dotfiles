---
name: commit-push-sync
description: This skill should be used when the user asks to "commit and push", "commit push", "sync changes", "push changes", "commit and sync", or "update remote". Handles the full workflow of committing changes, pulling with rebase, and pushing to remote.
version: 0.2.0
---

# Commit, Smart Sync, and Push Workflow

Commit local changes, sync with the remote using a context-aware strategy, then push. Use `/commit` instead when the user only wants a commit.

## Fetch The Tracked Remote Before Judging State

`@{u}` is stale until you fetch, so `git log ..@{u}` on cached data can miss remote commits entirely.

- `UPSTREAM_REF=$(git rev-parse --abbrev-ref @{u} 2>/dev/null)` — empty means no upstream: skip to committing, then push with `-u` (Step 4).
- Fetch the remote `@{u}` actually names, never a hardcoded `origin` — a branch may track `upstream/main`, and fetching the wrong remote leaves `@{u}` stale and misclassifies the state: `git fetch "$(echo "$UPSTREAM_REF" | cut -d/ -f1)"`.
- **If the fetch fails, abort the whole workflow** and show the user the error. Never proceed on stale refs. Common causes: network, expired auth, renamed/deleted remote.
- Detached HEAD (`git symbolic-ref -q HEAD` fails) cannot be pushed — tell the user to `git checkout -b <branch>` first.

Then gather state in parallel: `git status`, `git log @{u}.. --oneline` (local-only), `git log ..@{u} --oneline` (remote-only), `git log @{u}.. --merges --oneline` (local merge commits).

## Rebase Only When Cheap And Safe, Otherwise Merge

```
After fetching the tracked remote:
+-- Local ahead, remote has nothing     -> just push (no pull)
+-- Local behind, no local commits      -> git pull --ff-only
+-- Diverged:
|   +-- Local has merge commits?        -> git pull --no-rebase
|   +-- >20 local commits to replay?    -> git pull --no-rebase
|   +-- Few commits, no merges          -> git pull --rebase
|   +-- Any pull fails?                 -> abort, show state, ask user
+-- @{u} not configured                 -> commit, git push -u origin <branch>
```

Never rebase across merge commits: rebase drops the merge and replays its N constituent commits individually, each able to conflict — that is how an 81-commit rebase disaster happens. Show `git log @{u}.. --merges --oneline` when explaining why merge was chosen. `--ff-only` cannot conflict; if it fails, something unexpected happened — abort and ask.

## Triage Untracked Paths Before Staging Them

Gather context in parallel first: `git status` (never `-uall`), `git diff --staged`, `git diff`, `git log -10 --oneline` for style. Coding agents accrete runtime state, caches, job queues and control keys over time — for each *newly appeared* untracked path ask whether it is worth versioning and sharing across machines.

| Signal | Action |
|--------|--------|
| Machine-local runtime state, regenerated on the fly (caches, session dirs, queues, daemon/job state) | Add to `.gitignore` — don't commit |
| Contains a credential or secret (tokens, `*.key`, control keys) | Add to `.gitignore` **and** verify it never entered history |
| Server-pushed state that re-syncs itself (policy / remote-settings files) | Add to `.gitignore` — versioning it is churn plus conflicts |
| Genuine config or source meant to be shared (settings, rules, agents, scripts) | Stage and commit normally |

When unsure whether a path is durable config or agent scaffold, **ask the user**. Put the pattern in the nearest relevant `.gitignore` and confirm with `git check-ignore <path>`; if the scaffold is already tracked, `git rm --cached <path>` first (keeps the working copy).

## Commit Without Heredocs, And Never Amend Past A Hook

Message: name the nature of the change, say *why* rather than *what*, match the repo's style from `git log`, keep it to 1-2 sentences.

```bash
git add <specific files>   # never `git add -A` / `git add .` — risks committing secrets

# Multi-line message. NEVER a heredoc: the sandbox blocks the shell's /tmp scratch file,
# which yields an EMPTY commit message and a failed commit.
mkdir -p "$TMPDIR" && printf '%s\n' "subject" "" "body" > "$TMPDIR/commit_msg.txt" && git commit -F "$TMPDIR/commit_msg.txt"

git commit -m "subject"    # single-line messages only
git status                 # verify the commit landed
```

Never `--no-verify` — let hooks run. If a pre-commit hook fails, fix and make a **new** commit; never `--amend`.

## A Failed Pull Can Silently Revert Your Files

A failed `git pull --rebase` or `--no-rebase` leaves the working tree in a MIXED state: cleanly-merged files keep the remote's version while conflicted ones get restored, so the abort restores HEAD but not necessarily the tree. This is the top source of silent regressions (it caused the 2026-04-03 `profiles.yaml` loss, where the remote's old file was staged and committed as a "sync").

After **any** failed pull:

- STOP. Do not stage or commit dirty files.
- Diff every dirty file against **the commit you just made**, not HEAD, which may be wrong after the abort.
- If a diff shows your own recent additions being removed or renames reverted, the tree is contaminated: `git checkout <your-commit-hash> -- <contaminated-files>`.
- If unsure, ask the user whether to restore from the commit or keep the current state.

## Abort Conflicts And Hand Them To The User

Never auto-resolve, and never continue a rebase or merge with unresolved conflicts. Abort immediately (`git rebase --abort` / `git merge --abort`), show `git status` and both `git log @{u}.. --oneline` and `git log ..@{u} --oneline` to explain the divergence, then ask how to proceed. Guidance to offer: rebase → resolve, `git add`, `git rebase --continue`; merge → resolve, `git add`, `git commit`. Detail in `references/conflict-resolution.md`.

`.claude/settings*.json` cannot be stashed — the sandbox denies write and unlink on them. With dirty settings files, commit the non-settings changes and push directly instead of stashing.

## Push, Then Confirm The Branch Is Up To Date

`git push`, or `git push -u origin <branch-name>` with the branch name confirmed by the user when there is no upstream.

| Error | Cause | Response |
|-------|-------|----------|
| `rejected (non-fast-forward)` | Remote moved after our fetch | Re-fetch, re-classify state, sync again — not force |
| `no upstream branch` | New branch never pushed | `git push -u origin <branch>` after confirming with the user |
| `protected branch` | Push restrictions | Notify the user; a PR or extra permissions is needed |

Verify with `git status` ("up to date with 'origin/<branch>'") and `git log -3 --oneline`. Report what was committed, what was synced and by which strategy, and how many commits were pushed. If any step fails, stop and hand the problem to the user rather than continuing.

## Force-Push With Lease, Never To Main

Never suggest force-pushing `main`/`master` — warn if asked. On other branches, only after an explicit user request, and always `--force-with-lease` over `--force` so the push fails if someone else updated the remote since your fetch. Warn that history will be overwritten. Detail in `references/force-push-guidelines.md`.

The pull strategy here implements `rules/safety.md`; never update git config, and never run destructive git commands unasked.
