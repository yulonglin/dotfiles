# Plugin Marketplace Cleanup Plan

## Problem Summary

You have duplicate plugin marketplaces causing confusion and installation errors:

1. **claude-plugins-official** (git clone) - Built-in marketplace that doesn't need to be manually cloned
2. **claude-code-plugins** (git clone) - Main Claude Code CLI repository being misused as a marketplace
3. **7 duplicate plugins** installed from both marketplaces

**Goal:** Remove redundant marketplace git clones, deduplicate plugins, and rely on the built-in official marketplace.

---

## Current State

**Marketplaces:**
- `claude-plugins-official`: 17 plugins installed (REDUNDANT - marketplace is built-in)
- `claude-code-plugins`: 7 plugins installed (WRONG - this is the CLI repo, not a marketplace)
- `local-marketplace`: 3 plugins (research/writing/code toolkits - PRESERVE)

**Duplicate Plugins (enabled in both marketplaces):**
1. code-review
2. plugin-dev
3. security-guidance
4. learning-output-style
5. hookify
6. frontend-design
7. ralph-wiggum (claude-code-plugins) = ralph-loop (claude-plugins-official)

**Critical Files:**
- `/Users/yulong/.claude/settings.json` - Lines 164-193 contain duplicate enabledPlugins entries
- `/Users/yulong/.claude/plugins/known_marketplaces.json` - Registers all three marketplaces
- `/Users/yulong/.claude/plugins/installed_plugins.json` - Tracks all 27 installed plugins

---

## Implementation Steps

### 1. Pre-Cleanup Backup

Create safety backups before any changes:

```bash
# Create backup directory
mkdir -p ~/tmp/claude-backup-$(date +%Y%m%d-%H%M%S)
BACKUP_DIR=~/tmp/claude-backup-$(ls -t ~/tmp/ | grep claude-backup | head -1)

# Backup configuration files
cp ~/.claude/settings.json "$BACKUP_DIR/settings.json.backup"
cp ~/.claude/plugins/installed_plugins.json "$BACKUP_DIR/installed_plugins.json.backup"
cp ~/.claude/plugins/known_marketplaces.json "$BACKUP_DIR/known_marketplaces.json.backup"

# Backup entire plugin cache (safety net)
tar -czf "$BACKUP_DIR/plugin-cache-backup.tar.gz" ~/.claude/plugins/cache/

echo "Backups created in: $BACKUP_DIR"
```

### 2. Edit settings.json - Remove Duplicate Plugins

**File:** `/Users/yulong/.claude/settings.json`

**Remove these lines (186-192):**
```json
"code-review@claude-code-plugins": true,
"plugin-dev@claude-code-plugins": true,
"security-guidance@claude-code-plugins": true,
"ralph-wiggum@claude-code-plugins": true,
"learning-output-style@claude-code-plugins": true,
"hookify@claude-code-plugins": true,
"frontend-design@claude-code-plugins": true
```

