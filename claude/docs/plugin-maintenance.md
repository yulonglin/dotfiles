# Plugin Maintenance

## Renaming a Local Marketplace Plugin

Update these four locations, then restart Claude Code:

1. **Source**: Rename dir `claude/ai-safety-plugins/plugins/<old>/` → `<new>/`, update `"name"` in `.claude-plugin/plugin.json`
2. **Marketplace manifest**: Update entry in `claude/ai-safety-plugins/.claude-plugin/marketplace.json`
3. **settings.json**: Change `"<old>@ai-safety-plugins"` → `"<new>@ai-safety-plugins"` in `enabledPlugins`
4. **Clear cache**: `rm -rf ~/.claude/plugins/cache/ai-safety-plugins/<old>` (re-created on next `/plugin` install)
