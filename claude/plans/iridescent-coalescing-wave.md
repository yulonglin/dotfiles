# Debug: Serena Dashboard Auto-Opening on Session Start

## Problem Statement

Serena website (`http://127.0.0.1:24286/dashboard/index.html`) opens automatically every time a new Claude Code session starts.

## Root Cause Analysis (Phase 1 Complete)

**Evidence gathered:**

1. **URL is localhost dashboard**: Not serena.oraios.com, but `http://127.0.0.1:24286/dashboard/index.html`
   - This is Serena's local debugging/monitoring web server
   - Confirms it's started by the MCP server process, not a website redirect

2. **Process confirmation**: `lsof` shows Python process listening on port 24286
   ```
   python3.1 99162 yulong 4u IPv4 ... TCP localhost:24286 (LISTEN)
   ```

3. **MCP server configuration**: Serena plugin configured in `claude/settings.json`
   ```json
   "serena@claude-plugins-official": true
   ```

   MCP command: `uvx --from git+https://github.com/oraios/serena serena start-mcp-server`
   (from `claude/plugins/marketplaces/claude-plugins-official/external_plugins/serena/.mcp.json`)

4. **Launch mechanism**: Shell script wrapper calls `serena.cli.top_level()`
   - Located: `~/.cache/uv/archive-v0/tC49FIEHO4Q4Z5uF0CSX2/bin/serena`

**Root cause hypothesis**: The `start-mcp-server` command has browser auto-launch enabled by default, likely via a `--open-browser` flag or similar configuration.

## Solution Options

### Option 1: Disable Browser Auto-Launch via MCP Args (Recommended) ✅

**Approach**: Add `--open-web-dashboard false` flag to the MCP server launch command

**CONFIRMED**: Serena supports this flag:
```
--open-web-dashboard BOOLEAN    Open Serena's dashboard in your browser
                                after MCP server startup (overriding the
                                setting in Serena's config).
```

**Critical files:**
- `claude/plugins/marketplaces/claude-plugins-official/external_plugins/serena/.mcp.json` - MCP server config (symlinked from dotfiles)

**Steps:**
1. Edit `.mcp.json`:
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

2. Restart Claude Code session to apply changes

**Pros:**
- ✅ Official flag - confirmed working
- ✅ Clean solution - disables at source
- ✅ Preserves dashboard for manual access when needed
- ✅ Standard pattern for dev servers

**Cons:**
- None - this is the correct solution

### Option 2: Disable Serena Plugin Entirely

**Approach**: Remove Serena from enabled plugins if you're not actively using its features

**Critical files:**
- `claude/settings.json` - Plugin enablement config

**Steps:**
1. Edit `claude/settings.json`:
   ```json
   "enabledPlugins": {
     // ...
     "serena@claude-plugins-official": false,  // Change true → false
     // ...
   }
   ```

2. Restart Claude Code

**Pros:**
- Immediate fix, no research needed
- Saves resources if Serena not actively used

**Cons:**
- Loses Serena's semantic code analysis features
- Nuclear option if you want to keep the plugin

### Option 3: Use Serena Config File (If Available)

**Approach**: Check if Serena supports a config file (`.serenarc`, `serena.toml`, etc.) to disable browser launch

**Critical files:**
- Potentially: `~/.serenarc` or project-specific config

**Steps:**
1. Search Serena documentation/GitHub for config options
2. Create config file with `open_browser: false` or equivalent
3. Restart Claude Code

**Pros:**
- More maintainable than CLI args
- Config versioned in dotfiles

**Cons:**
- Depends on Serena supporting this
- Requires documentation lookup

## Recommended Approach

**Option 1** (disable via MCP args) is the **confirmed solution** - Serena supports `--open-web-dashboard false`.

**No fallback needed** - this is the correct fix.

## Verification Plan

After implementing fix:

1. **Restart Claude Code** completely (exit and relaunch)
2. **Verify browser doesn't open** on new session
3. **Manually test dashboard** is still accessible:
   ```bash
   open http://127.0.0.1:24286/dashboard/index.html
   ```
   (Should work if port 24286 is listening)
4. **Verify Serena MCP tools work**:
   - Try using Serena tools in a conversation
   - Check `~/.claude/logs/mcp-serena.log` for errors

## Implementation Steps

1. ✅ **DONE**: Confirmed flag exists (`--open-web-dashboard false`)
2. **TODO**: Edit `claude/plugins/marketplaces/claude-plugins-official/external_plugins/serena/.mcp.json`
3. **TODO**: Test by restarting Claude Code
4. **TODO**: Verify dashboard still accessible manually if needed
5. **TODO**: Consider documenting in CLAUDE.md if this is common

## Notes

- Serena dashboard is useful for debugging LSP issues, so preserving access (just not auto-launch) is preferred
- If Serena doesn't support disabling browser launch, consider filing a GitHub issue/feature request
- Current Serena install: git+https://github.com/oraios/serena (latest from main branch)
