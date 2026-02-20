---
name: merge-worktree
description: Merge current worktree branch into the original branch, resolve conflicts with AI, then mark worktree for cleanup
---

# Merge Worktree

Merge the current worktree's branch into the original (parent) branch. Resolves merge conflicts intelligently. Marks the worktree for cleanup after successful merge.

## Instructions

### 1. Detect Context

Run these commands to understand the current state:

```bash
# Are we in a worktree?
git rev-parse --git-common-dir
git rev-parse --git-dir
git rev-parse --show-toplevel

# Current branch (should be worktree-<name>)
git rev-parse --abbrev-ref HEAD

# Find main worktree path
git worktree list --porcelain
```

**Determine:**
- `WORKTREE_NAME`: extracted from current branch (strip `worktree-` prefix) or directory name
- `WORKTREE_BRANCH`: current branch (e.g., `worktree-bold-fox-gjac`)
- `MAIN_TREE_PATH`: path of the main worktree (first entry in `git worktree list`)
- `PARENT_BRANCH`: branch checked out in the main worktree

If NOT in a worktree, tell the user and exit. This skill is designed to run from inside a worktree session.

### 2. Pre-merge Check

```bash
# Ensure all changes are committed in the worktree
git status --porcelain
```

If there are uncommitted changes, commit them first using the `/commit` skill or ask the user.

```bash
# Check how many commits to merge
git rev-list --count <PARENT_BRANCH>..<WORKTREE_BRANCH>
```

If 0 commits ahead, report "Already up to date" and exit.

### 3. Attempt Merge

Run the merge from the main tree:

```bash
git -C <MAIN_TREE_PATH> merge --no-edit <WORKTREE_BRANCH>
```

**If merge succeeds:** Report success with commit count, skip to step 5.

**If merge fails (conflicts):** Continue to step 4.

### 4. Resolve Conflicts

Do NOT abort the merge. Instead:

1. List conflicting files:
   ```bash
   git -C <MAIN_TREE_PATH> diff --name-only --diff-filter=U
   ```

2. For each conflicting file:
   - Read the file (it has conflict markers `<<<<<<<`, `=======`, `>>>>>>>`)
   - Read the worktree's version: `git show <WORKTREE_BRANCH>:<file>`
   - Read the parent branch's version: `git show <PARENT_BRANCH>:<file>`
   - **Resolve the conflict** by understanding both sides' intent
   - Write the resolved file
   - Stage it: `git -C <MAIN_TREE_PATH> add <file>`

3. After all conflicts resolved:
   ```bash
   git -C <MAIN_TREE_PATH> commit --no-edit
   ```

4. If you cannot confidently resolve a conflict, leave it and tell the user which files need manual attention.

### 5. Mark for Cleanup

After successful merge, tell the user:

```
Merged <N> commit(s) from <WORKTREE_BRANCH> into <PARENT_BRANCH>.

This worktree is now safe to remove:
  cwrm --no-merge <WORKTREE_NAME>

Or continue working — run /merge-worktree again later to sync new commits.
```

## Important

- **Never force-push or rebase** the parent branch
- **Never delete the worktree branch** — `cwrm` handles that
- **Prefer the worktree's version** when both sides changed the same thing and intent is unclear (the worktree has the newer work)
- **If the main tree has uncommitted changes**, warn the user and ask them to commit or stash first before merging
