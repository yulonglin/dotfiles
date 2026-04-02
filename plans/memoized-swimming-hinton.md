# Plan: Profile-driven selective plugin sync

## Context

`claude-tools context --sync` currently runs `claude plugin marketplace update` for all registered marketplaces, which installs ALL plugins from each marketplace into `installed_plugins.json`. This creates bloat — 38 plugins installed when only 30 are referenced in profiles.yaml (11 orphans like `serena`, `linear`, `playwright`).

The fix: make profiles.yaml the single source of truth for what gets **installed**, not just what gets **enabled**.

## Current state

- 38 installed plugins, 30 wanted (from `base:` + all `profiles:` entries)
- 11 orphans: `claude-code-setup`, `code-review`, `feature-dev`, `learning-output-style`, `linear`, `playwright`, `pr-review-toolkit`, `serena`, `slack-mcp`, `supabase`, `swift-lsp`
- 3 missing: `codex`, `llms-fetch-mcp`, `things-mcp` (new additions to profiles, not yet synced)
- CLI commands available: `claude plugin install <plugin>@<marketplace>` and `claude plugin uninstall <plugin>`

## Design

### New sync flow (replaces Phase 2)

```
Phase 1: Register marketplaces (unchanged)
Phase 2: Update ONLY marketplaces that contain wanted plugins (skip unused ones)
Phase 3: Selective install — install wanted plugins not yet in installed_plugins.json
Phase 4: Prune — uninstall orphan plugins (opt-in via --prune flag)
Phase 5: Post-fixups (unchanged — permissions, auto-update, scope normalization)
```

### Key changes in `sync.rs`

**1. Compute wanted plugins from profiles.yaml**

Add `pub fn collect_wanted_plugins()` to `profiles.rs`:
- Union of `base:` + all `profiles:` `enable:` entries
- Returns `HashSet<String>` of short plugin names

**2. Build marketplace-to-plugin index**

Scan `~/.claude/plugins/marketplaces/` directories to map `plugin_name -> marketplace_name`. Each marketplace dir has subdirectories per plugin. This replaces the need for profiles.yaml to specify marketplaces per plugin.

Fallback: if a wanted plugin isn't found in any marketplace dir (not yet cloned), update ALL marketplaces first (current behavior), then retry the scan.

**3. Filter marketplace updates (Phase 2)**

Only `marketplace update` for marketplaces that contain at least one wanted plugin. Currently 8 marketplaces registered — with selective sync, unused ones (e.g., `openai-codex` if `codex` isn't found there) get skipped.

**4. Selective install (Phase 3)**

For each wanted plugin not in `installed_plugins.json`:
```
claude plugin install <plugin>@<marketplace> --scope user
```
Parallel via thread spawn (same pattern as existing Phase 2).

**5. Prune orphans (Phase 4, opt-in)**

New flag: `--prune` (separate from `--sync`)

For each plugin in `installed_plugins.json` NOT in the wanted set:
```
claude plugin uninstall <plugin> --keep-data
```
- `--keep-data` preserves plugin persistent data (safe to re-install later)
- Report what was pruned
- First run: dry-run output showing what WOULD be pruned (always, before actually pruning)

### CLI changes

```
--sync              Register + update + install wanted (no uninstall)
--sync --prune      Also uninstall orphaned plugins (with --keep-data)
--sync --verbose    Detailed output per step
```

### profiles.yaml: no schema change needed

The existing `base:` + `profiles:` sections already declare all wanted plugins. No new fields needed.

## Files to modify

| File | Change |
|------|--------|
| `tools/claude-tools/src/context/profiles.rs` | Add `collect_wanted_plugins()` |
| `tools/claude-tools/src/context/sync.rs` | New phases 3-4, filter Phase 2 marketplaces |
| `tools/claude-tools/src/context/mod.rs` | Add `--prune` flag to `ContextArgs` |

## Verification

1. `cargo build --release` in `tools/claude-tools/`
2. `claude-tools context --sync -v` — should show filtered marketplace updates + selective installs
3. `claude-tools context --sync --prune -v` — should show dry-run of orphan removal, then prune
4. Check `installed_plugins.json` — only wanted plugins remain
5. `claude-tools context --list` — profiles still work correctly
6. Apply a profile (`claude-tools context code python`) — all plugins resolve

## User's note: duplicate install bug

The user mentioned a Claude Code bug where the same plugin gets installed in different projects (multiple entries in `installed_plugins.json` with different scopes). This is separate from this plan — the existing `normalize_scopes()` partially addresses it. Worth tracking but not blocking this change.
