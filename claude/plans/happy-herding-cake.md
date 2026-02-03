# Fix Claude Code Startup by Reverting Plugin Runtime Files

## Problem Summary

**Claude Code won't start** - traced to commit `9f1d2ca` which introduced:
1. Hardcoded absolute paths (`/Users/yulong/...`) in runtime files
2. Relative path for local marketplace (`"path": "claude/local-marketplace"`) that can't be resolved

**Root cause**: Runtime plugin files (`installed_plugins.json`, `known_marketplaces.json`) were committed to git starting with `e6a8edd`. These files are managed by Claude Code and should NEVER be in version control.

**Cascading failures**:
- `9f1d2ca`: Added relative path → Claude Code can't resolve it → startup hang
- `d21dfe2`, `27185cf`, `dc23b28`: Attempted fixes using templates
- `dab6f6d`: Removed templates → broke the template-based workaround

**Current state**: Claude Code still won't start because runtime files exist with unresolvable paths.

## Investigation Results

### Current State
```
~/.claude → /Users/yulong/code/dotfiles/claude (symlink OK)
~/.claude/plugins/marketplaces/ contains:
  ✓ anthropics-claude-plugins-official
  ✓ claude-plugins-official
  ✓ thedotmack
  ✗ local-marketplace (missing!)

claude/local-marketplace/ exists with:
  ✓ .claude-plugin/marketplace.json
  ✓ plugins/research-toolkit/
  ✓ plugins/writing-toolkit/
  ✓ plugins/code-toolkit/
```

### Root Cause Analysis

1. **Runtime files in git**: `installed_plugins.json` and `known_marketplaces.json` are managed by Claude Code's plugin system, similar to `node_modules/` or `__pycache__/`. They should be git-ignored.

2. **Hardcoded paths**: The commit changed all paths from Linux (`/mnt/nw/home/y.lin/`) to macOS (`/Users/yulong/`), which breaks portability.

3. **Local marketplace not installed**: The marketplace exists in source but hasn't been properly registered/installed by Claude Code's plugin system.

## Implementation Plan

### Phase 1: Delete Local Runtime Files (Safe!)

**Action**: Delete corrupted local runtime files - Claude Code will regenerate them cleanly:
```bash
rm ~/.claude/plugins/installed_plugins.json
rm ~/.claude/plugins/known_marketplaces.json
rm ~/.claude/plugins/config.json
rm -rf ~/.claude/plugins/marketplaces/local-marketplace  # Remove broken symlink if exists
```

**Why this is safe**:
- These files contain NO user data, only plugin installation state
- Claude Code regenerates them automatically on next startup
- Like clearing a cache - purely restorative

### Phase 2: Gitignore Runtime Files

**Action**: Add plugin runtime files to `.gitignore`:

```gitignore
#-------------------------------------------------------------
# Claude Code Runtime State (NEVER COMMIT THESE)
#-------------------------------------------------------------
# These files are managed by Claude Code's plugin system and contain:
# - Absolute paths specific to the current machine/user
# - Plugin installation state that differs per machine
# - Runtime cache that should be regenerated
#
# Committing these files causes:
# - Claude Code startup failures on other machines
# - Hardcoded paths that break portability
# - Plugin loading errors for non-existent paths
#
# If you see these files in `git status`, they were committed by mistake.
# Remove with: git rm --cached claude/plugins/*.json

claude/plugins/installed_plugins.json
claude/plugins/known_marketplaces.json
claude/plugins/install-counts-cache.json
claude/plugins/config.json
claude/plugins/cache/
claude/plugins/marketplaces/
```

### Phase 3: Remove from Git Tracking

