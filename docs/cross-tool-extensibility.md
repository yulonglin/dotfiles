# Cross-Tool Extensibility Map

How extensibility concepts map across Claude Code, Codex CLI, and Antigravity (`agy` CLI, Antigravity 2.0 App, and Antigravity IDE).

> **Note:** Gemini CLI was retired by Google on 2026-06-18. Its successor is Antigravity, whose shared global customization root is `~/.gemini/config/`. Portable Claude Code config projects one-way into `~/.gemini/config/` via `deploy.sh --antigravity` (`scripts/sync_claude_to_antigravity.sh`): `skills.json` references `~/.claude/skills` with Claude-only excludes, `GEMINI.md` symlinks to `claude/CLAUDE.md`, `AGENTS.md` provides the Antigravity tool-compatibility shim (`antigravity/AGENTS.md`), portable `claude/rules/*.md` are projected into `~/.gemini/config/rules/` with `trigger: always_on` frontmatter, `mcp_config.json` is synced via `scripts/helpers/sync_mcp_servers.py` (seeding `context7`, macOS `bear`, and `slack` via `custom_bins/slack-mcp-stdio`), and `~/.gemini/antigravity-cli/settings.json` receives managed defaults (`agentMode: "auto"`, `enableTerminalSandbox: true`), curated Antigravity permissions (`antigravity/permissions.json`), and portable Claude Bash token-prefix rules via `scripts/helpers/sync_antigravity_settings.py`. Claude hooks are intentionally not auto-imported because of incompatible JSON contracts and synchronous-only hook execution.

## Concept Mapping

| Concept | Claude Code | Codex CLI | Antigravity (`~/.gemini/config/`) |
|---------|-------------|-----------|-----------------------------------|
| **Skills** | `~/.claude/skills/` (`SKILL.md`) | `~/.codex/skills/` (symlink to `../claude/skills`) | `~/.gemini/config/skills.json` (points at `~/.claude/skills` with `exclude`) |
| **Agents** | `~/.claude/agents/*.md` | Not native | Native `define_subagent` / `swarm` / `run_workflow` (do not mirror `claude/agents/`) |
| **Plugins/Extensions** | Plugins (`settings.json` `enabledPlugins`) | Marketplaces + `[plugins]` in `config.toml` | `~/.gemini/config/plugins/` (`plugin.json`) |
| **Hooks** | `settings.json` (snake_case, exit 2 blockers, async supported) | `codex/hooks.json` (curated via `sync_codex_hooks.py`) | `~/.gemini/config/hooks.json` (camelCase, JSON stdout, sync-only — curate separately) |
| **MCP Servers** | `settings.json` / `~/.claude.json` (JSON) | `config.toml` (TOML, synced via `sync_mcp_servers.py`) | `~/.gemini/config/mcp_config.json` (JSON, synced via `sync_mcp_servers.py`) |
| **Global Rules** | `~/.claude/CLAUDE.md` + `~/.claude/rules/*.md` | `~/.codex/AGENTS.md` + `tool-compatibility.md` | `~/.gemini/config/GEMINI.md` + `AGENTS.md` + `rules/*.md` (24 KB per-file cap, `trigger:` frontmatter) |
| **Output Styles** | `output-styles/*.md` | Not supported | Not supported |
| **Task Management** | TodoWrite/TaskCreate | Native plan tool | Artifacts / checklist |
| **LSP Servers** | Via plugins | Not supported | IDE-native |

## What Syncs Cleanly

All three tools use **SKILL.md with YAML frontmatter** for skills. **All skill types sync**, deduplicated by name:

- **User skills**: Real directories in `claude/skills/` (e.g., `commit/`, `spec-interview/`)
- **Standalone skills**: Single `.md` files in `claude/skills/` (wrapped in a directory for target)
- **Plugin skills**: From `plugins/marketplaces/` and `plugins/cache/` (deduplicated — see below)
- **Agent skills**: Claude agents (`agents/*.md`) wrapped as SKILL.md for Codex/Gemini

### Deduplication

The enumerate helper (`scripts/helpers/enumerate_claude_skills.sh`) emits skills in priority order and deduplicates by name (first-wins):

1. **User skills** — highest priority (your custom skills always win)
2. **Standalone skills** — `.md` files directly in `skills/`
3. **Plugin skills from `marketplaces/`** — canonical, git-cloned, always latest
4. **Plugin skills from `cache/ai-safety-plugins/`** — a stale tier. That marketplace is retired and its plugins are tombstoned in `enabledPlugins`, but its cache directory survives with 36 `SKILL.md` files, so this tier still exports retired skills to Codex and Gemini. Dedup is by name, so any cached skill whose name now exists under `claude/skills/` is shadowed by tier 1; the ones dropped rather than migrated are not, and clearing the cache is what actually removes them
5. **Plugin skills from remaining `cache/`** — versioned snapshots (may be stale)
6. **Agent skills** — lowest priority

