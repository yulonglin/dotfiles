# Things 3 MCP — Plan

## Context

Things 3 is already protected in `clear_mac_apps.conf` but has no MCP integration. Adding a Things 3 MCP server would let Claude Code interact with your task manager — creating tasks, querying views, updating projects — via natural language.

The goal: stand up a Things 3 MCP server, host it (or its manifest) under `~/code/marketplaces/`, and wire it into the dotfiles plugin system so it loads via profile.

---

## Recommendation: Fork `hald/things-mcp`

**Why `hald/things-mcp`** over building from scratch or using `drjforrest/mcp-things3`:

| | hald/things-mcp | drjforrest | from scratch |
|---|---|---|---|
| Tools | 20+ (all views, checklist, tags) | ~7 basic | 0 |
| Maturity | v0.7.3, Feb 2026 | v0.1.0, stalled | — |
| Stack | Python + uv ✓ | Python + pip | Python + uv |
| Connection | URL scheme (safe, native) | AppleScript (fragile) | your choice |
| Maintenance | Active | Dormant | owned by you |

Forking gets 20+ battle-tested tools immediately. Customizations can be layered on top.

---

## Architecture

```
~/code/marketplaces/           ← new marketplace repo (plugin manifests)
└── plugins/
    └── things-mcp/
        ├── plugin.json        ← Claude Code plugin manifest
        └── .mcp.json          ← MCP server connection config

~/code/things-mcp/             ← forked MCP server (actual Python code)
│   (fork of hald/things-mcp)
```

The marketplace repo (`~/code/marketplaces/`) acts as a local plugin source — like `alignment-hive` but for personal/custom servers. The actual server code lives in its own repo.

### Plugin System Integration

1. **`profiles.yaml`** — register `~/code/marketplaces/` as a local marketplace in the `marketplaces:` section
2. **`installed_plugins.json`** — register the things-mcp plugin
3. **`settings.json`** — no new sandbox domains needed (stdio transport, no network calls)
4. **Profile assignment** — add to `base` (always-on) or `workflow` profile

---

## Implementation Steps

### 1. Fork + Clone the MCP Server

```bash
# Fork hald/things-mcp on GitHub, then:
git clone git@github.com:<you>/things-mcp.git ~/code/things-mcp
cd ~/code/things-mcp
uv sync
```

### 2. Verify It Works

```bash
cd ~/code/things-mcp
uv run things-mcp  # should start the MCP server
```

Test with a simple MCP client call to confirm Things 3 integration works.

### 3. Create the Marketplace Repo

```bash
mkdir -p ~/code/marketplaces/plugins/things-mcp
cd ~/code/marketplaces
git init
```

**`plugins/things-mcp/plugin.json`:**
```json
{
  "name": "things-mcp",
  "version": "0.7.3",
  "description": "Things 3 task manager integration via MCP",
  "mcpServers": {
    "things": {
      "command": "uv",
      "args": ["run", "--project", "/Users/yulong/code/things-mcp", "things-mcp"],
      "env": {}
    }
  }
}
```

**`plugins/things-mcp/.mcp.json`:**
```json
{
  "mcpServers": {
    "things": {
      "command": "uv",
      "args": ["run", "--project", "/Users/yulong/code/things-mcp", "things-mcp"]
    }
  }
}
```

### 4. Register in Plugin System

**`profiles.yaml`** — add local marketplace:
```yaml
marketplaces:
  - name: personal
    path: ~/code/marketplaces   # local filesystem marketplace
    # existing marketplaces...
```

**Profile assignment** (e.g., base):
```yaml
base:
  plugins:
    - things-mcp
```

Run `claude-context --sync` to register.

### 5. Commit Both Repos

- `~/code/things-mcp`: commit as fork with any customizations
- `~/code/marketplaces/`: commit plugin manifest
- `dotfiles`: commit `profiles.yaml` + `installed_plugins.json` changes

---

## Verification

1. `claude-context --list` — confirms things-mcp shows as enabled
2. Start a Claude Code session → check `/mcp` or ask Claude to "show my Things inbox"
3. Test: "Create a task in Things: Review MCP integration"
4. Verify in Things 3 app that the task appears

---

## Open Questions (pre-approval)

- Fork vs. from-scratch? (fork strongly recommended unless custom features require different architecture)
- Any custom tools/features beyond hald's 20+? (e.g., recurring task creation, area-specific queries, Obsidian/Notion cross-linking)
- Which profile: `base` (always-on every session) or `workflow` (explicit opt-in)?
- Hardcode `~/code/things-mcp` path or make it configurable via env var?
