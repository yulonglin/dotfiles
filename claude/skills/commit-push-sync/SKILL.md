---
name: commit-push-sync
description: This skill should be used when the user asks to "commit and push", "commit push", "sync changes", "push changes", "commit and sync", or "update remote". Handles the full workflow of committing changes, pulling with rebase, and pushing to remote.
version: 0.2.0
---

# Commit, Smart Sync, and Push Workflow

Automates the complete workflow of committing local changes, syncing with remote using a context-aware pull strategy, and pushing updates.

## Purpose

Handle the full git workflow in a single command:
1. Stage and commit changes (following commit skill best practices)
2. Fetch and evaluate remote state
3. Sync with remote using the safest strategy for the situation
4. Push local commits to remote

## When to Use

Trigger this skill when the user requests:
- "commit and push"
- "commit push"
- "sync changes"
- "push changes" (after uncommitted work detected)
- "commit and sync"
- "update remote"

**Do NOT use** when:
- User only wants to commit (use `/commit` skill)
- User only wants to push existing commits (use direct `git push`)
- Working on a branch that shouldn't be pushed yet
- Conflicts are expected (handle manually)

## Workflow

### Step 1: Fetch and Evaluate State

**CRITICAL: Fetch first.** The local tracking ref (`@{u}`) is stale until you fetch. Without fetching, `git log ..@{u}` uses cached data and can miss remote changes.

First, check if upstream tracking exists and determine the correct remote:
```bash
UPSTREAM_REF=$(git rev-parse --abbrev-ref @{u} 2>/dev/null)
```

**If no upstream tracking branch (`UPSTREAM_REF` is empty):** Skip to Step 2 (commit), then push with `-u origin <branch>` in Step 4.

**If upstream exists**, extract the remote name and fetch it:
```bash
UPSTREAM_REMOTE=$(echo "$UPSTREAM_REF" | cut -d/ -f1)  # e.g., "origin" from "origin/main"
git fetch "$UPSTREAM_REMOTE"  # MUST succeed — abort entire workflow on failure
```

**IMPORTANT:** Always fetch the remote that `@{u}` actually points to, not hardcoded `origin`. A branch may track `upstream/main` or another remote — fetching the wrong remote leaves `@{u}` stale and causes incorrect state classification.

If fetch fails (network error, auth failure, etc.), **stop the entire workflow** and notify the user. Do not proceed with stale data.

**If upstream exists**, gather state (run in parallel):
```bash
git status                          # Uncommitted changes and branch info
git log @{u}.. --oneline            # Local-only commits (ahead count)
git log ..@{u} --oneline            # Remote-only commits (behind count)
git log @{u}.. --merges --oneline   # Merge commits in local history
```

Classify the state using the **Smart Pull Decision Tree**:

```
After git fetch origin:
+-- Local ahead, remote has nothing     -> just push (no pull needed)
+-- Local behind, no local commits      -> git pull --ff-only
+-- Diverged:
|   +-- Local has merge commits?        -> git pull --no-rebase (merge)
|   +-- >20 local commits to replay?    -> git pull --no-rebase (merge)
|   +-- Few commits, no merges          -> git pull --rebase
|   +-- Any pull fails?                 -> abort, show state, ask user
+-- @{u} not configured                 -> commit, git push -u origin <branch>
```

**Principle: rebase only when cheap and safe** (few commits, no merges). Otherwise merge. Never rebase merge commits — rebase drops them and replays their individual commits, causing massive conflicts.

### Step 2: Commit Changes (if needed)

If uncommitted changes exist, follow the commit skill workflow:

1. **Gather context** (run in parallel):
   ```bash
   git status              # See untracked files (NEVER use -uall flag)
   git diff --staged       # See staged changes
   git diff                # See unstaged changes
   git log -10 --oneline   # Recent commits for style reference
   ```

2. **Draft commit message**:
   - Summarize nature of changes (feature/fix/refactor/docs/etc.)
   - Focus on "why" rather than "what"
   - Match repository's commit style (from git log)
   - Keep concise (1-2 sentences)

3. **Stage and commit** (run sequentially):
   ```bash
   git add [specific files]  # Prefer specific files over "git add -A"

   # Sandbox-safe commit (NEVER use heredoc — sandbox blocks /tmp)
   # For multi-line messages:
   mkdir -p "$TMPDIR" && printf '%s\n' "subject line" "" "Body details here" > "$TMPDIR/commit_msg.txt" && git commit -F "$TMPDIR/commit_msg.txt"

   # For single-line messages:
   git commit -m "subject line"

   git status  # Verify commit succeeded
   ```

**Important commit rules** (from CLAUDE.md):
- NEVER skip hooks (no `--no-verify`)
- NEVER use `git add -A` or `git add .` (specify files to avoid secrets)
- NEVER commit secrets (.env, credentials.json, etc.)
- NEVER use heredoc (`<<EOF`) in commit commands (sandbox blocks `/tmp`)
- If pre-commit hook fails, create NEW commit after fixing (never `--amend`)