When a skill name appears in multiple sources, only the highest-priority source is used. Shadowed skills emit warnings to stderr (e.g., `⚠ Skill "brainstorming" from cache/... shadowed by marketplaces/...`).

### Known Issue: Plugin Symlink Duplication

Claude Code's plugin system creates symlinks in `~/.claude/skills/` pointing to `plugins/cache/` and `plugins/marketplaces/`. These cause every plugin skill to appear **twice** in the slash command picker: once as "(user)" from the symlink, once as "(plugin-name)" from the plugin registry. Related: [#14549](https://github.com/anthropics/claude-code/issues/14549), [#21891](https://github.com/anthropics/claude-code/issues/21891).

**Workarounds:**
- `clean-skill-dupes` alias removes the symlinks
- `deploy.sh` auto-cleans during Claude Code deployment
- Symlinks are **recreated on startup/plugin-sync**, so cleanup may need to be repeated

## What Needs Translation

| Source (Claude Code) | Target | Translation |
|---------------------|--------|-------------|
| MCP config (JSON) | Codex `config.toml` | JSON → TOML (deferred) |
| MCP config (JSON) | Gemini `settings.json` | Restructure JSON keys |
| Hooks (JSON, 12+ events) | Gemini hooks (4 events) | Map event names, subset |
| Hooks (JSON) | Codex (notify only) | Minimal — only completion events |
| Permissions (`settings.json`) | Codex rules (`.rules`) | Via `convert_claude_perms.py` |
| Permissions (`settings.json`) | Gemini policies (`.toml`) | Via `convert_claude_perms.py` |
| `CLAUDE.md` | `GEMINI.md` / `instructions.md` | Pointer file (already done) |

## What Doesn't Sync

| Feature | Tool | Notes |
|---------|------|-------|
| Output Styles | Claude Code only | `output-styles/*.md` |
| LSP Servers | Claude Code only | Via plugins |
| Task Management | Claude Code only | TodoWrite/TaskCreate |
| Gemini Extensions | Gemini CLI only | Different bundle format than Claude plugins |
| Codex Profiles | Codex CLI only | `config.toml` profiles feature |

## Sync Scripts

### Usage

```bash
# Deploy Antigravity global config (skills.json, rules, AGENTS.md/GEMINI.md, MCP)
./deploy.sh --only antigravity
# Or run the sync script directly:
scripts/sync_claude_to_antigravity.sh

# Sync skills, permissions, hooks, and MCP to Codex CLI
scripts/sync_claude_to_codex.sh
```

### What They Do

- **`scripts/sync_claude_to_antigravity.sh`** projects one-way into `~/.gemini/config/` (never bidirectional): symlinks `antigravity/skills.json` (referencing `~/.claude/skills` with Claude-only excludes), symlinks `antigravity/AGENTS.md` and `claude/CLAUDE.md` (`GEMINI.md`), renders portable `claude/rules/*.md` into `~/.gemini/config/rules/` with `trigger: always_on` frontmatter (pruning deleted managed rules, preserving hand-authored rules), and syncs `mcp_config.json` via `sync_mcp_servers.py`.
- **`scripts/sync_claude_to_codex.sh`** shares user skills via the `codex/skills -> ../claude/skills` symlink, translates Claude permissions to `codex/rules/default.rules`, syncs shared MCP servers, and applies curated Codex hooks via `scripts/setup/sync_codex_hooks.py`.

### `.gitignore` Strategy

`claude/skills/.gitignore` uses a **whitelist approach** (`*` then `!pattern`) to only track user-authored skills. Runtime symlinks and agent wrappers created by Claude Code are automatically ignored. When adding a new user skill, add corresponding `!dirname/` and `!dirname/**` entries.

### Shared Helper

`scripts/helpers/enumerate_claude_skills.sh` outputs tab-separated lines:

```
<type>\t<name>\t<path>
```

Types: `user_skill`, `standalone_skill`, `plugin_skill`, `agent_skill`

```bash
# Direct usage
bash scripts/helpers/enumerate_claude_skills.sh

# With custom claude dir
bash scripts/helpers/enumerate_claude_skills.sh /path/to/.claude

# Source in another script
source scripts/helpers/enumerate_claude_skills.sh
enumerate_claude_skills "$HOME/.claude" | while IFS=$'\t' read -r type name path; do
    echo "$type: $name at $path"
done
```

## Tool-Specific Docs

- Claude Code: [claude.ai/docs](https://docs.anthropic.com/en/docs/claude-code)
- Codex CLI: [github.com/openai/codex](https://github.com/openai/codex)
- Gemini CLI: [github.com/google-gemini/gemini-cli](https://github.com/google-gemini/gemini-cli)

## Future Work

- MCP server sync (JSON ↔ TOML translation for Codex)
- Hook sync (event name mapping Claude ↔ Gemini)
- Gemini Extension creation from Claude plugins
- `deploy.sh` integration (`--codex`, `--gemini` flags)
