# Things 3 + Slack MCP — mac-tools Marketplace Plan

## Context

Neither Things 3 nor the existing Slack MCP fork is wired into the dotfiles plugin system. The Slack fork already exists at `~/code/marketplaces/slack-mcp-server` (`github.com/yulonglin/slack-mcp-server`, fork of korotovsky, with custom security hardening + channel recency sorting). Goal: fork Things 3, move the Slack fork to `~/code/mcps/`, create a `mac-tools` manifest repo on GitHub, and wire both into the plugin system via a new `personal` profile.

---

## Final Architecture

```
~/code/mcps/                                    ← MCP server code (forks)
├── slack-mcp-server/                           ← moved from ~/code/marketplaces/slack-mcp-server/
└── things-mcp/                                 ← new fork of hald/things-mcp

~/code/marketplaces/mac-tools/                  ← new manifest repo (github.com/yulonglin/mac-tools)
├── .claude-plugin/
│   └── marketplace.json                        ← REQUIRED for claude-context to detect local marketplace
└── plugins/
    ├── things-mcp/
    │   └── .claude-plugin/
    │       └── plugin.json                     ← plugin.json MUST be inside .claude-plugin/
    └── slack-mcp/
        └── .claude-plugin/
            └── plugin.json
```

### profiles.yaml entry (follows ai-safety-plugins pattern)

```yaml
marketplaces:
  mac-tools:
    local: ${CODE_DIR}/marketplaces/mac-tools
    github: yulonglin/mac-tools
```

---

## Server Selection

### Things 3: Fork `hald/things-mcp`
325 stars, v0.7.3, Feb 2026, active. Python + uv. 20+ tools via Things URL scheme. All views, checklists, tags, areas, search.

### Slack: Existing fork `yulonglin/slack-mcp-server`
Fork of korotovsky/slack-mcp-server (1.4k stars). Currently at `~/code/marketplaces/slack-mcp-server/` — to be moved to `~/code/mcps/slack-mcp-server/`. Custom commits: "Add channel recency sorting and security hardening". Binary already built.

---

## Implementation Steps

### 1. Move Slack Fork to ~/code/mcps/

```bash
mkdir -p ~/code/mcps
mv ~/code/marketplaces/slack-mcp-server ~/code/mcps/slack-mcp-server
cd ~/code/mcps/slack-mcp-server

# Verify upstream remote exists (add if missing)
git remote get-url upstream 2>/dev/null || \
  git remote add upstream https://github.com/korotovsky/slack-mcp-server.git

git fetch upstream
git log upstream/main..HEAD --oneline   # review custom commits
git rebase upstream/main                # brings in upstream, preserves custom commits
go build -o slack-mcp-server .
git push --force-with-lease origin main  # rebase requires force-push
```

### 2. Fork + Clone Things 3

```bash
# Fork on GitHub (--fork-name flag does NOT exist in gh; default name is fine)
gh repo fork hald/things-mcp --clone=false

# Clone locally
git clone git@github.com:yulonglin/things-mcp.git ~/code/mcps/things-mcp
# Note: no uv sync needed — plugin uses uvx --from git+https://... directly
```

### 3. Create mac-tools Repo on GitHub + Init Locally

```bash
gh repo create yulonglin/mac-tools --public \
  --description "Claude Code MCP plugin manifests for macOS apps"

mkdir -p ~/code/marketplaces/mac-tools
cd ~/code/marketplaces/mac-tools
git init
git remote add origin git@github.com:yulonglin/mac-tools.git
```

### 4. Create Marketplace Structure

**Required structure** (`.claude-plugin/` at both marketplace root AND each plugin dir):

```bash
mkdir -p ~/code/marketplaces/mac-tools/.claude-plugin
mkdir -p ~/code/marketplaces/mac-tools/plugins/things-mcp/.claude-plugin
mkdir -p ~/code/marketplaces/mac-tools/plugins/slack-mcp/.claude-plugin
```

**`~/code/marketplaces/mac-tools/.claude-plugin/marketplace.json`:**
```json
{
  "$schema": "https://anthropic.com/claude-code/marketplace.schema.json",
  "name": "mac-tools",
  "plugins": [
    { "name": "things-mcp", "source": "./plugins/things-mcp", "version": "0.1.0" },
    { "name": "slack-mcp",  "source": "./plugins/slack-mcp",  "version": "1.0.0" }
  ]
}
```

