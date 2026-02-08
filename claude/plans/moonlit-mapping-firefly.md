# Simplify claude/skills/.gitignore

## Context

The current `claude/skills/.gitignore` uses a whitelist-then-re-ignore pattern requiring **two entries per skill** in two separate sections. This is error-prone — `my-insights/` is potentially untracked due to a missing allowlist entry. We want zero-maintenance for new user skills.

## Root cause

Claude Code's plugin system creates two types of runtime artifacts in `claude/skills/`:
1. **Self-referencing symlinks** (`skill-name/skill-name`) — always extensionless
2. **SKILL.md symlinks** (`context-summariser/SKILL.md`) — point to agents/skills with absolute paths

## Approach: Extension-based matching + pre-commit hook

### 1. Rewrite `claude/skills/.gitignore`

Replace per-skill directory allowlists with `!**/*.*` (track all files with extensions).

| | Current | Proposed |
|---|---|---|
| New user skill entries | 2 (two sections) | **0** (auto-tracked) |
| SKILL.md symlink re-ignore | Manual (10 lines) | **Auto-generated** by hook |
| Failure mode if forgotten | Silent data loss | Symlink tracked (visible in `git status`) |
| Total rules | ~55 lines | ~30 lines |

**Safety tradeoff (documented):** `!*/` + `!**/*.*` means new runtime dirs with extensioned files ARE auto-tracked. This is the preferred failure mode (visible vs silent). If Claude Code starts creating runtime files in `skills/`, add them to the deny list section.

```gitignore
# Claude Code Skills Directory
# =============================
# Runtime artifacts created by Claude Code's plugin system:
# 1. Self-referencing symlinks: skills/<name>/<name> (extensionless, circular)
# 2. SKILL.md symlinks: point to agents/*.md or skills/*.md (absolute paths)
#
# Strategy: Track all files with extensions (covers all user content).
# Self-referencing symlinks are extensionless → stay ignored.
# SKILL.md symlinks are auto-detected by pre-commit hook.
#
# ASSUMPTION: No runtime files with extensions are created in skill subdirs.
# If Claude Code starts creating runtime files here, add specific ignore patterns.

# Ignore everything by default
*

# Track this file
!.gitignore

# Track plugin system directory (needed for extensionless .codex-system-skills.marker)
!.system/
!.system/**

# Allow git to traverse into skill directories
!*/
!**/*/

# Track all files with extensions (user content always has extensions)
!**/*.*

# Standalone skill files (technically covered by !**/*.* but explicit for clarity)
!docs-search.md
!task-management.md

# === DENY LIST ===
# Re-ignore files/dirs that !**/*.* would incorrectly allow

# macOS metadata
**/.DS_Store

# AUTO-GENERATED: SKILL.md symlinks with non-portable absolute paths (do not edit manually)
# Updated by scripts/hooks/dotfiles-pre-commit.sh
context-summariser/SKILL.md
docs-search/SKILL.md
efficient-explorer/SKILL.md
gemini-cli/SKILL.md
llm-billing/SKILL.md
task-management/SKILL.md
# END AUTO-GENERATED
```

**Note:** Verify during implementation whether `my-insights/SKILL.md` is a real file or symlink. If symlink → add to auto-generated list. If real file → it's correctly auto-tracked.

### 2. Create pre-commit hook: `scripts/hooks/dotfiles-pre-commit.sh`

**Logic:**
1. Guard: exit 0 if not in dotfiles repo (check for `claude/skills/.gitignore`)
2. Find all `SKILL.md` symlinks: `find claude/skills -maxdepth 2 -name "SKILL.md" -type l | sed "s|^claude/skills/||" | sort`
3. Replace auto-generated section between markers using `sd` (cross-platform, available per coding conventions) or `awk` with `index()` (not regex — avoids metacharacter issues)
4. Fallback: if markers don't exist, append the block
5. Use temp file + mv for atomic write (prevents corruption on crash)
6. Stage `.gitignore` if changed (`git add claude/skills/.gitignore`)

**Portability notes (from critique):**
- No `find -printf` (macOS BSD doesn't have it) — use `sed` to strip prefix
- No `readlink -f` (macOS) — use `readlink` without `-f` (only need direct target)
- Use `sd` instead of `sed -i` (avoids macOS vs Linux difference)
- Optional: warn about extensionless non-symlink files that would be silently ignored

### 3. Wire into deploy.sh

Add to the git-hooks deployment section:
```bash
# Set up dotfiles-specific pre-commit hook if we're in the dotfiles repo
if [[ "$(git -C "$DOT_DIR" rev-parse --show-toplevel 2>/dev/null)" == "$DOT_DIR" ]]; then
    mkdir -p "$DOT_DIR/.git/hooks"
    chmod +x "$DOT_DIR/scripts/hooks/dotfiles-pre-commit.sh"
    ln -sf "../../scripts/hooks/dotfiles-pre-commit.sh" "$DOT_DIR/.git/hooks/pre-commit.local"
fi
```

## Files to create/modify

| File | Action |
|------|--------|
| `claude/skills/.gitignore` | Rewrite with extension-based matching |
| `scripts/hooks/dotfiles-pre-commit.sh` | Create — auto-updates SKILL.md symlink re-ignore list |
| `deploy.sh` | Add symlink setup for `.git/hooks/pre-commit.local` |

## Verification

1. Snapshot: `git ls-files claude/skills/ > /tmp/claude/before.txt`
2. Apply `.gitignore` changes
3. Compare: `git ls-files claude/skills/` — should be identical to before
4. Check `my-insights/`: `ls -la claude/skills/my-insights/SKILL.md` — determine if symlink or real
5. Self-links ignored: `git check-ignore -v claude/skills/agent-teams/agent-teams` ✓
6. SKILL.md symlinks ignored: `git check-ignore -v claude/skills/context-summariser/SKILL.md` ✓
7. Real files tracked: `git check-ignore -v claude/skills/commit/SKILL.md` — NOT ignored ✓
8. .DS_Store ignored: `git check-ignore -v claude/skills/strategic-communication/.DS_Store` ✓
9. Test hook: run `scripts/hooks/dotfiles-pre-commit.sh` manually, verify `.gitignore` unchanged
10. Test commit: small change → commit → verify hook runs and `.gitignore` stays correct
11. Run `shellcheck scripts/hooks/dotfiles-pre-commit.sh`
