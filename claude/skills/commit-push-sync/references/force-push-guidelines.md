# Force Push Guidelines

Detailed guidance for when and how to safely use `git push --force` (and its safer variant `--force-with-lease`).

## When Force Push Is Needed

Force push overwrites remote history. Use only when:

1. **Amending pushed commits** (typo in commit message, forgot file)
2. **Rebasing pushed branch** (cleaning up feature branch history)
3. **Squashing commits** before merge (interactive rebase)
4. **Removing sensitive data** (committed secrets, large files)
5. **Fixing mistakes** (committed to wrong branch, wrong changes)

**NEVER force push to**:
- `main` or `master` branch
- Any shared/protected branch
- Branches others are working on

## Force Push Variants

### `git push --force`

**What it does**: Overwrites remote with local state, regardless of remote changes.

**Danger**: If someone else pushed between your last fetch and force push, their changes are LOST.

**Use when**:
- Working alone on feature branch
- Absolutely certain no one else has pushed

### `git push --force-with-lease` (PREFERRED)

**What it does**: Overwrites remote ONLY if remote matches expected state (your last fetch).

**Safety**: If someone else pushed after your last fetch, push is rejected (protects their work).

**Use when**:
- Any force push situation
- Any chance someone else might have pushed
- **This should be your default force push command**

**Example**:
```bash
# Fetch first to update remote refs
git fetch

# Force push with lease (safe)
git push --force-with-lease

# If rejected: someone else pushed, pull first
git pull --rebase
git push
```

### `git push --force-if-includes` (Most Conservative)

**What it does**: Force push ONLY if remote changes are included in local history.

**Safety**: Ensures you've integrated others' work before force pushing.

**Use when**:
- Shared feature branch with multiple contributors
- Maximum safety needed

**Requires**: Git 2.30+ and `fetch.writeCommitGraph = true`

## Pre-Force Push Checklist

Before any force push:

- [ ] Verify branch name: `git branch --show-current`
- [ ] NOT main/master: Check it's a feature branch
- [ ] Fetch first: `git fetch`
- [ ] Check remote state: `git log origin/<branch> -5 --oneline`
- [ ] Verify no one else pushed: Compare timestamps
- [ ] Review changes being pushed: `git log origin/<branch>..HEAD`
- [ ] Backup if unsure: `git branch backup-$(date +%s)`
- [ ] Use `--force-with-lease` not `--force`

## Common Force Push Scenarios

### Scenario 1: Amend Last Commit

**Situation**: Forgot to include file or typo in commit message.

```bash
# Make additional changes
git add forgotten-file.py

# Amend last commit
git commit --amend

# Force push (safe if branch is yours)
git push --force-with-lease
```

**Warning**: Only amend if commit NOT pushed to main/master or shared branch.

### Scenario 2: Rebase Feature Branch

**Situation**: Want to clean up commit history before merging.

```bash
# Fetch latest main
git fetch origin main

# Rebase feature branch onto main
git rebase origin/main

# If conflicts, resolve and continue
git rebase --continue

# Force push rebased branch
git push --force-with-lease
```

**Impact**: Changes commit hashes (rewrites history).

### Scenario 3: Interactive Rebase (Squash Commits)

**Situation**: Combine multiple "WIP" commits into clean history.

```bash
# Interactive rebase last 5 commits
git rebase -i HEAD~5

# In editor: change "pick" to "squash" for commits to combine
# Save and exit

# Force push squashed commits
git push --force-with-lease
```

**Result**: Multiple commits → fewer, cleaner commits.

### Scenario 4: Remove Sensitive Data

**Situation**: Accidentally committed API key or password.

```bash
# Remove file from all history
git filter-branch --force --index-filter \
  "git rm --cached --ignore-unmatch path/to/secret.env" \
  --prune-empty --tag-name-filter cat -- --all

# Or use BFG Repo Cleaner (faster)
bfg --delete-files secret.env

# Force push cleaned history
git push --force-with-lease --all
```

**Critical**: Rotate compromised credentials immediately—history rewrite doesn't revoke access.

### Scenario 5: Fix Wrong Branch Commit

**Situation**: Committed to `main` instead of feature branch.

```bash
# Create branch from current main
git branch feature-branch

# Reset main to before mistake
git reset --hard origin/main

# Switch to feature branch
git checkout feature-branch

# Force push main back to correct state
git checkout main
git push --force-with-lease

# Push feature branch normally
git checkout feature-branch
git push -u origin feature-branch
```

## Force Push to Main (NEVER DO THIS)

**Why it's dangerous**:
1. **Destroys team's work**: Anyone who pulled before your force push has diverged history
2. **Breaks CI/CD**: Automated systems may fail with diverged history
3. **Confuses git**: Everyone must `git reset --hard` to recover (loses local work)
4. **Violates trust**: Team can't rely on main being stable

**Protected branches**: Most repos protect main/master against force push (GitHub/GitLab settings).

**If you accidentally force pushed to main**:
1. **Immediately notify team**: Stop all work
2. **Find lost commits**: `git reflog` on remote (if accessible)
3. **Force push back**: Restore to correct state ASAP
4. **Document**: Explain what happened, how to recover
5. **Prevent**: Enable branch protection rules

## Recovering from Force Push Mistakes

### If You Force Pushed and Regret It

