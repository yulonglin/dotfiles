# Fix Duplicate Skills + Cross-Tool Sync Strategy

## Part 1: Fix Claude Code Duplicate Skills

### Problem

Skills appear twice — once as `(user)` and once as `(plugin:name@source)`:
```
/review-draft    ... (user)
  /review-draft  ... (plugin:writing-toolkit@local-marketplace)
```

### Root Cause

57 symlinks in `claude/skills/` with `pluginname__skillname` pattern (e.g., `writing-toolkit__review-draft`) point into `plugins/cache/`. The plugin registry (`installed_plugins.json`) ALSO discovers the same skills. Both paths register them → duplicates.

### Fix

**Step 1**: Remove all plugin symlinks
```bash
cd claude/skills && find . -maxdepth 1 -type l -name '*__*' -delete
```

**Step 2**: Add `claude/skills/.gitignore`
```
# Plugin symlinks created by `claude plugins install` — redundant
# since installed_plugins.json handles plugin skill discovery
*__*
```

**Step 3**: Remove from git tracking
```bash
git rm --cached claude/skills/*__*
```

**Step 4**: Commit

**Files**: `claude/skills/` (remove 57 symlinks), `claude/skills/.gitignore` (new)

**Verify**: Start new Claude Code session → skills appear only once

---

## Part 2: Cross-Tool Extensibility Map

### Concept Mapping

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

### What Syncs Cleanly (same SKILL.md format)

All three tools use SKILL.md with YAML frontmatter for skills. These can sync directly:
- **User skills**: `claude/skills/commit/`, `spec-interview/`, etc.
- **Plugin skills**: From `plugins/cache/*/skills/` (need to scan cache, not rely on symlinks)
- **Agents → Skills**: Claude agents (`*.md`) can be wrapped as skills for Codex/Gemini

### What Needs Translation

| Source (Claude Code) | Target | Translation Needed |
|---------------------|--------|-------------------|
| MCP config (JSON) | Codex `config.toml` | JSON → TOML |
| MCP config (JSON) | Gemini `settings.json` | Restructure JSON keys |
| Hooks (JSON, 12+ events) | Gemini hooks (4 events) | Map event names, subset |
| Hooks (JSON) | Codex (notify only) | Minimal - only completion events |
| CLAUDE.md | GEMINI.md / instructions.md | Pointer file (already done) |

### What Doesn't Sync

- **Output Styles**: Claude Code only
- **LSP Servers**: Claude Code only (via plugins)
- **Task Management**: Claude Code only
- **Gemini Extensions**: Different bundle format than Claude plugins
- **Codex Profiles**: Codex-specific config.toml feature

---

## Part 3: Update Sync Scripts

### 3a. Update `scripts/sync_claude_to_gemini.sh`

Current behavior (broken after Part 1):
- Syncs directories from `claude/skills/` → `~/.gemini/skills/`
- After removing `*__*` symlinks, plugin skills won't sync

Updated behavior:
1. Sync **user skills** (real directories in `claude/skills/`)
2. Sync **plugin skills** from `~/.claude/plugins/cache/*/skills/`
3. Sync **agents as skills** (existing behavior, keep as-is)
4. Sync **MCP servers** from `~/.claude.json` → `~/.gemini/settings.json` mcpServers section

**Key changes to `scripts/sync_claude_to_gemini.sh`**:

```bash
# After existing user skill sync loop, add:
echo ">>> Syncing Plugin Skills to Gemini CLI..."
PLUGIN_CACHE="$HOME/.claude/plugins/cache"
if [ -d "$PLUGIN_CACHE" ]; then
    find "$PLUGIN_CACHE" -path "*/skills/*" -mindepth 3 -maxdepth 3 -type d | while read skill_dir; do
        name=$(basename "$skill_dir")
        # Skip if already synced as user skill
        [ -L "$TARGET_DIR/$name" ] && continue
        ln -sfn "$skill_dir" "$TARGET_DIR/$name"
        echo "Linked Plugin Skill: $name"
    done
fi
```

