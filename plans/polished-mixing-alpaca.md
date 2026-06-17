# Plan: Move ai-safety-plugins to ~/code/marketplaces/ai-safety-plugins

## Context

The `ai-safety-plugins` repo currently lives at `~/code/ai-safety-plugins`. It's being moved to
`~/code/marketplaces/ai-safety-plugins` for better organization (grouping all marketplace repos
under a `marketplaces/` parent). The GitHub repo name and marketplace identifier both stay
`ai-safety-plugins` — only the local directory path changes.

---

## Scope

**Functional changes** (break things if missed):
- `claude/templates/contexts/profiles.yaml` — `local:` path (line 14)
- `custom_bins/claude-cache-link` — `LOCAL_SOURCES` path (line 30)
- `claude/ai-safety-plugins` git-tracked symlink — update relative target

**Doc-only changes** (safe to do, low risk — confirmed grep hits only):
- `CLAUDE.md` line ~130 — symlink diagram (confirmed contains old path)
- `claude/docs/plugin-maintenance.md` lines 7-10 — path examples

**No changes needed — explicitly resolved:**
- `config.sh` `PLUGIN_MARKETPLACES` — GitHub source `yulonglin/ai-safety-plugins`, not local path
- `claude/settings.json` / `.claude/settings.json` — `@ai-safety-plugins` is marketplace name
- `scripts/helpers/enumerate_claude_skills.sh` — references `~/.claude/plugins/cache/ai-safety-plugins/` (cache name, not source path); confirmed safe
- `claude/plugins/known_marketplaces.json` — contains `/Users/yulong/.claude/ai-safety-plugins` which is the stable `~/.claude` symlink path; this path remains valid after updating the `claude/ai-safety-plugins` symlink
- `claude/CLAUDE.md` and `deploy.sh` line 481 — do not contain the local directory path; no change needed
- Plan files — historical docs, leave as-is

---

## Implementation Steps

### 0. Guard + move the actual directory
```bash
# Fail fast if destination already exists (prevents silent nesting)
[[ -e ~/code/marketplaces/ai-safety-plugins ]] && echo "ERROR: destination already exists" && exit 1

mkdir -p ~/code/marketplaces
mv ~/code/ai-safety-plugins ~/code/marketplaces/ai-safety-plugins

# Immediately create a compat symlink at old path (rollback safety during migration)
ln -s ~/code/marketplaces/ai-safety-plugins ~/code/ai-safety-plugins
```

### 1. Update `claude/templates/contexts/profiles.yaml`
File: `claude/templates/contexts/profiles.yaml` line 14

```yaml
# Before:
    local: ${CODE_DIR}/ai-safety-plugins
# After:
    local: ${CODE_DIR}/marketplaces/ai-safety-plugins
```

### 2. Update `custom_bins/claude-cache-link`
File: `custom_bins/claude-cache-link` line 30

```bash
# Before:
  ["ai-safety-plugins"]="${CODE_DIR:-${HOME}/code}/ai-safety-plugins/plugins"
# After:
  ["ai-safety-plugins"]="${CODE_DIR:-${HOME}/code}/marketplaces/ai-safety-plugins/plugins"
```

### 3. Update the `claude/ai-safety-plugins` symlink (relative target)
Current target is `../../ai-safety-plugins` (relative). Must stay relative for cross-machine portability:

```bash
# From dotfiles root:
ln -sfn ../../marketplaces/ai-safety-plugins claude/ai-safety-plugins
# Verify:
readlink claude/ai-safety-plugins   # should print: ../../marketplaces/ai-safety-plugins
```

### 4. Update documentation strings (confirmed grep hits)
- `CLAUDE.md` line ~130: `ai-safety-plugins -> ~/code/ai-safety-plugins` → `~/code/marketplaces/ai-safety-plugins`
- `claude/docs/plugin-maintenance.md` lines 7-10: path examples

### 5. Re-register marketplace and update cache
```bash
claude-context --sync          # Re-registers marketplace with new local path
claude-cache-link --apply      # Re-links plugin cache dirs to new source location
```

### 6. Verify and remove compat symlink
```bash
# Run verification (see below) first, then remove the compat symlink
rm ~/code/ai-safety-plugins
```

### 7. Commit (staged files only)
```bash
git add claude/ai-safety-plugins custom_bins/claude-cache-link \
        claude/templates/contexts/profiles.yaml CLAUDE.md \
        claude/docs/plugin-maintenance.md
git commit -m "chore: move ai-safety-plugins to ~/code/marketplaces/"
```

---

## Verification

Run these before step 6 (compat symlink still in place):

1. **Old path grep** — confirms no active references missed:
   ```bash
   grep -r "code/ai-safety-plugins" /Users/yulong/code/dotfiles \
     --include="*.sh" --include="*.yaml" --include="*.yml" \
     --include="*.md" --include="*.json" \
     --exclude-dir=plans --exclude-dir=".git" --exclude-dir=worktrees
   ```
   Expected: only the compat symlink itself, nothing in tracked source files.

2. **Symlink target** — `readlink claude/ai-safety-plugins` → `../../marketplaces/ai-safety-plugins`

3. **Cache links** — `claude-cache-link` (dry run) shows `LINKED` for all plugins, no `WOULD LINK`

4. **Marketplace registration** — `claude-context --list` shows ai-safety-plugins with new local path

5. **Live session** — open new Claude Code session; `[code python]` statusline appears, plugins load without errors

---

## Rollback (if verification fails)

```bash
# Restore old path (compat symlink already there from step 0)
# Undo symlink update:
ln -sfn ../../ai-safety-plugins claude/ai-safety-plugins
# Restore configs (git):
git checkout claude/templates/contexts/profiles.yaml custom_bins/claude-cache-link
# Move directory back:
mv ~/code/marketplaces/ai-safety-plugins ~/code/
rm ~/code/ai-safety-plugins  # remove compat symlink
```
