# Consolidate Third-Party Repos + Plugin Cleanup

## Context

Third-party Claude-related repos are scattered: `slack-mcp-server` in `~/code/`, `ui-ux-pro-max-skill` in `~/scratch/`. Consolidate to `~/code/marketplaces/` for cleaner organization. Also clean up accumulated plugin cruft.

**Key facts (confirmed via Claude Code docs):**
- Disabled plugins are **completely excluded from context** — current install-globally-disable-by-default pattern is correct
- `ui-ux-pro-max-skill` is registered as a GitHub source — Claude CLI manages its own clone. Moving `~/scratch/` copy is pure filesystem cleanup, no re-registration needed
- Only `slack-mcp-server` MCP binary path needs updating after move

## Step 1: Move repos to `~/code/marketplaces/`

```bash
mkdir -p ~/code/marketplaces
mv ~/code/slack-mcp-server ~/code/marketplaces/
mv ~/scratch/ui-ux-pro-max-skill ~/code/marketplaces/
```

## Step 2: Update `install.sh` MCP base path

**File:** `install.sh:296`

Change `mcp_base="$HOME/code"` → `mcp_base="$HOME/code/marketplaces"` so future `MCP_SERVERS_LOCAL` clones go to the consolidated directory.

## Step 3: Re-register slack MCP server

Binary path changes: `.../code/slack-mcp-server/...` → `.../code/marketplaces/slack-mcp-server/...`

```bash
claude mcp remove slack
# Then re-run install.sh which re-registers with correct path:
./install.sh --minimal --ai-tools
```

## Step 4: Plugin cruft cleanup

### 4a. Remove orphaned thedotmack marketplace (~176MB)

Not in `known_marketplaces.json`, no plugins referenced anywhere.

```bash
trash ~/.claude/plugins/marketplaces/thedotmack/
```

### 4b. Remove zombie `insights-toolkit` references

**File:** `claude/settings.json` — delete `"insights-toolkit@local-marketplace": false`

**Files:** `claude/templates/contexts/*.json` — delete any `insights-toolkit` entries from all profiles

### 4c. Clean up deploy.sh

**File:** `deploy.sh`

- Remove dead `deploy_plugins_config()` function (~lines 387-409) that references non-existent `.json.template` files
- Extend marketplace registration block (~line 462) to also register `claude-plugins-official` and `ui-ux-pro-max-skill`

### 4d. Update local-marketplace README

**File:** `claude/local-marketplace/README.md` — fix outdated plugin names (`code-quality` → `code-toolkit`, add `workflow-toolkit`, `viz-toolkit`)

## Verification

1. `ls ~/code/marketplaces/` — contains `slack-mcp-server/`, `ui-ux-pro-max-skill/`
2. `claude mcp list` — slack shows new path, connects OK
3. `claude plugin marketplace list` — all 3 marketplaces registered
4. `grep -r "insights-toolkit" claude/settings.json claude/templates/` — no matches
5. `ls ~/.claude/plugins/marketplaces/` — no `thedotmack/`
