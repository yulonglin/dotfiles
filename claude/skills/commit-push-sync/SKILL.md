---
name: commit-push-sync
description: This skill should be used when the user asks to "commit and push", "commit push", "sync changes", "push changes", "commit and sync", or "update remote". Handles the full workflow of committing changes, pulling with rebase, and pushing to remote.
version: 0.1.0
---

# Commit, Pull Rebase, and Push Workflow

Automates the complete workflow of committing local changes, syncing with remote (pull rebase), and pushing updates. Extends the commit skill with remote synchronization.

## Purpose

Handle the full git workflow in a single command:
1. Stage and commit changes (following commit skill best practices)
2. Pull remote changes with rebase to maintain linear history
3. Push local commits to remote

This eliminates manual steps and ensures proper rebase workflow (as specified in CLAUDE.md Git Commands section).

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

### Step 1: Check Current State

Run in parallel:
```bash
git status  # Check for uncommitted changes and branch info
git log @{u}.. --oneline  # Check for unpushed commits
git log ..@{u} --oneline  # Check for remote commits to pull
```

Analyze the state:
- **Uncommitted changes + no unpushed commits**: Need to commit first
- **No uncommitted changes + unpushed commits**: Skip to pull-rebase-push
- **Uncommitted changes + unpushed commits**: Commit, then pull-rebase-push
- **No changes either way**: Nothing to do, notify user

### Step 2: Commit Changes (if needed)

If uncommitted changes exist, follow the commit skill workflow:

1. **Gather context** (run in parallel):
   ```bash
   git status  # See untracked files (NEVER use -uall flag)
   git diff --staged  # See staged changes
   git diff  # See unstaged changes
   git log -10 --oneline  # Recent commits for style reference
   ```

2. **Draft commit message**:
   - Summarize nature of changes (feature/fix/refactor/docs/etc.)
   - Focus on "why" rather than "what"
   - Match repository's commit style (from git log)
   - Keep concise (1-2 sentences)

3. **Stage and commit** (run sequentially):
   ```bash
   git add [specific files]  # Prefer specific files over "git add -A"
   git commit -m "$(cat <<'EOF'
   Commit message here.
   EOF
   )"
   git status  # Verify commit succeeded
   ```

**Important commit rules** (from CLAUDE.md):
- NEVER skip hooks (no `--no-verify`)
- NEVER use `git add -A` or `git add .` (specify files to avoid secrets)
- NEVER commit secrets (.env, credentials.json, etc.)
- If pre-commit hook fails, create NEW commit after fixing (never `--amend`)
- Use HEREDOC for commit messages (ensures proper formatting)

### Step 3: Pull with Rebase

Pull remote changes using rebase (CLAUDE.md default):

```bash
git pull --rebase
```

**Handle conflicts** (if any):
- Notify user about conflicts
- Show conflicting files: `git status`
- Provide guidance:
  - Fix conflicts manually
  - Run `git add [resolved-files]`
  - Continue: `git rebase --continue`
  - Or abort: `git rebase --abort`
- **Do NOT attempt automatic conflict resolution**

**If pull succeeds** (no conflicts):
- Proceed to push
- Note if commits were rebased (check output for "Successfully rebased")

### Step 4: Push to Remote

Push commits to remote:

```bash
git push
```

**Handle push failures**:

| Error | Cause | Solution |
|-------|-------|----------|
| `rejected (non-fast-forward)` | Remote has new commits | Pull rebase again, then push |
| `rejected (fetch first)` | Remote branch updated | Pull rebase again |
| `no upstream branch` | New branch never pushed | Ask user: `git push -u origin <branch>` |
| `protected branch` | Branch has push restrictions | Notify user (need PR or permissions) |

**Force push warning**:
- NEVER suggest `git push --force` for main/master
- For other branches, only suggest after explicit user request
- Warn: "Force push will overwrite remote history"

### Step 5: Verify Success

After successful push:
```bash
git status  # Should show "Your branch is up to date with 'origin/<branch>'"
git log -3 --oneline  # Show recent commits for confirmation
```

