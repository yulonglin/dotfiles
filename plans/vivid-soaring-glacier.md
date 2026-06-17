# Fix: Plugin Marketplace Schema & Stale References

## Context

`claude doctor` reports 6 plugin errors because the **project-level** `.claude/settings.json` still references the old marketplace name `@local-marketplace` (pre-migration) and a nonexistent `@anthropic-agent-skills` marketplace. The global settings were migrated but the project settings were missed.

A separate schema validation warning was also occurring because `marketplace.json` used bare source names without `./plugins/` prefix — **already fixed** earlier this session.

## Root Cause

| Error | Source | Fix |
|-------|--------|-----|
| `*-toolkit@local-marketplace: not found` (5 errors) | `.claude/settings.json` lines 12-16 | Replace `@local-marketplace` → `@ai-safety-plugins` |
| `document-skills@anthropic-agent-skills: not found` | `.claude/settings.json` line 17 | Remove (marketplace doesn't exist) |
| marketplace schema validation warning | `marketplace.json` source fields | **Already fixed** (bare names → `./plugins/` paths) |

## Changes

### 1. `.claude/settings.json` (project-level, this repo)

**File**: `/Users/yulong/code/dotfiles/.claude/settings.json`

Replace lines 12-17:
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

- `@local-marketplace` → `@ai-safety-plugins` (matches global settings + known_marketplaces.json)
- Remove `document-skills@anthropic-agent-skills` entirely (stale, marketplace doesn't exist)

### 2. Optional: Clean stale `insights-toolkit` from installed_plugins.json

**File**: `/Users/yulong/.claude/plugins/installed_plugins.json`

Remove the `insights-toolkit@ai-safety-plugins` entry (lines 192-200) — this plugin was absorbed into `workflow-toolkit` and no longer exists in the marketplace.

## Verification

1. Restart Claude Code
2. `claude doctor` — should show 0 plugin errors (or only unrelated ones)
3. Confirm no `@local-marketplace` warnings on startup
