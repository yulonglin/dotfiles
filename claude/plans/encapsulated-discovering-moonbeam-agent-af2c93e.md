# Claude Code Infinite Hang - Root Cause Analysis

**Date**: 2026-02-02
**Status**: Root cause identified

## Problem Statement

Claude Code hangs indefinitely on startup and never finishes loading. Started after commit 3f22bd9 which added hooks and plugin config changes.

## Investigation Summary

### What We've Ruled Out
- ✅ History file size (trimmed from 3.7MB to 270KB)
- ✅ All hooks disabled (moved to ~/.claude/hooks.bak)
- ✅ Network slowness (user confirms fast network)
- ✅ Config file corruption (settings.json and plugin configs valid)
- ✅ The nested ~/.claude/.claude/ directory (only 20KB of runtime logs)

### Critical Evidence Found

#### 1. Orphaned Plugins (LIKELY ROOT CAUSE)
```bash
$ cat ~/.claude/plugins/cache/local-marketplace/*/1.0.0/.orphaned_at
177006558666617770065586666177006558666
```

All three local plugins (code-toolkit, research-toolkit, writing-toolkit) are marked as orphaned with timestamps `1770065586666` (Feb 2, 2026 20:53:06 UTC).

#### 2. Missing Marketplace Directory
```bash
$ ls ~/.claude/plugins/marketplaces/
claude-plugins-official/
thedotmack/
# local-marketplace/ is MISSING!
```

But `known_marketplaces.json` references it:
```json
{
  "local-marketplace": {
    "source": {
      "source": "local",
      "path": "claude/local-marketplace"  // ← Relative path
    },
    "installLocation": "/Users/yulong/.claude/plugins/marketplaces/local-marketplace",
    "lastUpdated": "2026-02-02T20:56:00.970Z"
  }
}
```

#### 3. Path Resolution Issue

The marketplace config uses a **relative path** `"claude/local-marketplace"` which would be resolved from:
- Current working directory at startup (unpredictable)
- NOT from `~/.claude/` as intended

Since `~/.claude` → `/Users/yulong/code/dotfiles/claude` (symlink), the correct path should be:
- Absolute: `/Users/yulong/code/dotfiles/claude/local-marketplace`
- OR relative from home: `~/code/dotfiles/claude/local-marketplace`

## Root Cause Hypothesis

**Claude Code is stuck in an infinite retry loop trying to resolve orphaned plugins.**

The startup sequence likely:
1. Loads `known_marketplaces.json`
2. Tries to resolve relative path `claude/local-marketplace` from CWD
3. Fails to find marketplace directory
4. Sees 3 orphaned plugins in installed_plugins.json
5. Attempts to re-sync/validate plugins from missing marketplace
6. Infinite loop: can't find source, can't resolve orphans, can't proceed

This would cause a hang (not crash) because:
- The plugin system is waiting for filesystem operations that never complete
- Or retrying failed path resolutions indefinitely
- Or deadlocked waiting for marketplace that doesn't exist at expected path

## Why Commit 3f22bd9 Triggered This

From git log:
```
3f22bd9 feat: implement per-project plans/tasks with validation hooks
```

This commit likely:
- Modified plugin configuration or marketplace registration
- Changed how relative paths are resolved
- Added hooks that register local marketplace with relative path
- Triggered plugin re-sync that orphaned the local plugins

## Verification Steps

1. **Check if Claude Code processes are spinning**:
   ```bash
   ps aux | grep claude  # (sandbox blocked this earlier)
   ```

2. **Check system logs for filesystem errors**:
   ```bash
   log show --predicate 'process == "2.1.29"' --last 5m --info
   ```

3. **Verify plugins marked as orphaned**:
   ```bash
   grep -r "orphaned_at" ~/.claude/plugins/cache/
   ```

## Proposed Solution

### Option 1: Fix Marketplace Path (Recommended)
Update `known_marketplaces.json` to use absolute path:
```json
{
  "local-marketplace": {
    "source": {
      "source": "local",
      "path": "/Users/yulong/code/dotfiles/claude/local-marketplace"
    },
    "installLocation": "/Users/yulong/.claude/plugins/marketplaces/local-marketplace",
    "lastUpdated": "2026-02-02T20:56:00.970Z"
  }
}
```

Then create the missing marketplace directory:
```bash
mkdir -p ~/.claude/plugins/marketplaces/local-marketplace
ln -s /Users/yulong/code/dotfiles/claude/local-marketplace/* \
      ~/.claude/plugins/marketplaces/local-marketplace/
```

### Option 2: Remove Orphaned Plugins (Nuclear Option)
Delete orphaned plugin cache and re-register:
```bash
rm -rf ~/.claude/plugins/cache/local-marketplace/
rm -rf ~/.claude/plugins/marketplaces/local-marketplace/
# Edit known_marketplaces.json to remove local-marketplace entry
# Restart Claude Code
# Re-register marketplace with correct absolute path
```

### Option 3: Disable Local Plugins Temporarily
```bash
# Edit installed_plugins.json, remove local-marketplace entries
# Or move ~/.claude/plugins/ to ~/.claude/plugins.bak
```

## Testing the Fix

After applying solution:
1. Restart Claude Code
2. Check startup completes within 10 seconds
3. Verify `/marketplace list` shows local-marketplace
4. Verify local plugins load: `/plugins list`
5. Test a local skill: `/run-experiment --help`

## Prevention

Add to deployment scripts:
1. Always use absolute paths for local marketplace registration
2. Validate marketplace directories exist before registering
3. Add pre-commit hook to validate plugin configs
4. Document marketplace setup in README

## Files Involved

- `/Users/yulong/.claude/plugins/known_marketplaces.json` - Marketplace registration (relative path bug)
- `/Users/yulong/.claude/plugins/installed_plugins.json` - Shows orphaned local plugins
- `/Users/yulong/.claude/plugins/cache/local-marketplace/*/1.0.0/.orphaned_at` - Orphan timestamps
- `/Users/yulong/code/dotfiles/claude/local-marketplace/` - Source marketplace (correct location)
- `/Users/yulong/.claude/plugins/marketplaces/local-marketplace/` - Expected symlink (MISSING)

## Next Steps

1. User confirms hypothesis (startup logs, process behavior)
2. Choose solution approach (Option 1 recommended)
3. Apply fix
4. Verify startup works
5. Update deployment scripts to prevent recurrence
