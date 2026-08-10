---
name: merge-worktree
description: Merge current worktree branch into the original branch, resolve conflicts with AI, then mark worktree for cleanup. Use when the user says "merge this worktree", "merge my branch back", or "finish this worktree."
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
- `PARENT_BRANCH`: branch checked out in the main worktree (the target for the local-merge path only)
- `PR_BASE_BRANCH`: the branch this worktree was actually based on (the target for the PR path; **never infer this from whatever the main worktree happens to have checked out now**)

If NOT in a worktree, tell the user and exit. This skill is designed to run from inside a worktree session.

### 2. Pre-merge Check

```bash
# Ensure all changes are committed in the worktree
git status --porcelain
```

If there are uncommitted changes:
- **`.claude/settings.json`**: This file is auto-managed by Claude Code at runtime. Deep-compare (parse JSON, compare key-value pairs ignoring order) against the committed version. If semantically equivalent, `git restore` it. If there are real value differences, `git restore` it anyway — runtime settings changes are ephemeral and should not be merged.
- **Other files**: Commit them first using the `/commit` skill or ask the user.

### 3. Commit Plan Files

Plan files are versioned artifacts that should travel with the branch. Before merging, ensure any plan files created during this worktree session are committed.

```bash
# Check for untracked or modified plan files
PLANS_DIR=$(git rev-parse --show-toplevel)/plans
if [ -d "$PLANS_DIR" ]; then
  git status --porcelain "$PLANS_DIR"
fi
```

If there are uncommitted plan files:
1. Stage them: `git add plans/`
2. Commit with message: `chore: commit plan files from worktree session`

This prevents plan files from being orphaned when the worktree is removed (gitignored files and untracked files don't survive `cwrm`).

### 4. Check Commits to Merge

```bash
# Local-merge path: compare with the main worktree's checked-out target
git rev-list --count <PARENT_BRANCH>..<WORKTREE_BRANCH>

# PR path: after PR_BASE_BRANCH is established in Step 5, compare with that
git rev-list --count <PR_BASE_BRANCH>..<WORKTREE_BRANCH>
```

Use the count for the integration path being taken. Do not conclude "Already up to date" for a PR by comparing against `PARENT_BRANCH`: a stacked branch's actual base may differ from whatever the main worktree currently has checked out. If the relevant count is 0, report "Already up to date" and exit.

### 5. Choose Integration Path (PR by default)

**PR-convention check — decide this BEFORE any main-tree checks.** A direct local merge is the trivial/mechanical path only (typo, version bump, doc touch-up). For a reviewable change, the convention is to push the worktree branch and open a PR instead — offer that as the default and merge locally only if the user picks it or the diff is genuinely trivial. See the repo's CLAUDE.md Top Rules.

Before opening a PR, determine `PR_BASE_BRANCH` independently of `PARENT_BRANCH`:

- If the branch is already tracked by `gh stack`, use `gh stack submit`, report the resulting stack/PR URLs, and stop; do not also run `gh pr create`.
- If a PR already exists, preserve its base (`gh pr view <WORKTREE_BRANCH> --json baseRefName --jq .baseRefName`), push the branch, report/update that PR, and stop; do not create a duplicate.
- Only for a new unstacked branch: use the branch-creation record from this session or an unambiguous creation reflog entry, then verify the candidate is an ancestor of `<WORKTREE_BRANCH>`. Git does not durably record an arbitrary branch's parent, so if the evidence is missing or ambiguous, ask the user to choose the base; **never substitute the main worktree's currently checked-out branch**. Then create the PR with the command below.

The PR path only pushes the isolated worktree branch and never touches the main tree, so an unrelated dirty main checkout must NOT block it:

```bash
git push -u origin <WORKTREE_BRANCH>
gh pr create --draft --base <PR_BASE_BRANCH> --title "<title>" --body-file <file>
```

Pass `--base <PR_BASE_BRANCH>` explicitly — without it, gh targets the repository's default branch, so a worktree stacked on another feature branch would open a PR that includes the parent branch's commits (for a stack, `gh stack` also works). Pass BOTH `--title` and `--body-file` explicitly — without a title, gh prompts interactively and hangs a non-interactive run; the body carries what AGENTS.md requires (commands run, host, risk assessment). Then report the PR URL and stop — the worktree stays for review follow-ups; skip steps 6-8.

### 6. Attempt Merge (local path only)

Before merging, verify the main tree has no uncommitted changes — this check gates only this local-merge path, not the PR path above:

```bash
git -C <MAIN_TREE_PATH> status --porcelain
```

If the main tree has uncommitted changes, warn the user and ask them to commit or stash first. Do NOT proceed with the merge — it will mix their uncommitted work with the merge result.

Run the merge from the main tree:

```bash
git -C <MAIN_TREE_PATH> merge --no-edit <WORKTREE_BRANCH>
```

**If merge succeeds:** Report success with commit count, skip to step 8.

**If merge fails (conflicts):** Continue to step 7.

### 7. Resolve Conflicts

Do NOT abort the merge. Instead:

1. List conflicting files:
   ```bash
   git -C <MAIN_TREE_PATH> diff --name-only --diff-filter=U
   ```

2. For each conflicting file:
   - Read the file (it has conflict markers `<<<<<<<`, `=======`, `>>>>>>>`)
   - Read the worktree's version: `git show <WORKTREE_BRANCH>:<file>`
   - Read the parent branch's version: `git show <PARENT_BRANCH>:<file>`
   - **For JSON files** (`.claude/settings.json`, etc.): do a deep comparison — parse both sides and check if the actual key-value pairs are semantically equivalent (ignoring key ordering, whitespace). If equivalent, keep the parent branch's version. Only treat as a real conflict if values differ.
   - **For other files**: resolve the conflict by understanding both sides' intent
   - Write the resolved file
   - Stage it: `git -C <MAIN_TREE_PATH> add <file>`

3. After all conflicts resolved:
   ```bash
   git -C <MAIN_TREE_PATH> commit --no-edit
   ```

4. If you cannot confidently resolve a conflict, leave it and tell the user which files need manual attention.

### 8. Mark for Cleanup

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
- **Main tree uncommitted changes** are checked in step 6 before a local merge — do not skip this check (the PR path in step 5 doesn't need it)
