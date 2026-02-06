# Fix Duplicate Skills + Cross-Tool Sync Strategy (Final)

## Completed Steps

- [x] **Step 1**: `.gitignore` whitelist — `claude/skills/.gitignore` rewritten
- [x] **Step 2**: Runtime cleanup — 81 symlinks, 6 agent wrapper dirs, 8 circular self-links removed
- [x] Partial Step 4: Sync scripts updated (but need revision — see below)
- [x] Partial Step 5: `docs/cross-tool-extensibility.md` updated (needs revision)

## Remaining Work

### Step 3: Fix `enumerate_claude_skills.sh` — deduplicate with version awareness

**Problem**: The enumerate helper emits duplicates from 3 plugin source locations:
1. `marketplaces/` — canonical, always latest (git-cloned repos)
2. `cache/local-marketplace/` — user's custom plugins (research/writing/code toolkit)
3. `cache/claude-plugins-official/` — versioned snapshots (may have old versions)

**Fix**: Split into `_enumerate_raw()` and `enumerate_claude_skills()`:
- `_enumerate_raw()` emits all entries in priority order:
  1. User skills (from `skills/`)
  2. Standalone skills (`.md` files in `skills/`)
  3. Plugin skills from `marketplaces/` first (canonical/latest)
  4. Plugin skills from `cache/local-marketplace/` second (user custom)
  5. Plugin skills from remaining `cache/` last (versioned, may be stale)
  6. Agent skills
- `enumerate_claude_skills()` pipes through `awk -F'\t' '!seen[$2]++ { print }'` — first-wins dedup means marketplaces beat cache, user skills beat all.

**Result**: Each skill name emitted exactly once, from the best source.

**Conflict detection**: When deduplicating, emit warnings to stderr for shadowed skills:
```
⚠ Skill "brainstorming" from cache/superpowers/4.1.1 shadowed by marketplaces/superpowers
```
This alerts users when a user skill accidentally shadows a plugin skill (or vice versa).

**File**: `scripts/helpers/enumerate_claude_skills.sh`

### Step 4 (revised): Sync scripts — include ALL skill types, deduplicated

**Change from previous plan**: Sync ALL plugin skills (not skip them). The enumerate helper's dedup ensures each skill appears once.

**Revert the `plugin_skill) continue` change** in both sync scripts. Restore plugin_skill handling but simplify:

```bash
plugin_skill)
    ln -sfn "$path" "$TARGET_DIR/$name"
    echo "  Plugin Skill: $name"
    ;;
```

No need for "user skill takes precedence" check — the enumerate helper handles priority.

**Files**:
- `scripts/sync_claude_to_gemini.sh`
- `scripts/sync_claude_to_codex.sh`

### Step 5 (revised): Update docs

Revert the "plugin skills are NOT synced" text. Instead document:
- All skill types sync (user, standalone, plugin, agent)
- Enumerate helper deduplicates (user > standalone > plugin > agent priority)
- `.gitignore` whitelist prevents runtime artifacts from being tracked in git

**File**: `docs/cross-tool-extensibility.md`

### Step 6: Verify

1. `bash scripts/helpers/enumerate_claude_skills.sh` — each skill name appears exactly once
2. `scripts/sync_claude_to_gemini.sh` — syncs ~95 unique skills (9 user + 2 standalone + ~81 plugin + 4 agent, minus overlaps)
3. `scripts/sync_claude_to_codex.sh` — same count
4. `git status` in `claude/skills/` — only user-authored files tracked
5. No duplicate skill names in output

## Files to Modify

| File | Action |
|------|--------|
| `scripts/helpers/enumerate_claude_skills.sh` | Add dedup logic (final `awk` pass) |
| `scripts/sync_claude_to_gemini.sh` | Restore plugin_skill handling (remove `continue`) |
| `scripts/sync_claude_to_codex.sh` | Restore plugin_skill handling (remove `continue`) |
| `docs/cross-tool-extensibility.md` | Revert "not synced" text, document dedup |
