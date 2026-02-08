# Fix Duplicate Skills — Final Step

## Context

All implementation for the duplicate skills fix is complete. The one remaining change — a "Known Issue" note in `docs/cross-tool-extensibility.md` — was made, then mistakenly reverted. It needs to be restored and committed.

**Why this doc change matters:** The cross-tool doc's "Deduplication" section documents how `enumerate_claude_skills.sh` works. That helper **skips symlinks** for the `user_skill` type specifically because of the plugin symlink bug. Without the "Known Issue" note, readers won't understand *why* symlinks get special treatment in the enumerate helper.

## Completed Work

- [x] `scripts/cleanup/clean_plugin_symlinks.sh` — cleanup script
- [x] `deploy.sh:473-476` — wired cleanup into `deploy_claude()`
- [x] `config/aliases.sh:400` — `clean-skill-dupes` alias
- [x] `CLAUDE.md:300` — Learnings entry
- [x] GitHub issue [#23819](https://github.com/anthropics/claude-code/issues/23819) — filed

## Remaining

### Step 1: Re-add "Known Issue" to `docs/cross-tool-extensibility.md`

After the existing "Deduplication" section's last paragraph (ending with `...shadowed by marketplaces/...`), add:

```markdown
### Known Issue: Plugin Symlink Duplication

Claude Code's plugin system creates symlinks in `~/.claude/skills/` pointing to `plugins/cache/` and `plugins/marketplaces/`. These cause every plugin skill to appear **twice** in the slash command picker: once as "(user)" from the symlink, once as "(plugin-name)" from the plugin registry. Related: [#14549](https://github.com/anthropics/claude-code/issues/14549), [#21891](https://github.com/anthropics/claude-code/issues/21891).

**Workarounds:**
- `clean-skill-dupes` alias removes the symlinks
- `deploy.sh` auto-cleans during Claude Code deployment
- Symlinks are **recreated on startup/plugin-sync**, so cleanup may need to be repeated
```

**File**: `docs/cross-tool-extensibility.md`

### Step 2: Commit all outstanding changes

Stage and commit all modified files from this fix (cleanup script, deploy.sh, aliases, CLAUDE.md, cross-tool doc).

## Verification

1. `git diff docs/cross-tool-extensibility.md` — shows the Known Issue addition
2. Commit succeeds cleanly
