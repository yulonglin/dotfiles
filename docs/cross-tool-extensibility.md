# Cross-Tool Extensibility Map

How extensibility concepts map across Claude Code, Codex CLI, and Gemini CLI.

## Concept Mapping

| Concept | Claude Code | Codex CLI | Gemini CLI |
|---------|-------------|-----------|------------|
| **Skills** | `~/.claude/skills/` (SKILL.md) | `~/.codex/skills/` (SKILL.md) | `~/.gemini/skills/` (SKILL.md) |
| **Agents** | `~/.claude/agents/*.md` | Not native | Not native |
| **Plugins/Extensions** | Plugins (`installed_plugins.json`) | Not supported | Extensions (`~/.gemini/extensions/`) |
| **Hooks** | `settings.json` (12+ events) | `config.toml` (notify only) | `settings.json` (4 events) |
| **MCP Servers** | `.mcp.json` / `~/.claude.json` (JSON) | `config.toml` (TOML, stdio only) | `settings.json` (JSON) |
| **Context File** | `CLAUDE.md` | `instructions.md` | `GEMINI.md` |
| **Slash Commands** | Via skills | `~/.codex/*.md` | `~/.gemini/commands/*.toml` |
| **Output Styles** | `output-styles/*.md` | Not supported | Not supported |
| **Custom Tools** | Via MCP only | Via MCP only | MCP + discoveryCommand |
| **Task Management** | TodoWrite/TaskCreate | Not supported | Not supported |
| **LSP Servers** | Via plugins | Not supported | Not supported |

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
4. **Plugin skills from `cache/ai-safety-plugins/`** — user's custom plugins
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
# Sync skills + permissions to Gemini CLI
scripts/sync_claude_to_gemini.sh

# Sync skills + permissions to Codex CLI
scripts/sync_claude_to_codex.sh
```

### What They Do

Both scripts use `scripts/helpers/enumerate_claude_skills.sh` to discover and deduplicate all skill sources:

1. **User skills** — real directories in `~/.claude/skills/` → symlinked
2. **Standalone skills** — `.md` files in `~/.claude/skills/` → wrapped in dir with SKILL.md symlink
3. **Plugin skills** — from `marketplaces/` and `cache/` → symlinked (deduplicated by name, first-wins)
4. **Agent skills** — `~/.claude/agents/*.md` → wrapped in dir with SKILL.md symlink

Each skill name appears exactly once in the output. The enumerate helper handles deduplication so sync scripts don't need to.

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
