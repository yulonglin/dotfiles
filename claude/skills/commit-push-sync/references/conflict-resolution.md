# Conflict Resolution During Rebase

Detailed guidance for handling merge conflicts when running `git pull --rebase`.

## Understanding Rebase Conflicts

Conflicts occur during `git pull --rebase` when:
- Local commits modify lines also changed in remote commits
- Files are renamed/deleted locally but modified remotely (or vice versa)
- Binary files differ between local and remote

**Rebase vs Merge conflicts**:
- Rebase: Replays local commits on top of remote commits (one conflict per local commit)
- Merge: Creates single merge commit (all conflicts at once)

Rebase maintains linear history but may require resolving conflicts multiple times if multiple local commits touch the same areas.

## Conflict Workflow

### Step 1: Identify Conflicts

When `git pull --rebase` reports conflicts:

```bash
git status
```

Look for:
```
Unmerged paths:
  both modified:   src/file.py
  deleted by us:   config/old.yaml
  added by them:   config/new.yaml
```

### Step 2: Examine Conflict Markers

For text files, conflicts appear as:

```
<<<<<<< HEAD (remote version)
Remote changes here
=======
Local changes here
>>>>>>> commit-message (local version)
```

### Step 3: Resolve Conflicts

**Manual resolution**:
1. Edit conflicting files
2. Remove conflict markers (`<<<<<<<`, `=======`, `>>>>>>>`)
3. Keep desired changes (local, remote, or combination)
4. Save file

**Example**:
```python
# Before resolution
<<<<<<< HEAD
def process(data):
    return validate(data)
=======
def process(data):
    return sanitize(data)
>>>>>>> feat: add input sanitization

# After resolution (keep both)
def process(data):
    data = sanitize(data)
    return validate(data)
```

### Step 4: Stage Resolved Files

```bash
git add src/file.py config/other.py
```

Stage ALL resolved files before continuing.

### Step 5: Continue Rebase

```bash
git rebase --continue
```

If more local commits exist, may encounter conflicts again—repeat process.

### Step 6: Abort If Needed

If conflicts are too complex or you want to start over:

```bash
git rebase --abort
```

Returns to state before `git pull --rebase`.

## Common Conflict Scenarios

### Scenario 1: Both Modified Same Lines

**Conflict**:
```
<<<<<<< HEAD
result = compute_v2(input)
=======
result = compute_new(input)
>>>>>>> refactor: rename compute function
```

**Resolution approaches**:
- **Keep remote**: Use `compute_v2` (assuming remote is authoritative)
- **Keep local**: Use `compute_new` (your refactor is correct)
- **Combine**: If both changes are needed, integrate both

**Decision criteria**:
- Check commit timestamps: Which change is more recent?
- Check commit messages: Which change is intentional vs incidental?
- Check surrounding code: Which version is consistent with codebase?

### Scenario 2: File Deleted Locally, Modified Remotely

```
deleted by us:   src/deprecated.py
```

**Options**:
```bash
# Keep deletion (remove file)
git rm src/deprecated.py

# Keep remote version (restore and accept their changes)
git add src/deprecated.py
```

**Decision criteria**:
- Was local deletion intentional? (check commit message)
- Are remote changes critical? (review with `git diff`)
- Can remote changes be migrated to new file?

### Scenario 3: File Added with Same Name

```
added by us:     config/settings.yaml
added by them:   config/settings.yaml
```

Both local and remote added same filename (different content).

**Options**:
```bash
# Rename local version
git mv config/settings.yaml config/settings-local.yaml
git add config/settings.yaml  # Accept remote version

# Merge contents manually
# Edit config/settings.yaml to combine both
git add config/settings.yaml
```

### Scenario 4: Binary File Conflicts

```
both modified:   assets/logo.png
```

Cannot merge binary files—must choose one version.

**Options**:
```bash
# Keep remote version
git checkout --theirs assets/logo.png
git add assets/logo.png

# Keep local version
git checkout --ours assets/logo.png
git add assets/logo.png
```

**Note**: `--ours` and `--theirs` are REVERSED in rebase:
- During rebase: `--ours` = remote, `--theirs` = local
- During merge: `--ours` = local, `--theirs` = remote

