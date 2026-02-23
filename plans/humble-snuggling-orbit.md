# Move plans/ and docs/ to project root (global convention)

## Context

Knowledge artifacts (plans, docs) currently live under `.claude/` (e.g., `.claude/plans/`, `.claude/docs/`). Moving them to the project root (`plans/`, `docs/`) makes them first-class project artifacts — visible, easy to commit, consistent with `specs/` at root.

**Critique acknowledged:** Two sub-agents argued against this change (`.claude/` prefix is a useful namespace, plans have random names, docs collision risk). Proceeding per user decision — the rationale is that project knowledge should be as visible as project code, not hidden under dot-directories.

## Critical files to modify

| File | Change |
|------|--------|
| `claude/settings.json:281` | `plansDirectory: ".claude/plans"` → `"plans"` |
| `config/aliases.sh:55` | Update comment referencing `.claude/plans` |
| `claude/rules/workflow-defaults.md` | Update paths + versioning rule |
| `claude/CLAUDE.md:58,70,158` | Update Directory Convention table + standard paths + Notes |
| `CLAUDE.md` | Update Architecture section paths |
| `config/vscode_settings.json:91-94` | Add folder icon associations |
| `specs/claude-memory.md:37` | Update `.claude/docs/` reference |

## Changes

### 1. Global settings (`claude/settings.json:281`)
- `"plansDirectory": ".claude/plans"` → `"plansDirectory": "plans"`
- Affects ALL repos immediately (global setting via `claude/` → `~/.claude` symlink)

### 2. Aliases (`config/aliases.sh:55`)
- Update comment: `plansDirectory: "plans"` (was `.claude/plans`)
- Auto-cd-to-git-root logic still needed (relative path resolution)

### 3. Rules (`claude/rules/workflow-defaults.md`)

**Path updates:**
- Line 7: `<repo>/.claude/plans/` → `<repo>/plans/`
- Line 15: `".claude/plans"` → `"plans"`

**Tiered versioning rule** (replace current "always version" block):
- **Always version**: `CLAUDE.md`, `rules/`, `agents/` (durable config)
- **Version when useful**: `docs/`, `specs/`, `plans/` with descriptive content
- **Ephemeral by default**: Auto-generated plans (random names) — version if referenced, prune freely otherwise

### 4. Global CLAUDE.md (`claude/CLAUDE.md`)
- Line 58: per-project plans column → `plans/`
- Line 70: standard paths → `plans/`, `docs/`
- Line 158: Notes → `plans/`

### 5. Project CLAUDE.md (`CLAUDE.md`)
- Architecture section: `.claude/plans/` → `plans/`

### 6. Specs (`specs/claude-memory.md:37`)
- Update `per-project at <repo>/.claude/docs/` → `per-project at <repo>/docs/`

### 7. Dotfiles repo: migrate existing plans
- `git add .claude/plans/*.md` (track untracked files first: `humble-snuggling-orbit.md`, `glowing-wandering-frog.md`)
- `mkdir plans/` at repo root
- `git mv .claude/plans/*.md plans/` (move all ~47 per-project plan files)
- Keep `.claude/context.yaml` and `.claude/settings.json` (not plans)
- Remove empty `.claude/plans/` directory

### 8. Cross-repo migration (CRITICAL — from Codex critique)
6 other repos have `.claude/plans/` with 25 total plan files:
- `apollo_rsre_takehome_v2` (5), `dotfiles-nordtailscale` (3), `dotfiles-vpn` (5), `nudge` (7), `sandbagging-detection` (1), `VoiceInk` (4)

Migration script (run once after setting change):
```bash
for repo in ~/code/*/; do
  if [ -d "$repo/.claude/plans" ] && [ "$(ls -A "$repo/.claude/plans" 2>/dev/null)" ]; then
    echo "Migrating: $repo"
    mkdir -p "$repo/plans"
    git -C "$repo" mv .claude/plans/*.md plans/ 2>/dev/null || mv "$repo/.claude/plans/"*.md "$repo/plans/"
  fi
done
```