Remove from git but preserve locally (so they'll be regenerated):
```bash
git rm --cached claude/plugins/installed_plugins.json
git rm --cached claude/plugins/known_marketplaces.json
git rm --cached claude/plugins/config.json
```

### Phase 4: Test Claude Code Startup

**Action**: Test that Claude Code starts without hanging:
```bash
claude --version
```

**Expected**: Should return immediately with version info, not hang.

If it hangs or fails:
- Check `~/.claude/plugins/known_marketplaces.json` for relative paths
- Ensure `~/.claude` symlink points to `dotfiles/claude/`
- Try `./deploy.sh --claude` to re-register marketplace

### Phase 5: Register Local Marketplace (if needed)

If local plugins aren't available after Phase 4:

**Action**: Use `deploy.sh` to register the local marketplace:
```bash
./deploy.sh --claude
```

This will:
1. Create the `~/.claude` symlink to `dotfiles/claude/`
2. Register the local marketplace using Claude Code's plugin system
3. Install local plugins (research-toolkit, writing-toolkit, code-toolkit)

**Alternative manual method**:
```bash
claude plugin marketplace add ~/.claude/local-marketplace
claude plugin install research-toolkit@local-marketplace
claude plugin install writing-toolkit@local-marketplace
claude plugin install code-toolkit@local-marketplace
```

### Phase 6: Commit Changes

Commit the gitignore and git rm changes:
```bash
git add .gitignore
git commit -m "fix: remove Claude Code plugin runtime files from git

Root cause: Runtime state files (installed_plugins.json,
known_marketplaces.json) were committed with machine-specific paths,
causing Claude Code to hang on startup.

Solution:
- Gitignore all plugin runtime files
- Remove from git tracking (preserves local copies)
- Claude Code regenerates them cleanly on next startup

These files are equivalent to node_modules/ or __pycache__/ and
should never be version-controlled."
```

### Phase 7: Update Documentation

**Action**: Add a note to `claude/local-marketplace/README.md` about runtime files:

Add after line 67 (end of Troubleshooting section):

```markdown
## Runtime Files

The following files in `claude/plugins/` are runtime state managed by Claude Code:
- `installed_plugins.json` - Plugin installation registry
- `known_marketplaces.json` - Registered marketplace paths
- `install-counts-cache.json` - Usage statistics

These files are git-ignored and regenerated on each machine. If you see them
with hardcoded paths in git, they were committed by mistake and should be removed
with `git rm --cached`.
```

## Critical Files

### Files to Modify
- `.gitignore` - Add plugin runtime exclusions
- `claude/local-marketplace/README.md` - Add runtime files documentation (append to existing)

### Files to Remove from Git
- `claude/plugins/installed_plugins.json`
- `claude/plugins/known_marketplaces.json`
- `claude/plugins/install-counts-cache.json`

### Files to Investigate
- `deploy.sh` - May need marketplace registration logic
- Claude Code docs - Check marketplace registration commands

## Verification

After implementation:

1. **Check git status**:
   ```bash
   git status claude/plugins/
   # Should show no tracked files in claude/plugins/
   ```

2. **Verify gitignore**:
   ```bash
   git check-ignore claude/plugins/installed_plugins.json
   git check-ignore claude/plugins/known_marketplaces.json
   # Both should be reported as ignored
   ```

3. **Test Claude Code starts**:
   ```bash
   claude --version
   # Should return immediately without hanging
   ```

4. **Verify local plugins are available**:
   ```bash
   # In a new Claude Code session
   /research-toolkit  # Should be available
   /writing-toolkit   # Should be available
   /code-toolkit      # Should be available
   ```

5. **Check plugin files were regenerated correctly**:
   ```bash
   cat ~/.claude/plugins/known_marketplaces.json
   # Should contain absolute paths, no relative paths
   # local-marketplace should point to full path like:
   # "/Users/yulong/code/dotfiles/claude/local-marketplace"
   ```

## Success Criteria

- [ ] Local runtime files deleted
- [ ] Runtime files git-ignored
- [ ] Runtime files removed from git tracking
- [ ] Claude Code starts immediately with `claude --version` (no hang)
- [ ] Claude Code regenerates clean runtime files with absolute paths
- [ ] Local plugins (research-toolkit, writing-toolkit, code-toolkit) are available
- [ ] `~/.claude/plugins/known_marketplaces.json` contains only absolute paths (no relative paths)
- [ ] Documentation updated

## Risk Assessment

**Low risk**:
- Reverting commits is safe (no code changes, only config files)
- Deleting runtime files is safe - Claude Code regenerates them automatically
- `.gitignore` prevents re-committing

**Safety**: Runtime files are pure state with no user data. Deleting them is equivalent to clearing a cache.

## Critical Files

**Files to modify**:
- `.gitignore` - Add runtime file exclusions
- `claude/local-marketplace/README.md` - Document runtime files

**Files to remove from git**:
- `claude/plugins/installed_plugins.json`
- `claude/plugins/known_marketplaces.json`
- `claude/plugins/config.json`

**Files to delete locally** (will be regenerated):
- `~/.claude/plugins/installed_plugins.json`
- `~/.claude/plugins/known_marketplaces.json`
- `~/.claude/plugins/marketplaces/local-marketplace/` (if exists)