```bash
# Find previous state with reflog
git reflog

# Example output:
# a1b2c3d HEAD@{0}: push --force-with-lease: forced-update
# e4f5g6h HEAD@{1}: rebase: finished
# i7j8k9l HEAD@{2}: commit: my work before rebase

# Reset to before force push
git reset --hard HEAD@{2}

# Force push again to restore remote
git push --force-with-lease
```

**Reflog is local**: Only works if you have local copy. Remote reflog is usually inaccessible.

### If Someone Else Force Pushed

**Your local branch diverged from remote**:

```bash
# Fetch latest remote state
git fetch

# See divergence
git log HEAD..origin/<branch>  # Remote commits you don't have
git log origin/<branch>..HEAD  # Your commits not in remote

# Option 1: Abandon local changes, use remote
git reset --hard origin/<branch>

# Option 2: Keep local changes, rebase onto remote
git rebase origin/<branch>

# Option 3: Merge remote into local (creates merge commit)
git merge origin/<branch>
```

**Ask force pusher**: Which commits were intentionally removed? Which should you keep?

## GitHub/GitLab Force Push Protections

### GitHub Branch Protection Rules

Enable for main/master:
1. Settings → Branches → Add rule
2. Check: "Require pull request reviews before merging"
3. Check: "Do not allow force pushes"
4. Check: "Do not allow deletions"

**Result**: Force push to protected branch is rejected.

### GitLab Protected Branches

1. Settings → Repository → Protected Branches
2. Select branch: `main`
3. Allowed to push: "Maintainers" or "No one"
4. Allowed to force push: "No one"

**Result**: Force push requires elevated permissions.

## Best Practices Summary

✅ **DO**:
- Use `--force-with-lease` instead of `--force`
- Fetch before force pushing
- Force push only to your own feature branches
- Check `git log` to verify what's being overwritten
- Create backup branch before risky operations
- Communicate with team before force pushing shared branches

❌ **DON'T**:
- Force push to main/master
- Force push to shared branches without coordination
- Force push without fetching first
- Use `--force` when `--force-with-lease` is safer
- Assume no one else pushed (always verify)

## Quick Command Reference

```bash
# Safe force push (PREFERRED)
git fetch && git push --force-with-lease

# Check what will be overwritten
git log origin/<branch>..HEAD  # Your commits
git log HEAD..origin/<branch>  # Remote commits (should be empty)

# Create backup before force push
git branch backup-$(date +%s)

# Verify branch before force push
git branch --show-current  # Should NOT be main/master

# Abort if main/master
if [[ "$(git branch --show-current)" =~ ^(main|master)$ ]]; then
  echo "ERROR: Cannot force push to main/master"
  exit 1
fi

# Most conservative (Git 2.30+)
git push --force-if-includes

# Recover from force push mistake
git reflog  # Find previous state
git reset --hard HEAD@{N}  # Reset to before force push
git push --force-with-lease  # Restore remote
```

## When to Ask User Permission

Before force pushing, ask user if:
- Branch name contains "main", "master", "prod", "release"
- Remote has commits you don't have (`git log HEAD..origin/<branch>`)
- Last remote push was recent (<1 hour) and not by you
- Multiple contributors detected (check `git log --all --format='%ae' | sort -u`)

**Prompt format**:
```
⚠️  Force push will rewrite history on origin/<branch>
   Remote has commits not in your local branch.

   Proceed with force push? (y/N)
```

## Integration with commit-push-sync Skill

The commit-push-sync skill follows these guidelines:

1. **Never suggest force push** unless user explicitly requests
2. **Always use `--force-with-lease`** if force push needed
3. **Warn before force pushing** to main/master
4. **Fetch first** before any force push
5. **Provide recovery steps** if force push was mistake

**Typical interaction**:
```
User: "commit and push"
Skill: *detects push rejection due to rebase*
Skill: "Push rejected. Remote has diverged. Options:
        1. Pull and merge (safe, creates merge commit)
        2. Pull and rebase (rewrites history, requires force push)

        Which approach?"
User: "rebase"
Skill: *rebases, then prompts*
       "Rebase successful. Push requires --force-with-lease.
        Proceed? (y/N)"
```

## Force Push Decision Tree

```
Need to push?
├─ Push rejected?
│  ├─ Reason: non-fast-forward
│  │  ├─ Did you rebase? → Force push OK (use --force-with-lease)
│  │  ├─ Did you amend? → Force push OK (use --force-with-lease)
│  │  └─ Did someone else push? → Pull first, NO force push
│  └─ Reason: protected branch → Cannot force push (use PR)
└─ Push succeeded? → Done, no force push needed

Before force push:
├─ Branch is main/master? → STOP, never force push
├─ Branch is shared? → Coordinate with team first
├─ Fetched recently? → Yes → Proceed with --force-with-lease
└─ Not fetched? → Fetch first, then --force-with-lease
```

## Summary

Force push is a powerful tool that rewrites history. Use responsibly:

1. **Prefer `--force-with-lease`** over `--force`
2. **Never force push to main/master**
3. **Fetch before force push** (updates remote refs)
4. **Verify branch** before force push (check name)
5. **Backup if unsure** (create branch)
6. **Communicate with team** for shared branches
7. **Use reflog to recover** from mistakes

When in doubt, ask user before force pushing.
