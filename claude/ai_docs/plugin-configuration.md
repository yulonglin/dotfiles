# Plugin Configuration

Common plugin configuration tweaks and troubleshooting for Claude Code.

## Serena: Disable Auto-Opening Dashboard

**Problem:** Serena's web dashboard (`http://127.0.0.1:24286/dashboard/index.html`) opens automatically in your browser every time a new Claude Code session starts.

**Solution:** Add `--open-web-dashboard false` flag to the MCP server args.

**File:** `claude/plugins/marketplaces/claude-plugins-official/external_plugins/serena/.mcp.json`

```json
{
  "serena": {
    "command": "uvx",
    "args": [
      "--from",
      "git+https://github.com/oraios/serena",
      "serena",
      "start-mcp-server",
      "--open-web-dashboard",
      "false"
    ]
  }
}
```

**Notes:**
- This file is in the plugin marketplace cache (`plugins/marketplaces/`), which is gitignored
- Change must be reapplied after clearing plugin cache or on new machines
- Dashboard remains accessible at `http://127.0.0.1:24286/dashboard/index.html` when needed
- Requires full Claude Code restart to take effect

**Verification:**
```bash
# After restart, check MCP logs if needed
tail -f ~/.claude/logs/mcp-serena.log
```
