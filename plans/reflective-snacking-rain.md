# Plan: Unified Text Snippets Sync — Remaining Work (Revised)

## Context

Bidirectional sync between macOS text replacements, Alfred snippets, and a version-controlled YAML config. Core implementation done — script, deploy integration, initial export all working. This plan covers cleanup, bug fixes, verification, and commit.

Two sub-agent critiques (Codex plan-critic + Claude) identified critical issues in the original plan, incorporated below.

## Critical Bug Fixes (Before Any Testing)

### Bug 1: Backup doesn't actually back up the SQLite DB

`backup_current_state()` calls `defaults export NSGlobalDomain` which exports ALL global prefs as a plist — it does NOT copy `TextReplacements.db`. If sync corrupts the DB, there's no rollback.

**Fix:** Change `backup_current_state()` to copy `~/Library/KeyboardServices/TextReplacements.db` (+ WAL/SHM sidecars) instead of (or in addition to) the NSGlobalDomain plist export.

**File:** `scripts/sync_text_replacements.py` lines 526-555

### Bug 2: `restore` does destructive `shutil.rmtree` on live Alfred dir

`cmd_restore()` calls `shutil.rmtree(snippets_dir)` then `copytree` from backup. If interrupted or backup is incomplete, production Alfred snippets are destroyed and this propagates via Dropbox sync.

**Fix:** Use safer pattern: copy backup to staging path, verify, then swap (rename old → `.bak`, rename staging → live). Or at minimum, rename existing dir before copying backup in.

**File:** `scripts/sync_text_replacements.py` lines 836-841

## Revised Task Order

### Task 1: Fix Bugs (above)

Apply Bug 1 and Bug 2 fixes to the script.

### Task 2: User Review of YAML Duplicates

**Assessment from critique:** Duplicates are not a blocker — the script handles them correctly as separate entries. But they're worth cleaning for hygiene.

Removals (user-approved):
- **Remove `snip.brainstorm`** from default → keep `exp` in coding-agents (has UID)
- **Remove `snip.cr`** from default → keep `plan` in coding-agents (has UID)
- **Remove `snip.txt`** from default → keep `txt2` in coding-agents (has UID)
- **Remove `canarystr`** from default → keep `snip.canary` in default (has UID, user prefers `snip.` prefix)

**Action:** Apply directly — user has approved.

### Task 3: First Sync Test (with dry-run gate)

**Key addition from critique:** Run `--dry-run` before live sync.

1. Verify Alfred path resolves to Dropbox: `defaults read com.runningwithcrayons.Alfred-Preferences syncfolder`
2. Run `snippets-diff` to see current delta
3. Run `sync --dry-run` — review output for unexpected overwrites
4. **User approves** dry-run output
5. Run `sync-snippets` (live sync, includes Alfred restart)
6. Verify entries in macOS System Settings → Keyboard → Text Replacements
7. Verify entries in Alfred → Features → Snippets
8. Verify unicode: `sqlite3 ~/Library/KeyboardServices/TextReplacements.db "SELECT ZPHRASE FROM ZTEXTREPLACEMENTENTRY WHERE ZSHORTCUT='phileo' AND ZWASDELETED=0"` — should return `philéō`

### Task 4: Clean Up Stale Alfred Directories

**Moved after sync test** (critique: verify sync works before removing the fallback path).

1. Confirm active path is Dropbox (verified in Task 3 step 1)
2. `trash ~/Library/Application\ Support/Alfred/snippets/Default\ Collection/`
3. `trash ~/Library/Application\ Support/Alfred/Alfred.alfredpreferences/snippets/Default\ Collection/`
4. Verify Alfred still works

### Task 5: Document

Add to `CLAUDE.md` Deployment Components section:
```
- Text replacements - Bidirectional sync with macOS + Alfred snippets (daily 9 AM, requires Full Disk Access for terminal app)
```

Also document prefix behavior: macOS uses raw shortcuts (e.g., `hi`), Alfred applies collection prefix at runtime (e.g., `fm.hi`).

**Files:** `CLAUDE.md`

### Task 6: Verification

1. **Idempotent export:** `export-snippets` → verify YAML unchanged
2. **Add/remove test:** Add `__test_entry` to YAML → `sync-snippets` → verify in both systems → remove from YAML → `sync --prune` → verify removed
3. **Diff clean:** `snippets-diff` → should show no differences
4. **Backup test:** Check `~/.local/share/text-replacements-backup/` has entries with correct DB backup
5. **iCloud drift check:** Wait 3-5 min after sync, rerun `snippets-diff` to confirm no drift

### Task 7: Commit

Files to commit:
- `scripts/sync_text_replacements.py` (new + bug fixes)
- `config/text_replacements.yaml` (new, cleaned)
- `scripts/cleanup/setup_text_replacements_sync.sh` (new)
- `deploy.sh` (modified)
- `config.sh` (modified)
- `config/aliases.sh` (modified)
- `scripts/shared/helpers.sh` (modified)
- `CLAUDE.md` (modified)

Push to main (personal repo, direct push OK).

## Key Files

| File | Lines | Change |
|------|-------|--------|
| `scripts/sync_text_replacements.py` | ~500 | Fix backup (copy DB) + fix restore (safe swap) |
| `config/text_replacements.yaml` | ~143 | Remove duplicates after user approval |
| `CLAUDE.md` | ~89 | Add deployment component entry |
| `deploy.sh` | — | Already modified, verify correct |
| `config.sh` | — | Already modified, verify correct |
| `config/aliases.sh` | — | Already modified, verify correct |

## Decisions

1. **Duplicate cleanup:** ✅ Decided — remove `snip.brainstorm`, `snip.cr`, `snip.txt`, `canarystr`; keep coding-agents versions + `snip.canary`
2. **Dry-run review:** Approve sync output before live run (during execution)