Output summary:
- "✓ Committed: [commit message]" (if committed)
- "✓ Pulled: [N] commits from remote" (if pulled any)
- "✓ Pushed: [N] commits to origin/<branch>"

## Stash Workflow (Alternative Pattern)

For users with unstaged changes who prefer stash:

```bash
git stash && git pull --rebase && git stash pop
```

**When to use stash approach**:
- User has uncommitted changes they're not ready to commit
- User explicitly requests stash workflow
- Quick sync needed without finalizing commit message

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

# If detached, notify user
echo "Cannot push from detached HEAD. Create a branch first:"
echo "  git checkout -b <branch-name>"
```

### Case 2: No Remote Tracking Branch

```bash
# First push of new branch
git push -u origin <branch-name>
```

Ask user to confirm branch name before pushing.

### Case 3: Diverged Branches

```bash
# Local and remote have diverged
git status  # Shows "have diverged"
```

Notify user:
- Local has commits not in remote
- Remote has commits not in local
- Need to decide: rebase or merge
- Suggest: Review divergence with `git log --oneline --graph --all -10`

### Case 4: Nothing to Commit or Push

```bash
git status  # "nothing to commit, working tree clean"
git log @{u}.. --oneline  # No output = no unpushed commits
```

Notify user: "No changes to commit or push. Working tree is clean and up to date."

## Common Mistakes to Avoid

❌ **Don't:**
- Run `git add -A` or `git add .` (risk committing secrets)
- Use `--no-verify` to skip hooks
- Force push to main/master without explicit request
- Auto-resolve merge conflicts (always involve user)
- Amend commits after hook failures
- Skip verification steps

✅ **Do:**
- Stage specific files by name
- Use rebase for pull (linear history)
- Let hooks run (respect pre-commit checks)
- Create new commits after hook failures
- Verify success with `git status`
- Handle errors gracefully with clear user guidance

## Integration with CLAUDE.md Rules

This skill follows CLAUDE.md Git Commands guidelines:

**Prefer rebase over merge**:
- `git pull --rebase` maintains linear history
- Default behavior when user says "pull"

**Handle unstaged changes**:
- Stash workflow: `git stash && git pull --rebase && git stash pop`
- Commit workflow: Commit first, then pull-rebase-push

**Git Safety Protocol**:
- Never update git config
- Never run destructive commands (--force push to main)
- Never skip hooks
- Always create new commits (not amend after failures)
- Prefer specific file staging

**Commit process**:
- Check `git status` (no -uall flag)
- Check `git diff` for staged/unstaged changes
- Check `git log` for commit style
- Draft message focusing on "why"
- Use HEREDOC for commit message formatting
- Verify with `git status` after commit

## Additional Resources

### Reference Files

For detailed guidance:
- **`references/conflict-resolution.md`** - Handling merge conflicts during rebase
- **`references/force-push-guidelines.md`** - When and how to force push safely

### Related Skills

- **`/commit`** - Just commit workflow (no push)
- Standard git commands for manual control

## Quick Command Reference

```bash
# Full workflow (no uncommitted changes)
git pull --rebase && git push

# Full workflow (with uncommitted changes - stash approach)
git stash && git pull --rebase && git stash pop && git push

# Full workflow (with uncommitted changes - commit approach)
git add [files] && git commit -m "message" && git pull --rebase && git push

# Check state before starting
git status
git log @{u}.. --oneline  # Unpushed local commits
git log ..@{u} --oneline  # Remote commits to pull

# Verify success
git status  # Should show "up to date with origin/<branch>"
git log -3 --oneline
```

## Success Criteria

A successful commit-push-sync completes when:
1. All changes are committed (if any uncommitted work existed)
2. Remote changes are pulled and rebased (if any remote updates existed)
3. Local commits are pushed to remote
4. `git status` shows "Your branch is up to date with 'origin/<branch>'"
5. No conflicts or errors remain unresolved

If any step fails, provide clear guidance and stop—don't proceed to next step until user resolves the issue.