### 3b. Create `scripts/sync_claude_to_codex.sh` (new)

Codex CLI only supports skills + MCP. New sync script:
1. Sync **user skills** from `claude/skills/` → `~/.codex/skills/`
2. Sync **plugin skills** from `plugins/cache/*/skills/` → `~/.codex/skills/`
3. Sync **agents as skills** (wrap `.md` files in skill dirs)

**Note**: Codex uses TOML for config (`config.toml`), not JSON. MCP server sync would require JSON→TOML translation. Defer MCP sync to follow-up (manual for now).

### 3c. Shared helper: `scripts/helpers/enumerate_claude_skills.sh` (new)

Both sync scripts need the same logic to enumerate skills. Extract into shared helper:
```bash
# Outputs lines: <type>\t<name>\t<path>
# Types: user_skill, plugin_skill, agent_skill
enumerate_claude_skills() {
    local claude_dir="${1:-$HOME/.claude}"

    # User skills (real directories)
    for skill in "$claude_dir/skills"/*/; do
        [ -d "$skill" ] || continue
        name=$(basename "$skill")
        [[ "$name" == .* ]] && continue
        echo "user_skill\t$name\t$skill"
    done

    # Plugin skills (from cache)
    local cache="$claude_dir/plugins/cache"
    if [ -d "$cache" ]; then
        find "$cache" -path "*/skills/*" -mindepth 3 -maxdepth 3 -type d | while read skill_dir; do
            name=$(basename "$skill_dir")
            echo "plugin_skill\t$name\t$skill_dir"
        done
    fi

    # Agent skills (converted)
    for agent in "$claude_dir/agents"/*.md; do
        [ -f "$agent" ] || continue
        name=$(basename "$agent" .md)
        echo "agent_skill\t$name\t$agent"
    done
}
```

---

## Part 4: Document Cross-Tool Mapping

Create `docs/cross-tool-extensibility.md` documenting how extensibility concepts map across Claude Code, Codex CLI, and Gemini CLI.

Contents:
- Concept mapping table (from Part 2 above)
- What syncs cleanly vs needs translation vs doesn't sync
- Sync script usage (how to run, what they do)
- Links to each tool's official extensibility docs
- Notes on what each tool uniquely supports

This serves as a reference for:
- Understanding which features are portable
- Deciding where to invest in skill/tool development
- Onboarding to new tools (what carries over, what doesn't)

**File**: `docs/cross-tool-extensibility.md`

---

## Part 5: Files Modified Summary

| File | Action |
|------|--------|
| `claude/skills/*__*` | Remove 57 symlinks |
| `claude/skills/.gitignore` | New (gitignore pattern) |
| `scripts/helpers/enumerate_claude_skills.sh` | New (shared skill enumeration) |
| `scripts/sync_claude_to_gemini.sh` | Update (use enumerate helper, add plugin cache scan) |
| `scripts/sync_claude_to_codex.sh` | New (Codex CLI sync) |
| `docs/cross-tool-extensibility.md` | New (cross-tool mapping reference) |

## Part 6: Verification

1. **Claude Code**: Start new session → no duplicate skills in `/skills` list
2. **Gemini CLI**: Run `scripts/sync_claude_to_gemini.sh` → check `~/.gemini/skills/` has both user and plugin skills
3. **Codex CLI**: Run `scripts/sync_claude_to_codex.sh` → check `~/.codex/skills/` has both user and plugin skills
4. **Git**: `git status` shows clean (symlinks removed, gitignore in place)

## Part 7: Future Work (Out of Scope)

- MCP server sync (JSON↔TOML translation for Codex)
- Hook sync (event name mapping Claude↔Gemini)
- Gemini Extension creation from Claude plugins
- `deploy.sh` integration for Codex/Gemini sync (add `--codex`, `--gemini` flags)