### Step 3: Sync with Remote (if needed)

**Based on the state classification from Step 1, choose the appropriate strategy:**

#### Case A: Local strictly ahead (no remote-only commits)

**Skip this step entirely.** Go straight to Step 4 (push). This is the most common case.

#### Case B: Local behind, no local commits (fast-forward)

```bash
git pull --ff-only
```

This cannot fail with conflicts. If it fails, something unexpected happened — abort and ask user.

#### Case C: Diverged — local has merge commits OR >20 local commits

**Use merge (not rebase)** to preserve merge commits and avoid replaying a large number of commits:

```bash
git pull --no-rebase
```

**Why not rebase here:** `git rebase` drops merge commits by default and replays their individual commits. A merge commit containing N upstream commits would expand into N individual replays, each potentially conflicting. This is how the 81-commit rebase disaster happens.

If merge conflicts occur:
1. **Immediately abort**: `git merge --abort`
2. Show the user the conflicting state: `git status`
3. Explain what diverged: show `git log @{u}.. --oneline` and `git log ..@{u} --oneline`
4. **Ask the user how to proceed** — do NOT auto-resolve

#### Case D: Diverged — few local commits (<= 20), no merge commits

**Rebase is safe here** — small, linear history is easy to replay:

```bash
git pull --rebase
```

If rebase conflicts occur:
1. **Immediately abort**: `git rebase --abort`
2. Show the user the conflicting state: `git status`
3. Explain what diverged
4. **Ask the user how to proceed** — do NOT auto-resolve

#### General conflict handling

- **NEVER attempt automatic conflict resolution** — always abort and ask user
- **NEVER continue a rebase/merge with unresolved conflicts**
- Show conflicting files with `git status`
- Provide guidance:
  - For rebase: resolve, `git add`, `git rebase --continue`, or `git rebase --abort`
  - For merge: resolve, `git add`, `git commit`, or `git merge --abort`

### Step 4: Push to Remote

Push commits to remote:

```bash
git push
```

**If no upstream tracking branch:**
```bash
git push -u origin <branch-name>
```
Ask user to confirm branch name before pushing.

**Handle push failures**:

| Error | Cause | Solution |
|-------|-------|----------|
| `rejected (non-fast-forward)` | Remote updated after our fetch | Re-fetch, re-evaluate state, sync again |
| `no upstream branch` | New branch never pushed | `git push -u origin <branch>` (confirm with user) |
| `protected branch` | Branch has push restrictions | Notify user (need PR or permissions) |

**Force push guidance**:
- NEVER suggest `git push --force` for main/master — warn the user if they request it
- For other branches, only suggest after explicit user request
- **Always use `--force-with-lease`** over `--force` — it checks that the remote hasn't been updated by someone else since your last fetch
- See `references/force-push-guidelines.md` for detailed guidance
- Warn: "Force push will overwrite remote history. `--force-with-lease` provides a safety check."

### Step 5: Verify Success

After successful push:
```bash
git status            # Should show "Your branch is up to date with 'origin/<branch>'"
git log -3 --oneline  # Show recent commits for confirmation
```

Output summary:
- "Committed: [commit message]" (if committed)
- "Synced: [N] commits from remote via [merge/rebase/fast-forward]" (if synced)
- "Pushed: [N] commits to origin/<branch>"

## Stash Workflow (Alternative Pattern)

For users with unstaged changes who prefer stash over committing. **Only use when remote actually has commits to pull** (check after fetch).

**WARNING:** `.claude/settings*.json` files cannot be stashed — the sandbox denies write/unlink on these files. If the working tree has dirty settings files:
1. Check if stash will fail: `git stash --dry-run 2>&1` (if this errors on settings files, skip stash)
2. Fallback: commit the non-settings dirty files first, then push directly
3. Or: just push if local is strictly ahead (stash is unnecessary)

```bash
git fetch origin

# Only if `git log ..@{u} --oneline` shows remote commits:
LOCAL_MERGES=$(git log @{u}.. --merges --oneline | wc -l)
LOCAL_COUNT=$(git log @{u}.. --oneline | wc -l)

git stash

if [ "$LOCAL_MERGES" -gt 0 ] || [ "$LOCAL_COUNT" -gt 20 ]; then
  git pull --no-rebase   # Preserve merge commits
else
  git pull --rebase      # Safe for small linear history
fi

git stash pop
```

**Handle stash pop conflicts**:
- Notify user about conflicts after stash pop
- Show conflicting files
- Provide guidance: resolve conflicts, then `git add [files]`
- No `git stash drop` until conflicts resolved

## Edge Cases

### Case 1: Detached HEAD

