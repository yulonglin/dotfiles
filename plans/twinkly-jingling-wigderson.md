# Things 3 + Slack MCP — Productivity Plugins Plan

## Context

Neither Things 3 nor a self-hosted Slack MCP is currently integrated. Adding both would let Claude Code interact with your task manager and Slack natively — creating tasks, querying views, reacting to messages, tracking unreads — all via natural language.

Goal: stand up both MCP servers, host their manifests under a single `mac-tools` marketplace repo, and wire into the dotfiles plugin system via a new `personal` profile.

---

## Marketplace Naming: `mac-tools`

The unifying theme is "Claude talking to native macOS desktop apps" (Things via URL scheme, Slack via API, potentially Calendar / Reminders / Contacts someday). Recommendation: **`mac-tools`**.

```
~/code/marketplaces/mac-tools/     ← new marketplace repo
└── plugins/
    ├── things-mcp/
    │   ├── plugin.json
    │   └── .mcp.json
    └── slack-mcp/
        ├── plugin.json
        └── .mcp.json

~/code/things-mcp/                 ← fork of hald/things-mcp (Python + uv)
~/code/slack-mcp/                  ← fork of korotovsky/slack-mcp-server (Go)
```

---

## Server Selection

### Things 3: Fork `hald/things-mcp`

| | |
|---|---|
| Stars | 325, v0.7.3 (Feb 2026), active |
| Stack | Python + things.py + uv |
| Tools | 20+ (all views, checklist, tags, areas, search) |
| Connection | Things URL scheme (safe, native) |

### Slack: Fork `korotovsky/slack-mcp-server`

| | |
|---|---|
| Stars | 1.4k, 245 forks, active |
| Stack | Go, stdio/SSE/HTTP transports |
| Tools | 15 tools (reactions, usergroups, unreads, smart history caching) |
| Auth | Browser tokens (xoxc/xoxd), Bot token, or User OAuth |

**Why korotovsky over alternatives:** Complements your existing Claude.ai Slack integration. The Claude.ai tools already handle send/read/search — korotovsky adds the gaps: reaction management, user groups, unreads tracking, message editing, and smart history caching. No permission creep.

---

## Implementation Steps

### 1. Fork + Clone Both Servers

```bash
# Fork hald/things-mcp and korotovsky/slack-mcp-server on GitHub, then:
git clone git@github.com:<you>/things-mcp.git ~/code/things-mcp
git clone git@github.com:<you>/slack-mcp.git ~/code/slack-mcp

cd ~/code/things-mcp && uv sync
cd ~/code/slack-mcp && go build .  # or: go install .
```

### 2. Create the mac-tools Marketplace Repo

```bash
mkdir -p ~/code/marketplaces/mac-tools/plugins/{things-mcp,slack-mcp}
cd ~/code/marketplaces/mac-tools && git init
```

**`plugins/things-mcp/plugin.json`:**
```json
{
  "name": "things-mcp",
  "version": "0.7.3",
  "description": "Things 3 task manager — all views, projects, tags, checklists",
  "mcpServers": {
    "things": {
      "command": "uv",
      "args": ["run", "--project", "/Users/yulong/code/things-mcp", "things-mcp"]
    }
  }
}
```

**`plugins/slack-mcp/plugin.json`:**
```json
{
  "name": "slack-mcp",
  "version": "1.0.0",
  "description": "Slack — reactions, usergroups, unreads, history (complements Claude.ai Slack)",
  "mcpServers": {
    "slack": {
      "command": "/Users/yulong/code/slack-mcp/slack-mcp-server",
      "args": ["--transport", "stdio"],
      "env": {
        "SLACK_TOKEN": "${SLACK_TOKEN}"
      }
    }
  }
}
```

(`.mcp.json` mirrors `mcpServers` block from each `plugin.json`)

### 3. Register mac-tools in Plugin System

**`profiles.yaml`** — add local marketplace:
```yaml
marketplaces:
  - name: mac-tools
    path: ~/code/marketplaces/mac-tools
    type: local
  # ... existing marketplaces
```

**New `personal` profile:**
```yaml
profiles:
  personal:
    description: "Life and productivity tools — Things 3, Slack extensions"
    plugins:
      - things-mcp
      - slack-mcp
```

Run `claude-context --sync` to register, then `claude-context personal` (or compose: `claude-context code personal`).

### 4. Slack Auth Setup

korotovsky supports multiple auth methods. Simplest for personal use:
- Browser tokens (xoxc + xoxd cookies from browser devtools) — no scope configuration needed
- Or: create a Slack Bot with scopes `channels:history`, `reactions:write`, `usergroups:read` etc.

Store token in `~/.zshenv`: `export SLACK_TOKEN="xoxb-..."` (picked up by the plugin env block above).

### 5. Custom Extensions (v2, after core works)

**Things 3:**
- **Natural language scheduling** — `dateparser` library: "next Monday" → Things date format, wired into `create_task`/`update_task`
- **Cross-app linking** — `link_to_task(task_id, url, app)` appends structured URL to task notes; Claude can create a Things task + link to Linear issue in one shot
- **Bulk operations** — `bulk_complete(task_ids)`, `bulk_tag(task_ids, tags)`, `bulk_move(task_ids, project_id)`

**Slack (gaps korotovsky doesn't cover):**
- Custom reaction aliases ("use :white_check_mark: for done" → maps to API call)

---

## Critical Files to Modify (Dotfiles)

| File | Change |
|------|--------|
| `claude/templates/contexts/profiles.yaml` | Add `mac-tools` marketplace + `personal` profile |
| `claude/plugins/installed_plugins.json` | Register things-mcp + slack-mcp |
| `claude/settings.json` | No new sandbox domains needed (stdio transport) |

---

## Verification

1. `claude-context --list` — confirms things-mcp + slack-mcp show as registered
2. `claude-context personal` → start Claude Code session
3. Ask: "Show my Things inbox" → tasks appear
4. Ask: "Add a reaction 👍 to the last message in #general" → reaction appears in Slack
5. Ask: "Create a Things task: Review mac-tools MCP integration, due next Monday" → task appears with correct date

---

## New Repos Summary

| Repo | Location | Base |
|------|----------|------|
| `mac-tools` | `~/code/marketplaces/mac-tools/` | new (manifests only) |
| `things-mcp` | `~/code/things-mcp/` | fork of hald/things-mcp |
| `slack-mcp` | `~/code/slack-mcp/` | fork of korotovsky/slack-mcp-server |