### 9. Plugin hooks (from Codex critique)
Two hooks in ai-safety-plugins core set stale `CLAUDE_CODE_PLANS_DIR='.claude/plans'`:
- `claude/plugins/cache/ai-safety-plugins/core/*/hooks/pre_plan_create.sh`
- `claude/plugins/cache/ai-safety-plugins/core/*/hooks/pre_task_create.sh`

Update cache AND source repo (`~/code/ai-safety-plugins`) so fix persists across `claude-context --sync`.

### 10. SessionStart hook (`claude/hooks/check_git_root.sh`)
- Verified: warning message is generic ("Plans will be created in the wrong location") — no change needed.

### 11. VSCode folder icons (`config/vscode_settings.json:91-94`)

Existing: 2 custom entries (`experiments` → test, `journal` → log).

**Already have built-in icons** (skip):
- `docs` (built-in), `hooks` (built-in), `specs` (built-in via `test`)

**Add custom associations** ([verified](https://github.com/vscode-icons/vscode-icons/wiki/ListOfFolders)):

| Folder | Icon | Rationale |
|--------|------|-----------|
| `plans` | `blueprint` | Planning/design |
| `tasks` | `todo` | Task lists (critic: `notification` is wrong, `todo` better) |
| `rules` | `config` | Behavioral configuration |
| `skills` | `plugin` | Extends capabilities |
| `agents` | `bot` | Autonomous agents |

```json
{ "icon": "blueprint", "extensions": ["plans"], "format": "svg" },
{ "icon": "todo", "extensions": ["tasks"], "format": "svg" },
{ "icon": "config", "extensions": ["rules"], "format": "svg" },
{ "icon": "plugin", "extensions": ["skills"], "format": "svg" },
{ "icon": "bot", "extensions": ["agents"], "format": "svg" }
```

If `todo` doesn't exist in vscode-icons, fall back to `job` or `queue`.

## Docs convention (soft change — documentation only)

- Recommend `docs/` at project root for ALL project knowledge (Claude context, MCP examples, guides)
- `~/.claude/docs/` remains global knowledge location (unchanged — it's in `claude/docs/`)
- Per-project `.claude/docs/` → `docs/` (convention, not enforced by tooling)
- For public libraries with generated docs: use `docs/api/` or similar subdirectory
- Update docs-search skill to note `docs/` (root) vs `~/.claude/docs/` (global) distinction

## What NOT to change

- **`claude/plans/`** (168 global plan files) — part of `~/.claude/`, stays as-is
- **`claude/docs/`** (global knowledge) — stays, deployed as `~/.claude/docs/`
- **`deploy.sh` `runtime_files` array** — `"plans"` refers to global `~/.claude/plans/` (168 files), NOT per-project. Do not change.
- **Historical plan files** referencing `.claude/plans/` in content — records, not instructions
- **`scripts/migrate_claude_plans_tasks.sh`** — historical migration script

## Verification

1. New Claude Code session in a non-dotfiles repo → `EnterPlanMode` → verify plan lands at `<repo>/plans/`
2. Dotfiles repo: `ls plans/` → should contain ~47 migrated files
3. `ls claude/plans/` → global plans (168 files) untouched
4. Broad grep for stale references:
   ```bash
   grep -rn '\.claude/plans' --include='*.md' --include='*.sh' --include='*.json' . \
     | grep -v 'plans/' | grep -v archive/ | grep -v plans.archive/ | grep -v history
   ```
   → should only appear in historical plan content, not active instructions
5. Verify VSCode icons render correctly in sidebar
6. Verify cross-repo migration worked: `for r in ~/code/*/; do [ -d "$r/plans" ] && echo "$r: $(ls "$r/plans/" | wc -l) plans"; done`

## Execution order

1. Update `claude/settings.json` (plansDirectory)
2. Migrate dotfiles `.claude/plans/` → `plans/`
3. Update all documentation (CLAUDE.md, rules, specs, aliases)
4. Update plugin hooks
5. Add VSCode icons
6. Commit and push dotfiles
7. Run cross-repo migration script
8. Verify
