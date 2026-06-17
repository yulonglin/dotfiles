# Fix: Remove stale Notion plugin entry

## Context
The "Notion" plugin (capital N) was installed from `claude-plugins-official` but no longer exists in that marketplace. The `/plugin` UI shows an error and can't remove it because it tries user scope but it's installed at local scope.

## Steps
1. Edit `~/.claude/plugins/installed_plugins.json` — remove the `"Notion@claude-plugins-official"` entry (lines 315-325)
2. Remove cached plugin directory: `~/.claude/plugins/cache/claude-plugins-official/Notion/`

## Verification
- Run `/plugin` → Errors tab should no longer show the Notion error