**Keep these existing lines (they're already enabled):**
- `"code-review@claude-plugins-official": true` (line 168)
- `"plugin-dev@claude-plugins-official": true` (line 176)
- `"security-guidance@claude-plugins-official": true` (line 169)
- `"ralph-loop@claude-plugins-official": true` (line 174) ← replaces ralph-wiggum
- `"learning-output-style@claude-plugins-official": true` (line 175)
- `"hookify@claude-plugins-official": true` (line 171)
- `"frontend-design@claude-plugins-official": true` (line 172)

**Note:** ralph-wiggum is the same plugin as ralph-loop (just renamed). Keep ralph-loop.

### 3. Edit known_marketplaces.json - Remove claude-code-plugins

**File:** `/Users/yulong/.claude/plugins/known_marketplaces.json`

**Remove lines 18-25:**
```json
"claude-code-plugins": {
  "source": {
    "source": "github",
    "repo": "anthropics/claude-code"
  },
  "installLocation": "/Users/yulong/.claude/plugins/marketplaces/claude-code-plugins",
  "lastUpdated": "2026-02-03T20:55:34.994Z"
}
```

**Keep:**
- `local-marketplace` entry (lines 2-9)
- `claude-plugins-official` entry (lines 10-17)

### 4. Remove Marketplace Directories

```bash
# Remove the claude-code-plugins marketplace (CLI repo misused as marketplace)
rm -rf ~/.claude/plugins/marketplaces/claude-code-plugins

# Remove the claude-plugins-official git clone (redundant - marketplace is built-in)
rm -rf ~/.claude/plugins/marketplaces/claude-plugins-official
```

### 5. Clean Plugin Cache

```bash
# Remove orphaned cache from claude-code-plugins
rm -rf ~/.claude/plugins/cache/claude-code-plugins

# Remove temp git directories
rm -rf ~/.claude/plugins/cache/temp_git_*

# Optional: Clear claude-plugins-official cache to force fresh install
# (It will auto-rebuild from built-in marketplace on next startup)
rm -rf ~/.claude/plugins/cache/claude-plugins-official
```

### 6. Update installed_plugins.json

**File:** `/Users/yulong/.claude/plugins/installed_plugins.json`

Remove all entries for `@claude-code-plugins` marketplace:
- code-review@claude-code-plugins (lines 204-213)
- plugin-dev@claude-code-plugins (lines 214-223)
- security-guidance@claude-code-plugins (lines 224-233)
- ralph-wiggum@claude-code-plugins (lines 234-243)
- learning-output-style@claude-code-plugins (lines 244-253)
- hookify@claude-code-plugins (lines 254-263)
- frontend-design@claude-code-plugins (lines 264-273)

**Keep all entries for:**
- `@local-marketplace` (research-toolkit, writing-toolkit, code-toolkit)
- `@claude-plugins-official` (all 17 plugins)

### 7. Restart Claude Code

```bash
# Exit current Claude session
exit

# Start new session
claude

# Claude will:
# 1. Detect missing cache entries for enabled plugins
# 2. Auto-fetch from built-in claude-plugins-official marketplace
# 3. Rebuild cache at ~/.claude/plugins/cache/claude-plugins-official/
# 4. Update installed_plugins.json with new installation metadata
```

---

## Verification Steps

After restart, verify the cleanup was successful:

### 1. Check Marketplace Registration
```bash
cat ~/.claude/plugins/known_marketplaces.json | jq 'keys'
# Expected: ["claude-plugins-official", "local-marketplace"]
# Should NOT contain "claude-code-plugins"
```

### 2. Check Enabled Plugins
```bash
cat ~/.claude/settings.json | jq '.enabledPlugins | keys' | grep "@claude-code-plugins"
# Expected: No output (all @claude-code-plugins entries removed)
```

### 3. Check Installed Plugins
```bash
cat ~/.claude/plugins/installed_plugins.json | jq '.plugins | keys[]' | cut -d'@' -f2 | sort | uniq -c
# Expected:
#    3 local-marketplace
#   17 claude-plugins-official
# Should NOT show "claude-code-plugins"
```

### 4. Verify Local Marketplace Plugins Still Work
```bash
# Check if custom plugins are still available
claude skills | grep -E "research-toolkit|writing-toolkit|code-toolkit"
# Expected: Should see all skills from these plugins
```

### 5. Test Plugin Functionality
```bash
# Test a plugin command (e.g., commit-commands)
/commit --help

# Test ralph-loop (replacement for ralph-wiggum)
/ralph-loop --help

# Test hookify
/hookify --help
```

### 6. Check Plugin Cache Directories
```bash
ls ~/.claude/plugins/cache/
# Expected: claude-plugins-official/, local-marketplace/
# Should NOT contain: claude-code-plugins/

# Count plugins in official cache
find ~/.claude/plugins/cache/claude-plugins-official -maxdepth 2 -type d | wc -l
# Expected: ~17 plugin directories
```

---

## Expected Final State

**After cleanup:**
- 20 plugins total (17 official + 3 local)
- 2 marketplaces: built-in claude-plugins-official + local-marketplace
- No duplicate plugin entries
- No claude-code-plugins marketplace
- All functionality preserved

**Plugin count by marketplace:**
- claude-plugins-official: 17 plugins
- local-marketplace: 3 plugins (research-toolkit, writing-toolkit, code-toolkit)

**Preserved custom content:**
- ✅ Local marketplace plugins (research/writing/code toolkits)
- ✅ Custom skills in ~/code/dotfiles/claude/skills/
- ✅ Custom agents in ~/code/dotfiles/claude/agents/
- ✅ Hooks configuration
- ✅ All settings and preferences

**Removed:**
- ❌ claude-code-plugins marketplace (CLI repo)
- ❌ claude-plugins-official git clone (redundant)
- ❌ 7 duplicate plugin installations
- ❌ Orphaned cache directories

---

## Rollback Procedure

If something goes wrong, restore from backup:

```bash
BACKUP_DIR=~/tmp/claude-backup-$(ls -t ~/tmp/ | grep claude-backup | head -1)

# Restore configuration files
cp "$BACKUP_DIR/settings.json.backup" ~/.claude/settings.json
cp "$BACKUP_DIR/installed_plugins.json.backup" ~/.claude/plugins/installed_plugins.json
cp "$BACKUP_DIR/known_marketplaces.json.backup" ~/.claude/plugins/known_marketplaces.json

# Restore plugin cache
cd ~/.claude/plugins
rm -rf cache/
tar -xzf "$BACKUP_DIR/plugin-cache-backup.tar.gz" -C ~

# Restart Claude Code
exit
claude
```

---

## Post-Cleanup: How to Add Plugins Back

After cleanup, the built-in `claude-plugins-official` marketplace is automatically available.

### Installing New Plugins

Plugins are **auto-installed** when enabled in settings:

1. **Enable plugin in settings.json:**
```json
"enabledPlugins": {
  "plugin-name@claude-plugins-official": true
}
```

2. **Restart Claude Code:**
```bash
exit
claude
```

3. **Claude automatically:**
   - Detects the enabled plugin
   - Fetches it from the built-in marketplace
   - Installs to `~/.claude/plugins/cache/claude-plugins-official/plugin-name/`
   - Updates `installed_plugins.json`

### No Explicit Install Command Needed

Claude Code uses **pull-based plugin discovery:**
- Plugins enabled in `settings.json` are automatically fetched
- No `claude install plugin-name` command required
- Cache rebuilds automatically when missing

### Adding Third-Party Marketplaces

If you later want to add other marketplaces:

```bash
# Via Claude Code UI (preferred)
/plugin marketplace add owner/repo

# Or manually edit known_marketplaces.json:
{
  "my-marketplace": {
    "source": {
      "source": "github",
      "repo": "owner/repo"
    },
    "installLocation": "/Users/yulong/.claude/plugins/marketplaces/my-marketplace"
  }
}
```

---

## Risk Assessment

**Low Risk:**
- All changes backed up
- Plugin cache auto-regenerates
- Built-in marketplace always available
- Local plugins untouched

**Zero Risk:**
- Custom skills/agents (in dotfiles, not affected)
- Local marketplace (preserved)
- No MCP servers to break (none configured)

**Potential Issues:**
- If built-in marketplace fails, restore from backup
- Ralph-loop commands replace ralph-wiggum (same functionality, different name)

---

## Summary

This plan safely removes duplicate marketplace git clones and consolidates to the built-in official marketplace. All functionality is preserved, with 7 duplicate plugin installations removed. The cleanup reduces complexity while maintaining full plugin access through the built-in marketplace system.
