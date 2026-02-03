# Fix Claude Code Startup Hang - Orphaned Plugin Infinite Retry Loop

## Problem Summary

Claude Code hangs on startup and never finishes loading due to an **infinite retry loop** attempting to re-sync orphaned plugins from a missing marketplace.

## Root Cause

**Orphaned plugins + broken marketplace path = infinite sync retry loop**

1. Three local plugins have `.orphaned_at` timestamp files (code-toolkit, research-toolkit, writing-toolkit)
2. Marketplace config uses **relative path**: `claude/local-marketplace` (unpredictable CWD resolution)
3. Marketplace directory doesn't exist at expected location
4. Claude Code tries to re-sync → fails → retries infinitely → **hangs forever**

This was introduced by commit `3f22bd9` which changed plugin configuration to use relative paths and templates.

## Critical Files

- `~/.claude/plugins/known_marketplaces.json` - Contains broken relative path
- `~/.claude/plugins/cache/local-marketplace/*/.orphaned_at` - Orphan timestamps triggering retry
- `/Users/yulong/code/dotfiles/claude/local-marketplace/` - Source marketplace directory

## Solution: Fix Template System with Deploy-Time Substitution

### Step 1: Update Template Files

**In `claude/plugins/known_marketplaces.json.template`:**
```json
[
  {
    "name": "local-marketplace",
    "path": "{{DOTFILES_DIR}}/claude/local-marketplace"
  }
]
```

Use `{{DOTFILES_DIR}}` placeholder instead of relative path.

### Step 2: Update deploy.sh

**In `deploy_plugins_config()` function:**
```bash
# Get dotfiles directory absolute path
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Generate configs from templates with substitution
sed "s|{{DOTFILES_DIR}}|$DOTFILES_DIR|g" \
    claude/plugins/known_marketplaces.json.template > \
    ~/.claude/plugins/known_marketplaces.json

sed "s|{{DOTFILES_DIR}}|$DOTFILES_DIR|g" \
    claude/plugins/installed_plugins.json.template > \
    ~/.claude/plugins/installed_plugins.json
```

### Step 3: Update .gitignore

**Add to `claude/.gitignore`:**
```gitignore
# Generated plugin configs (machine-specific absolute paths)
plugins/known_marketplaces.json
plugins/installed_plugins.json
```

Keep only the `.template` files in git.

### Step 4: Remove Orphaned State

```bash
# Clear orphan timestamps
find ~/.claude/plugins/cache/local-marketplace -name ".orphaned_at" -delete
```

### Step 5: Deploy

```bash
cd ~/code/dotfiles
./deploy.sh --claude
```

This generates machine-specific configs with correct absolute paths.

## Quick Workaround (If deploy.sh not ready yet)

**Manually fix the path to unblock startup immediately:**

```bash
# 1. Edit known_marketplaces.json directly
cd ~/.claude/plugins
DOTFILES_DIR="/Users/yulong/code/dotfiles"
jq ".[0].path = \"$DOTFILES_DIR/claude/local-marketplace\"" \
   known_marketplaces.json > temp.json && mv temp.json known_marketplaces.json

# 2. Remove orphan timestamps
find ~/.claude/plugins/cache/local-marketplace -name ".orphaned_at" -delete

# 3. Test startup
claude
```

This is a temporary fix—still implement the template system properly.

## Verification Steps

### 1. Verify Current Issue

```bash
# Check for orphaned plugins
find ~/.claude/plugins/cache -name ".orphaned_at"
# Expected: Should find .orphaned_at files for code-toolkit, research-toolkit, writing-toolkit

# Check marketplace path
cat ~/.claude/plugins/known_marketplaces.json | jq '.[0].path'
# Expected: "claude/local-marketplace" (WRONG - relative path causes issue)
```

### 2. Implement Fix

Choose one:

**A. Full Template System (Recommended)**
```bash
# Implement Steps 1-5 from Solution section above
# This is the proper long-term fix
```

**B. Quick Workaround**
```bash
# Use manual path fix from "Quick Workaround" section
# Gets Claude working immediately, implement templates later
```

### 3. Verify Fix Applied

```bash
# Check path is now absolute
cat ~/.claude/plugins/known_marketplaces.json | jq '.[0].path'
# Expected: "/Users/yulong/code/dotfiles/claude/local-marketplace" (absolute path)

# Verify path exists
ls -la "$(jq -r '.[0].path' ~/.claude/plugins/known_marketplaces.json)"
# Expected: Shows local-marketplace directory contents

# Check orphan files removed
find ~/.claude/plugins/cache -name ".orphaned_at"
# Expected: No output (all orphan timestamps cleared)
```

### 4. Test Startup

```bash
claude
# Expected: Starts immediately without hanging (under 5 seconds)
```

If still hangs, check deploy.sh actually generated the file correctly.

## Why This Happened

Commit `3f22bd9` and `d21dfe2` refactored plugin configuration to use templates:
- Changed `installed_plugins.json` → `installed_plugins.json.template`
- Changed `known_marketplaces.json` → `known_marketplaces.json.template`
- Used **relative path** `claude/local-marketplace` instead of absolute

When the template was deployed, the relative path couldn't be resolved correctly because:
1. `~/.claude` is a symlink to `dotfiles/claude/`
2. Relative path resolution depends on CWD (unpredictable)
3. Expected marketplace at `~/.claude/plugins/marketplaces/local-marketplace/` but it was missing

This caused the plugins to be marked as orphaned, triggering infinite re-sync attempts.

## Prevention

1. **Template files in git, runtime configs gitignored**:
   - Commit: `*.template` files with `{{DOTFILES_DIR}}` placeholders
   - Ignore: Generated configs with absolute paths

2. **deploy.sh validates after generation**:
   ```bash
   # After generating configs
   MARKETPLACE_PATH=$(jq -r '.[0].path' ~/.claude/plugins/known_marketplaces.json)
   if [[ ! -d "$MARKETPLACE_PATH" ]]; then
     echo "ERROR: Marketplace not found at $MARKETPLACE_PATH"
     exit 1
   fi
   ```

3. **Document in CLAUDE.md**:
   ```markdown
   ## Plugin Configuration
   - Source: claude/plugins/*.template (version controlled)
   - Runtime: ~/.claude/plugins/*.json (machine-specific, gitignored)
   - Deploy: ./deploy.sh --claude regenerates with correct paths
   ```

4. **CI/CD check** (optional):
   ```bash
   # In pre-commit hook - verify no absolute paths in templates
   if grep -r "/Users/" claude/plugins/*.template; then
     echo "ERROR: Absolute path in template file"
     exit 1
   fi
   ```