**`plugins/things-mcp/.claude-plugin/plugin.json`:**
```json
{
  "name": "things-mcp",
  "version": "0.1.0",
  "description": "Things 3 task manager — all views, projects, tags, checklists",
  "mcpServers": {
    "things": {
      "command": "uvx",
      "args": ["--from", "git+https://github.com/yulonglin/things-mcp", "things-mcp"]
    }
  }
}
```

**`plugins/slack-mcp/.claude-plugin/plugin.json`:**
```json
{
  "name": "slack-mcp",
  "version": "1.0.0",
  "description": "Slack extensions — reactions, usergroups, unreads (adds to Claude.ai Slack)",
  "mcpServers": {
    "slack": {
      "command": "slack-mcp-server",
      "args": ["--transport", "stdio"],
      "env": {
        "SLACK_TEAM_ID": "${SLACK_TEAM_ID}",
        "SLACK_TOKEN": "${SLACK_TOKEN}"
      }
    }
  }
}
```

Note: `slack-mcp-server` referenced by name only (not hardcoded path) — requires the binary to be on PATH. Install step:
```bash
cd ~/code/mcps/slack-mcp-server && go install .
# Binary lands at ~/go/bin/slack-mcp-server (ensure ~/go/bin is in PATH)
```

### 5. Commit and Push mac-tools (BEFORE claude-context --sync)

```bash
cd ~/code/marketplaces/mac-tools
git add -A
git commit -m "feat: add things-mcp and slack-mcp plugin manifests"
git push -u origin main
```

### 6. Register in Dotfiles

**Edit `claude/templates/contexts/profiles.yaml`:**

```yaml
marketplaces:
  # ... existing entries
  mac-tools:
    local: ${CODE_DIR}/marketplaces/mac-tools
    github: yulonglin/mac-tools

profiles:
  # ... existing profiles
  personal:
    comment: "Life and productivity — Things 3, Slack extensions"
    enable:
      - things-mcp
      - slack-mcp
```

**Commit the dotfiles change:**
```bash
cd ~/code/dotfiles
git add claude/templates/contexts/profiles.yaml
git commit -m "feat: add mac-tools marketplace and personal profile"
git push
```

### 7. Sync + Activate

```bash
claude-context --sync          # registers mac-tools, updates installed_plugins.json
claude-context personal        # activates plugins in settings.json (required separate step)
```

### 8. Slack Auth

Ensure in `~/.zshenv`:
```bash
export SLACK_TOKEN="xoxb-..."
export SLACK_TEAM_ID="T..."
```

### 9. Custom Extensions (v2 — after core works)

**Things 3 additions** (in fork at `~/code/mcps/things-mcp/`):
- NL scheduling: `dateparser` → "next Monday" into Things date format in `create_task`/`update_task`
- Cross-app linking: `link_to_task(task_id, url, app)` appends URL to task notes
- Bulk ops: `bulk_complete/tag/move(task_ids, ...)` over filter results

**Slack additions** (in fork at `~/code/mcps/slack-mcp-server/`):
- Reaction aliases ("done" → `:white_check_mark:`)

---

## Critical Files (Dotfiles)

| File | Change |
|------|--------|
| `claude/templates/contexts/profiles.yaml` | Add `mac-tools` marketplace + `personal` profile |
| `claude/plugins/installed_plugins.json` | Auto-updated by `claude-context --sync` |
| `claude/settings.json` | No new sandbox domains (stdio transport) |

---

## Verification

1. `which slack-mcp-server` → confirms binary is on PATH
2. `claude-context --list` → things-mcp + slack-mcp show under `personal`
3. Start Claude Code session with `personal` profile
4. "Show my Things inbox" → task list appears
5. "React 👍 to last message in #general" → reaction appears in Slack
6. "Create Things task: Review mac-tools integration, due next Monday" → task with correct date

Smoke tests before wiring:
```bash
# Things 3
uvx --from git+https://github.com/yulonglin/things-mcp things-mcp --help

# Slack
echo '{"jsonrpc":"2.0","method":"initialize","id":1,"params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1"}}}' | slack-mcp-server --transport stdio
```

---

## New Repos Summary

| Repo | Local path | Status |
|------|-----------|--------|
| `mac-tools` | `~/code/marketplaces/mac-tools/` | new (manifests only) |
| `things-mcp` | `~/code/mcps/things-mcp/` | new fork of hald/things-mcp |
| `slack-mcp-server` | `~/code/mcps/slack-mcp-server/` | existing fork — move + sync upstream |
