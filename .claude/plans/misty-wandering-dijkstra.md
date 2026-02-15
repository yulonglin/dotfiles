# Fix Plugin Marketplace Name Mismatch

## Context

`claude doctor` reports 6 plugin errors after the marketplace migration (plan: `harmonic-puzzling-bubble`). Two root causes:

1. **Symlink name mismatch**: `claude/local-marketplace` → `~/code/ai-safety-plugins` — Claude Code auto-discovers the marketplace using the directory name (`local-marketplace`), but the manifest `name` field and all `installed_plugins.json` entries use `ai-safety-plugins`.
2. **Project-level settings drift**: `.claude/settings.json` still references `@local-marketplace` (5 entries) and has an orphaned `document-skills@anthropic-agent-skills` entry from a removed marketplace.

## Changes

### 1. Rename symlink: `local-marketplace` → `ai-safety-plugins`

```bash
mv claude/local-marketplace claude/ai-safety-plugins
```

Directory name now matches `marketplace.json` `name` field and all `@ai-safety-plugins` references.

**File:** `claude/local-marketplace` → `claude/ai-safety-plugins`

### 2. Update `claude/plugins/known_marketplaces.json` (CRITICAL)

**File:** `claude/plugins/known_marketplaces.json` — lines 5, 7

Both `path` and `installLocation` point to `/Users/yulong/.claude/local-marketplace`. After the symlink rename, this path won't exist. Update both to `/Users/yulong/.claude/ai-safety-plugins`.

### 3. Fix project-level `.claude/settings.json`

**File:** `.claude/settings.json` — lines 12-17

Replace `@local-marketplace` → `@ai-safety-plugins` and remove orphaned entry:

```json
// Before:
"research-toolkit@local-marketplace": false,
"writing-toolkit@local-marketplace": false,
"code-toolkit@local-marketplace": true,
"workflow-toolkit@local-marketplace": true,
"viz-toolkit@local-marketplace": false,
"document-skills@anthropic-agent-skills": false,

// After:
"research-toolkit@ai-safety-plugins": false,
"writing-toolkit@ai-safety-plugins": false,
"code-toolkit@ai-safety-plugins": true,
"workflow-toolkit@ai-safety-plugins": true,
"viz-toolkit@ai-safety-plugins": false,
```

### 4. Update `CLAUDE.md` (project root)

**File:** `CLAUDE.md` — line 106

```
├── local-marketplace -> ~/code/ai-safety-plugins  # Symlink to marketplace repo
```
→
```
├── ai-safety-plugins -> ~/code/ai-safety-plugins  # Symlink to marketplace repo
```

### 5. Update `claude/docs/plugin-maintenance.md`

**File:** `claude/docs/plugin-maintenance.md` — all 4 references

Replace `local-marketplace` → `ai-safety-plugins` in dir paths and `@` references.

### 6. Update `docs/cross-tool-extensibility.md`

**File:** `docs/cross-tool-extensibility.md` — line 37

```
4. **Plugin skills from `cache/local-marketplace/`** — user's custom plugins
```
→
```
4. **Plugin skills from `cache/ai-safety-plugins/`** — user's custom plugins
```

### 7. Clean stale `insights-toolkit` from `installed_plugins.json`

**File:** `claude/plugins/installed_plugins.json` — lines 192-200

Remove `insights-toolkit@ai-safety-plugins` entry (plugin was absorbed into `workflow-toolkit`, no longer exists in marketplace).

## Files Modified

| File | Change |
|------|--------|
| `claude/local-marketplace` | Rename symlink → `claude/ai-safety-plugins` |
| `claude/plugins/known_marketplaces.json` | Update path + installLocation to new symlink name |
| `.claude/settings.json` | `@local-marketplace` → `@ai-safety-plugins`, remove orphan |
| `CLAUDE.md` | Update directory tree reference |
| `claude/docs/plugin-maintenance.md` | Update 4 path references |
| `docs/cross-tool-extensibility.md` | Update 1 cache path reference |
| `claude/plugins/installed_plugins.json` | Remove stale `insights-toolkit` entry |

## Not Updated (Historical)

Plan files (`.claude/plans/*.md`, `claude/plans/*.md`, `claude/plans.archive/*.md`) and `claude/history.jsonl.archive.*` contain `local-marketplace` references but are historical records — left as-is.

## Verification

1. Restart Claude Code
2. `claude doctor` — should show 0 plugin errors
3. `claude plugin list` — all 6 ai-safety-plugins should resolve
4. Skills from plugins still work (e.g., `/docs-search`)
