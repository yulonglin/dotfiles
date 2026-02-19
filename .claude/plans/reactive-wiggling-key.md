# Plan: Rename `*-toolkit` plugins to shorter names

## Context

The 6 ai-safety-plugins have verbose names (`core-toolkit`, `code-toolkit`, etc.). Dropping the `-toolkit` suffix makes names shorter and easier to read in agent prefixes (`core:codex` vs `core-toolkit:codex`), profiles, settings, and conversation references.

## Naming

| Current | New |
|---------|-----|
| `core-toolkit` | `core` |
| `code-toolkit` | `code` |
| `research-toolkit` | `research` |
| `writing-toolkit` | `writing` |
| `workflow-toolkit` | `workflow` |
| `viz-toolkit` | `viz` |

Note: profile names in `profiles.yaml` (`code`, `research`, `writing`) overlap with plugin names. This is fine — `claude-context` resolves them in separate namespaces (profiles via `profiles[key]`, plugins via `registry[name]`).

## Blast Radius

Comprehensive list of files referencing `*-toolkit`:

### ai-safety-plugins repo (`~/code/ai-safety-plugins/`)

| File | What changes |
|------|-------------|
| `plugins/*/` | 6 directory renames |
| `plugins/*/.claude-plugin/plugin.json` | `name` field (6 files) |
| `.claude-plugin/marketplace.json` | `name` + `source` fields (6 entries) |
| `README.md` | Documentation references |

### dotfiles repo (`~/code/dotfiles/`)

| File | What changes |
|------|-------------|
| `claude/CLAUDE.md` | Plugin descriptions section (~6 refs) |
| `claude/templates/contexts/profiles.yaml` | Enable lists (~12 refs) |
| `claude/plugins/installed_plugins.json` | Keys (`name@marketplace`) + `installPath` (6 entries) |
| `claude/rules/agents-and-delegation.md` | `code-toolkit:*` agent refs (7 refs) — also fix `code-toolkit:claude` → `core:claude` (moved in previous commit) |
| `CLAUDE.md` (project) | Plugin architecture section |
| `.claude/settings.json` | `enabledPlugins` keys (6 entries) |

### Plugin cache (`~/.claude/plugins/cache/ai-safety-plugins/`)

| Path | What changes |
|------|-------------|
| `cache/ai-safety-plugins/*/` | 6 directory renames |

### Auto-generated (no manual update needed)

- Per-project `.claude/settings.json` — rebuilt by `claude-context` on next session start
- Per-project `.claude/context.yaml` — stores profile names only, not plugin names

## Implementation

### Step 1: Rename source directories + update manifests

In `~/code/ai-safety-plugins/`:

```bash
# Rename directories
for old in core-toolkit code-toolkit research-toolkit writing-toolkit workflow-toolkit viz-toolkit; do
  new="${old%-toolkit}"
  mv "plugins/$old" "plugins/$new"
done
```

Then update:
- Each `plugins/*/.claude-plugin/plugin.json` — change `name` field
- `.claude-plugin/marketplace.json` — change `name` and `source` for all 6

### Step 2: Update dotfiles references

Edit these files with `sd` or `Edit` tool (simple find-replace):
- `claude/CLAUDE.md` — replace all `*-toolkit` refs
- `claude/templates/contexts/profiles.yaml` — replace all `*-toolkit` refs
- `claude/rules/agents-and-delegation.md` — replace `code-toolkit:` → `code:` and fix `code-toolkit:claude` → `core:claude`
- `CLAUDE.md` (project) — replace all `*-toolkit` refs

### Step 3: Update plugin registry

`claude/plugins/installed_plugins.json` — for each of the 6 entries:
- Change key: `code-toolkit@ai-safety-plugins` → `code@ai-safety-plugins`
- Change `installPath`: `.../code-toolkit/1.0.0` → `.../code/1.0.0`

### Step 4: Rename cache directories

```bash
CACHE=~/.claude/plugins/cache/ai-safety-plugins
for old in core-toolkit code-toolkit research-toolkit writing-toolkit workflow-toolkit viz-toolkit; do
  new="${old%-toolkit}"
  mv "$CACHE/$old" "$CACHE/$new"
done
```

### Step 5: Rebuild project settings

```bash
# In dotfiles repo (and any other active project)
claude-context  # Re-applies context.yaml with new plugin names
```

### Step 6: Update .claude/settings.json

Replace the `enabledPlugins` keys in the dotfiles project settings to use new names. Or just run `claude-context` which rebuilds it.

## Verification

1. `ls ~/code/ai-safety-plugins/plugins/` — should show `core`, `code`, `research`, `writing`, `workflow`, `viz`
2. `rg "toolkit" ~/code/ai-safety-plugins/plugins/` — should return 0 matches
3. `rg "-toolkit" claude/CLAUDE.md claude/templates/contexts/profiles.yaml claude/rules/agents-and-delegation.md` — 0 matches
4. `jq 'keys' claude/plugins/installed_plugins.json` — no `*-toolkit` keys
5. `claude-context --list` — shows plugins with new short names
6. Start new Claude Code session — agents appear as `core:codex`, `code:code-reviewer`, etc.

## Commit Plan

Two commits in two repos:
1. **ai-safety-plugins**: `refactor: rename *-toolkit plugins to shorter names`
2. **dotfiles**: `refactor: update plugin references for *-toolkit → * rename`
