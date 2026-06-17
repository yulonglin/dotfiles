# Fix Slack MCP Connection + Rename mac-tools → productivity-tools

## Context

`/mcp` shows "Failed to reconnect to slack." Two root causes:

1. **Wrong env vars in plugin.json**: Plugin passes `SLACK_TOKEN`/`SLACK_TEAM_ID`, but `slack-mcp-server` (korotovsky v1.2.3) expects `SLACK_MCP_XOXP_TOKEN`.
2. **Name collision**: Both `slack@claude-plugins-official` and `slack-mcp@mac-tools` define MCP server `"slack"`.

Official Slack/GitHub MCPs confirmed broken as of 2026-03-05 (#30855, #30902).
`SLACK_MCP_XOXP_TOKEN` already exists in `config/secrets.sh`.

## Revised Plan (post-critique)

Two separate concerns → two commits. GitHub rename last (only externally-visible step).

### Phase 1: Fix Slack MCP (bugfix commit)

#### 1a. Fix plugin.json env vars

**File**: `~/code/marketplaces/mac-tools/plugins/slack-mcp/.claude-plugin/plugin.json`

```json
{
  "name": "slack-mcp",
  "version": "1.0.0",
  "description": "Slack workspace — channels, threads, search, reactions, usergroups (korotovsky/slack-mcp-server)",
  "mcpServers": {
    "slack": {
      "command": "slack-mcp-server",
      "args": ["--transport", "stdio"],
      "env": {
        "SLACK_MCP_XOXP_TOKEN": "${SLACK_MCP_XOXP_TOKEN}"
      }
    }
  }
}
```

#### 1b. Disable official slack plugin

Remove `slack@claude-plugins-official` from:
- `.claude/settings.json` (worktree) — line 39, currently `false`
- `.claude/settings.local.json` (worktree) — line 28, currently `true`

Keep `slack-mcp@mac-tools` entries (will be renamed in Phase 2).

#### 1c. Commit both repos
- mac-tools repo: `fix: use SLACK_MCP_XOXP_TOKEN env var for slack-mcp-server`
- dotfiles repo: `fix: disable broken official Slack MCP plugin`

### Phase 2: Rename mac-tools → productivity-tools

#### 2a. Update marketplace manifest (before rename, while path is still mac-tools)

**File**: `~/code/marketplaces/mac-tools/.claude-plugin/marketplace.json`
- `"name": "mac-tools"` → `"name": "productivity-tools"`
- `"description": "Claude Code MCP plugin manifests for macOS apps"` → `"description": "Claude Code MCP plugins — Slack, Things 3, productivity tools"`

Commit in mac-tools repo: `refactor: rename mac-tools → productivity-tools`

#### 2b. Local directory rename + git remote

```bash
mv ~/code/marketplaces/mac-tools ~/code/marketplaces/productivity-tools
cd ~/code/marketplaces/productivity-tools
git remote set-url origin git@github.com:yulonglin/productivity-tools.git
```

#### 2c. Rename GitHub repo (externally-visible step — do after local is ready)

```bash
gh repo rename productivity-tools --repo yulonglin/mac-tools
```

GitHub creates automatic redirect from old URL. Push committed changes.

#### 2d. Update dotfiles config files

**profiles.yaml** (`~/.claude/templates/contexts/profiles.yaml` lines 23-25):
```yaml
# Was:
  mac-tools:
    local: ${CODE_DIR}/marketplaces/mac-tools
    github: yulonglin/mac-tools

# Becomes:
  productivity-tools:
    local: ${CODE_DIR}/marketplaces/productivity-tools
    github: yulonglin/productivity-tools
```

**settings.json** (global, `claude/settings.json` lines 321-328):
```json
// Was:
"extraKnownMarketplaces": {
  "mac-tools": {
    "source": { "source": "directory", "path": "/Users/yulong/code/marketplaces/mac-tools" }
  }
}

// Becomes:
"extraKnownMarketplaces": {
  "productivity-tools": {
    "source": { "source": "directory", "path": "/Users/yulong/code/marketplaces/productivity-tools" }
  }
}
```

**settings.json** (worktree, `.claude/settings.json` line 40):
- `"slack-mcp@mac-tools": false` → `"slack-mcp@productivity-tools": false`

**settings.local.json** (worktree, `.claude/settings.local.json` line 29):
- `"slack-mcp@mac-tools": true` → `"slack-mcp@productivity-tools": true`

#### 2e. Clean stale plugin state (simpler than hand-editing installed_plugins.json)

```bash
# Remove stale entries — let claude-context --sync re-register fresh
# 1. Delete old cache
rm -rf ~/.claude/plugins/cache/mac-tools

# 2. Remove stale key from installed_plugins.json (jq or manual)
# Delete "slack-mcp@mac-tools" key from plugins object

# 3. Update known_marketplaces.json
# Rename "mac-tools" key → "productivity-tools", update path and installLocation
```

**known_marketplaces.json** (`~/.claude/plugins/known_marketplaces.json` lines 34-41):
```json
// Was:
"mac-tools": {
  "source": { "source": "directory", "path": "/Users/yulong/code/marketplaces/mac-tools" },
  "installLocation": "/Users/yulong/code/marketplaces/mac-tools",
  ...
}

// Becomes:
"productivity-tools": {
  "source": { "source": "directory", "path": "/Users/yulong/code/marketplaces/productivity-tools" },
  "installLocation": "/Users/yulong/code/marketplaces/productivity-tools",
  ...
}
```

#### 2f. Run claude-context --sync

Re-registers productivity-tools marketplace, installs plugins fresh.

#### 2g. Commit dotfiles

`refactor: rename mac-tools → productivity-tools marketplace`

## Complete file inventory (from grep)

| File | Reference | Action |
|------|-----------|--------|
| `marketplaces/mac-tools/.claude-plugin/marketplace.json` | `"name": "mac-tools"` | Update name + description |
| `marketplaces/mac-tools/plugins/slack-mcp/.claude-plugin/plugin.json` | env vars | Fix to `SLACK_MCP_XOXP_TOKEN` |
| `claude/settings.json` (global) | `extraKnownMarketplaces.mac-tools` | Rename key + path |
| `claude/templates/contexts/profiles.yaml` | marketplace key, local path, github ref | Rename all three |
| `.claude/settings.json` (worktree) | `slack-mcp@mac-tools` in enabledPlugins | Rename key |
| `.claude/settings.local.json` (worktree) | `slack-mcp@mac-tools` in enabledPlugins | Rename key |
| `~/.claude/plugins/installed_plugins.json` | `slack-mcp@mac-tools` key + installPath | Delete stale entry (sync recreates) |
| `~/.claude/plugins/known_marketplaces.json` | `mac-tools` key + paths | Rename key + paths |
| `~/.claude/plugins/cache/mac-tools/` | Cache directory | Delete (sync recreates) |
| `plans/twinkly-jingling-wigderson.md` | Historical plan doc | No action needed (reference only) |

## Verification

1. After Phase 1: `echo $SLACK_MCP_XOXP_TOKEN | head -c 5` → should show `xoxp-`
2. `gh repo view yulonglin/productivity-tools` — confirms rename
3. `claude-context --sync` completes without errors
4. `claude-context personal` enables slack-mcp
5. Restart Claude Code → `/mcp` shows slack connected
6. Test: list channels via slack MCP tool
