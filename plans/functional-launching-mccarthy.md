# Fix Plans & Tasks Directory Placement

## Context

Plans and tasks created by Claude Code aren't consistently landing at the project root. The root cause: `plansDirectory: ".claude/plans"` resolves relative to CWD, not the git root. When Claude Code launches from a subdirectory, `.claude/plans/` gets created there.

**Evidence** — misplaced `.claude/plans/` in non-git-root subdirectories:
- `sandbagging-detection/dev/web/.claude/plans/`
- `sandbagging-detection/dev/docs/challenge-fund-updates/.claude/plans/`
- `dotfiles/claude/.claude/` (= `~/.claude/.claude/`, CWD was inside `~/.claude/`)

Additional: tasks always go to `~/.claude/tasks/` (global, no per-project option — #20425), but `workflow-defaults.md` incorrectly says they're per-project.

---

## Plan

### 1. Add git-root auto-cd to `claude()` wrapper

**File:** `config/aliases.sh` — `claude()` function (line ~68, before `command claude`)

```bash
local git_root
git_root=$(git rev-parse --show-toplevel 2>/dev/null)
if [[ -n "$git_root" && "$PWD" != "$git_root" ]]; then
    echo "claude: moving to git root: $git_root"
    cd "$git_root" || true
fi
```

This is the primary fix. Makes `plansDirectory: ".claude/plans"` always resolve correctly. Safe because:
- Returns nearest git root (correct for monorepos with sub-repos)
- `claude()` runs in current shell, so cd persists — but user explicitly invoked claude, so moving to root is expected
- No-op when already at root or outside a git repo

### 2. Add SessionStart hook for CWD validation

**File:** `claude/hooks/check_git_root.sh` (new)

Unlike a PreToolUse/Write hook (which can't redirect plan paths — Claude Code determines them before the model writes), a **SessionStart** hook warns early. This catches IDE integrations and direct `command claude` invocations that bypass the wrapper.

```bash
#!/bin/bash
# SessionStart hook: warn if CWD is not a git root
git_root=$(git rev-parse --show-toplevel 2>/dev/null)
if [[ -n "$git_root" && "$PWD" != "$git_root" ]]; then
    echo "WARNING: CWD ($PWD) is not the git root ($git_root)"
    echo "Plans will be created in the wrong location."
    echo "Consider: cd $git_root"
fi
exit 0  # Don't block session start
```

**Register in:** `claude/settings.json` → `hooks.SessionStart`

### 3. Fix documentation in `workflow-defaults.md`

**File:** `claude/rules/workflow-defaults.md`

- Change `Tasks: <repo>/.claude/tasks/ (NOT ~/.claude/tasks/)` → `Tasks: ~/.claude/tasks/ (global, no per-project option — #20425, last checked 2026-02-14)`
- Add review note: "Check weekly if `tasksDirectory` setting has been added; update date when checked"
- Add note about `claude()` wrapper auto-cd to git root

### 4. Clean up misplaced `.claude` directories

Verified contents — no CLAUDE.md or rules in any of them, just plans and bash logs:

| Path | Contents | Action |
|------|----------|--------|
| `sandbagging-detection/dev/web/.claude/` | 3 plan files | Move plans to `dev/.claude/plans/`, then `trash` |
| `sandbagging-detection/dev/docs/challenge-fund-updates/.claude/` | Empty `plans/` dir | `trash` |
| `dotfiles/claude/.claude/` | Bash logs only | `trash` |

### 5. Add `claude/.claude/` to `.gitignore`

**File:** `.gitignore`

Prevents `~/.claude/.claude/` from showing in `git status` if recreated. Minor housekeeping.

---

## Files to Modify

| File | Action |
|------|--------|
| `config/aliases.sh` | Add git-root cd to `claude()` (~line 68) |
| `claude/hooks/check_git_root.sh` | New SessionStart validation hook |
| `claude/settings.json` | Register SessionStart hook |
| `claude/rules/workflow-defaults.md` | Fix tasks docs, add dated review note |
| `.gitignore` | Add `claude/.claude/` |

## Cleanup (other repos)

| Path | Action |
|------|--------|
| `sandbagging-detection/dev/web/.claude/plans/*.md` | Move to `dev/.claude/plans/`, then trash dir |
| `sandbagging-detection/dev/docs/challenge-fund-updates/.claude/` | `trash` (empty) |
| `dotfiles/claude/.claude/` | `trash` (bash logs) |

## Verification

1. `cd` into a subdirectory of a git repo → run `claude` → confirm it auto-cds to root
2. Start a new Claude session → enter plan mode → verify plan lands at `<git-root>/.claude/plans/`
3. Test SessionStart hook: launch from a subdirectory → should see warning
4. Confirm `workflow-defaults.md` matches reality
5. Confirm misplaced dirs are cleaned up