## Tools for Conflict Resolution

### Using Git Diff

```bash
# Show conflicts with context
git diff

# Show conflicts for specific file
git diff src/file.py

# Show what changed in remote
git diff HEAD...origin/main src/file.py

# Show what changed locally
git diff origin/main...HEAD src/file.py
```

### Using Git Log

```bash
# See commits being rebased
git log --oneline origin/main..HEAD

# See remote commits we're rebasing onto
git log --oneline HEAD..origin/main
```

### Using Merge Tools

```bash
# Launch visual merge tool
git mergetool

# Common tools: vimdiff, meld, kdiff3, opendiff (macOS)
```

Configure default merge tool:
```bash
git config --global merge.tool vimdiff
```

## Conflict Prevention

### Best Practices

1. **Pull frequently**: Reduces divergence between local and remote
2. **Small commits**: Easier to rebase, fewer conflicts
3. **Coordinate with team**: Communicate before major refactors
4. **Feature branches**: Isolate experimental work from main

### Before Pull Rebase

```bash
# Check how much local and remote have diverged
git fetch
git log --oneline HEAD..origin/main  # Remote commits
git log --oneline origin/main..HEAD  # Local commits

# If large divergence, consider merge instead of rebase
git pull --no-rebase  # Creates merge commit instead
```

## Stash Pop Conflicts

After `git stash && git pull --rebase && git stash pop`, conflicts may occur during stash pop:

```
CONFLICT (content): Merge conflict in src/file.py
```

**Resolution**:
1. Resolve conflicts manually (same as rebase conflicts)
2. Stage resolved files: `git add src/file.py`
3. **Do NOT** `git stash drop` until conflicts resolved
4. After resolution, stash entry is automatically dropped

**Abort stash pop**:
```bash
git reset --merge  # Undo stash pop, restore stash entry
```

## When to Give Up on Rebase

Abort rebase and use merge instead if:
- Too many conflicts (>5 files or >3 commit rounds)
- Conflicts are complex (extensive refactoring on both sides)
- Binary files with conflicts (can't merge, must choose)
- Time-sensitive (need to push quickly)

**Switch to merge**:
```bash
git rebase --abort
git pull --no-rebase  # Creates merge commit
```

Merge commits are acceptable when rebase is too difficult—linear history is nice but not mandatory.

## Advanced: Rerere (Reuse Recorded Resolution)

Git can remember conflict resolutions:

```bash
# Enable rerere
git config --global rerere.enabled true
```

**How it works**:
- First time you resolve a conflict, git records the resolution
- Next time same conflict appears (e.g., during another rebase), git auto-applies resolution

**Useful when**:
- Rebasing multiple times on same branch
- Cherry-picking commits across branches
- Long-running feature branches

## Conflict Resolution Checklist

Before continuing rebase:
- [ ] All conflicts resolved (no `<<<<<<<` markers remain)
- [ ] Code compiles/runs (if applicable)
- [ ] Tests pass (if applicable)
- [ ] Resolved files staged (`git add`)
- [ ] Commit message reviewed (will be preserved)

After continuing rebase:
- [ ] No more conflicts reported
- [ ] Rebase completed successfully
- [ ] Final state matches expectations
- [ ] Ready to push

## Emergency: Recovering from Bad Rebase

If rebase goes wrong:

```bash
# Find previous HEAD before rebase
git reflog

# Example output:
# a1b2c3d HEAD@{0}: rebase finished: ...
# e4f5g6h HEAD@{1}: checkout: moving from main to e4f5g6h
# i7j8k9l HEAD@{2}: commit: my work before rebase

# Reset to state before rebase
git reset --hard HEAD@{2}
```

**Reflog preserves history for ~90 days**—use it to undo mistakes.

## Summary

**Key principles**:
1. Understand conflict context (which commits, which changes)
2. Resolve systematically (one file at a time)
3. Stage all resolved files before continuing
4. Verify resolution (tests pass, code works)
5. Abort if too complex (merge instead)
6. Use reflog as safety net

**When to involve user**:
- Always involve user for conflict resolution (never auto-resolve)
- Provide context: which commits conflict, what changed
- Offer options: abort, continue, switch to merge
- Verify understanding before proceeding
