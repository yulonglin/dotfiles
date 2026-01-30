# Plugin Maintenance

## Renaming a Local Marketplace Plugin

Update these four locations, then restart Claude Code:

1. **Source**: Rename dir `claude/local-marketplace/plugins/<old>/` → `<new>/`, update `"name"` in `.claude-plugin/plugin.json`
2. **Marketplace manifest**: Update entry in `claude/local-marketplace/.claude-plugin/marketplace.json`
3. **settings.json**: Change `"<old>@local-marketplace"` → `"<new>@local-marketplace"` in `enabledPlugins`
4. **Clear cache**: `rm -rf ~/.claude/plugins/cache/local-marketplace/<old>` (re-created on next `/plugin` install)