```bash
# Check if detached
git symbolic-ref -q HEAD || echo "Detached HEAD"
```

If detached, notify user: "Cannot push from detached HEAD. Create a branch first: `git checkout -b <branch-name>`"

### Case 2: No Remote Tracking Branch

Handled in Step 1 (detected by `git rev-parse --abbrev-ref @{u}`) and Step 4 (push with `-u`).

### Case 3: Diverged Branches with Merge Commits

This is the critical case that motivated the smart pull strategy. When local history contains merge commits (e.g., from `git merge upstream/main`):

- **NEVER rebase** — rebase drops the merge commit and replays all N individual commits from the merged branch
- **Always merge** — `git pull --no-rebase` preserves the merge commit intact
- Show the user: `git log @{u}.. --merges --oneline` to explain why merge was chosen

### Case 4: Nothing to Commit or Push

```bash
git status                 # "nothing to commit, working tree clean"
git log @{u}.. --oneline   # No output = no unpushed commits
```

Notify user: "No changes to commit or push. Working tree is clean and up to date."

### Case 5: Fetch Fails

If `git fetch origin` fails:
- **Abort the entire workflow** — do not proceed with stale tracking refs
- Show the error to the user
- Common causes: network issues, auth expired, remote renamed/deleted

## Common Mistakes to Avoid

**Don't:**
- Run `git add -A` or `git add .` (risk committing secrets)
- Use `--no-verify` to skip hooks
- Force push to main/master without explicit request
- Auto-resolve merge conflicts (always involve user)
- Amend commits after hook failures
- Skip verification steps
- Use heredoc (`<<EOF`) in commit commands (sandbox blocks `/tmp`)
- Rebase when local history contains merge commits
- Rebase >20 commits without warning the user
- Use `--force` when `--force-with-lease` is available

**Do:**
- Stage specific files by name
- Choose pull strategy based on local history (merge commits? commit count?)
- Let hooks run (respect pre-commit checks)
- Create new commits after hook failures
- Use `$TMPDIR` for commit message files
- Verify success with `git status`
- Handle errors gracefully with clear user guidance
- Use `--force-with-lease` over `--force` when force push is needed

## Integration with Rules

This skill follows the smart pull strategy from `rules/safety-and-git.md`:

**Context-aware pull strategy** (not unconditional rebase):
- Rebase only when cheap and safe (few commits, no merges)
- Merge when local has merge commits or many commits
- Fast-forward when local has no work
- Skip pull entirely when local is strictly ahead

**Git Safety Protocol**:
- Never update git config
- Never run destructive commands (--force push to main)
- Never skip hooks
- Always create new commits (not amend after failures)
- Prefer specific file staging

**Sandbox-safe commits**:
- Use `printf` + `git commit -F` for multi-line messages
- Use `-m` for single-line messages
- Never use heredoc (`<<EOF`) in commit commands

## Additional Resources

### Reference Files

For detailed guidance:
- **`references/conflict-resolution.md`** - Handling merge conflicts during rebase or merge
- **`references/force-push-guidelines.md`** - When and how to force push safely

### Related Skills

- **`/commit`** - Just commit workflow (no push)
- Standard git commands for manual control

## Quick Command Reference

```bash
# ALWAYS fetch the correct remote first (matches @{u})
UPSTREAM_REMOTE=$(git rev-parse --abbrev-ref @{u} 2>/dev/null | cut -d/ -f1)
git fetch "${UPSTREAM_REMOTE:-origin}"

# Check state AFTER fetch
git status
git log @{u}.. --oneline            # Unpushed local commits
git log ..@{u} --oneline            # Remote-only commits to pull
git log @{u}.. --merges --oneline   # Merge commits in local history

# Decision tree:
# Local strictly ahead (no remote-only commits) — just push
git push

# Local behind only (no local commits) — fast-forward
git pull --ff-only && git push

# Diverged with merge commits or >20 local commits — merge
git pull --no-rebase && git push

# Diverged with few commits, no merges — rebase
git pull --rebase && git push

# No upstream tracking — set it
git push -u origin <branch>

# Sandbox-safe commit (multi-line)
mkdir -p "$TMPDIR" && printf '%s\n' "subject" "" "body" > "$TMPDIR/commit_msg.txt" && git commit -F "$TMPDIR/commit_msg.txt"

# Verify success
git status  # Should show "up to date with origin/<branch>"
git log -3 --oneline
```

## Success Criteria

A successful commit-push-sync completes when:
1. All changes are committed (if any uncommitted work existed)
2. Remote changes are synced using the appropriate strategy (if any remote updates existed)
3. Local commits are pushed to remote
4. `git status` shows "Your branch is up to date with 'origin/<branch>'"
5. No conflicts or errors remain unresolved
6. Merge commits in local history are preserved (not flattened by rebase)

If any step fails, provide clear guidance and stop — don't proceed to next step until user resolves the issue.
