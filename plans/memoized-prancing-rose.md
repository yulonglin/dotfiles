# Plan: Auto-Commit Hook at SessionEnd

## Context

When a Claude Code session ends, uncommitted changes are left in the working tree. The user wants each
session captured as one logical commit — a safety net that preserves work and builds readable git history.

The existing `/commit` skill (a Claude Code slash command) already handles staging + LLM message
generation + committing perfectly. Since hooks are bash scripts and can't invoke skills directly, the
hook replicates the skill by calling `claude -p` with the same prompt and tool permissions.

## Design

| Decision | Choice |
|----------|--------|
| **Trigger** | `SessionEnd` (one session = one logical chunk) |
| **Commit logic** | Delegate to `claude -p` replicating the `/commit` skill |
| **Activation** | Always-on globally + per-project opt-out via `.no-auto-commit` file |
| **Push** | No — local commit only |
| **Guards** | 7 safety checks before delegating (detached HEAD, in-progress ops, conflicts) |

## Files

### 1. NEW: `claude/hooks/auto_commit.sh`

The script runs safety guards, checks for any changes, then delegates entirely to `claude -p` using
the same prompt and allowed-tools as the existing `/commit` skill.

```bash
#!/usr/bin/env bash
# Hook: Auto-commit any uncommitted changes at session end
# Event: SessionEnd
# Replicates the /commit skill via `claude -p` for LLM-generated commit messages.
# Per-project opt-out: touch .no-auto-commit in repo root
#                   or: export CLAUDE_AUTO_COMMIT=0

set -euo pipefail

# ── Parse input ───────────────────────────────────────────────────────────────
INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-${CWD:-$(pwd)}}"
[ -z "$PROJECT_DIR" ] && exit 0

# ── Opt-out: env var ──────────────────────────────────────────────────────────
[[ "${CLAUDE_AUTO_COMMIT:-1}" == "0" ]] && exit 0

# ── Must be a git repo ────────────────────────────────────────────────────────
REPO_ROOT=$(git -C "$PROJECT_DIR" rev-parse --show-toplevel 2>/dev/null) || exit 0

# ── Opt-out: sentinel file ────────────────────────────────────────────────────
[[ -f "$REPO_ROOT/.no-auto-commit" ]] && exit 0

# ── Guard: detached HEAD (commit would create orphaned commit) ────────────────
if ! git -C "$REPO_ROOT" symbolic-ref HEAD >/dev/null 2>&1; then
  echo "auto-commit skipped: detached HEAD" >&2
  exit 0
fi

# ── Guard: in-progress git operations ────────────────────────────────────────
GIT_DIR=$(git -C "$REPO_ROOT" rev-parse --git-dir)
for sentinel in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD rebase-merge rebase-apply BISECT_LOG; do
  if [ -e "$GIT_DIR/$sentinel" ]; then
    echo "auto-commit skipped: $sentinel in progress" >&2
    exit 0
  fi
done

# ── Guard: unresolved conflicts ───────────────────────────────────────────────
CONFLICTS=$(git -C "$REPO_ROOT" diff --name-only --diff-filter=U 2>/dev/null || true)
if [[ -n "$CONFLICTS" ]]; then
  echo "auto-commit skipped: unresolved conflicts" >&2
  exit 0
fi

# ── Early exit: nothing to commit ─────────────────────────────────────────────
# Check both tracked changes (diff HEAD) and new untracked files (ls-files -o)
UNTRACKED=$(git -C "$REPO_ROOT" ls-files --others --exclude-standard 2>/dev/null | head -1)
if git -C "$REPO_ROOT" diff HEAD --quiet 2>/dev/null && [[ -z "$UNTRACKED" ]]; then
  exit 0
fi

# ── Delegate to claude -p (replicates /commit skill) ─────────────────────────
# Build git context exactly as the /commit skill does via its !` inline commands
GIT_STATUS=$(git -C "$REPO_ROOT" status 2>/dev/null)
GIT_DIFF=$(git -C "$REPO_ROOT" diff HEAD 2>/dev/null | head -300)
GIT_BRANCH=$(git -C "$REPO_ROOT" branch --show-current 2>/dev/null)
GIT_LOG=$(git -C "$REPO_ROOT" log --oneline -10 2>/dev/null)

PROMPT="Based on the above changes, create a single git commit.

## Context

- Current git status:
$GIT_STATUS

- Current git diff (staged and unstaged changes):
$GIT_DIFF

- Current branch: $GIT_BRANCH

- Recent commits:
$GIT_LOG

## Your task

Stage and create the commit using a single message. Do not use any other tools or do anything else.
Do not send any other text or messages besides these tool calls.
Working directory: $REPO_ROOT"

(cd "$REPO_ROOT" && claude -p "$PROMPT" \
  --allowedTools "Bash(git add:*),Bash(git status:*),Bash(git commit:*)" \
  2>/dev/null) || echo "auto-commit: claude invocation failed" >&2
```

### 2. MODIFY: `claude/settings.json`

Add `auto_commit.sh` to the `SessionEnd` hooks array alongside `watchdog_stop.sh`. Timeout 120s
to accommodate LLM call + any slow pre-commit hooks.

```json
"SessionEnd": [
  {
    "hooks": [
      {
        "type": "command",
        "command": "$HOME/.claude/hooks/watchdog_stop.sh",
        "timeout": 5
      },
      {
        "type": "command",
        "command": "$HOME/.claude/hooks/auto_commit.sh",
        "timeout": 120
      }
    ]
  }
],
```

## Safety Guards

| Guard | What it prevents |
|-------|-----------------|
| `CLAUDE_AUTO_COMMIT=0` env var | Per-session disable |
| `.no-auto-commit` file | Per-project opt-out |
| `symbolic-ref HEAD` | Orphaned commit in detached HEAD state |
| `MERGE_HEAD` sentinel | Accidental commit during merge |
| `CHERRY_PICK_HEAD` sentinel | Accidental commit during cherry-pick |
| `REVERT_HEAD` sentinel | Accidental commit during revert |
| `rebase-merge` / `rebase-apply` | Accidental commit during rebase |
| `BISECT_LOG` | Accidental commit during bisect |
| Unresolved conflicts check | Committing partial conflict resolution |
| Clean working tree check | Skip `claude -p` entirely if nothing to commit |

## Verification

1. **Normal case**: Edit a tracked file, exit session → `git log --oneline -1` shows new commit with semantic message from LLM
2. **Nothing to commit**: Start fresh session, exit → no new commit
3. **New file**: Create a new untracked file, exit → file is staged and committed
4. **Opt-out**: Create `.no-auto-commit` in repo root → no auto-commit even with changes
5. **Guard test**: `git checkout HEAD~1` (detached HEAD), make a change, exit → `auto-commit skipped: detached HEAD` on stderr, no commit
6. **Direct invocation** (test without ending session):
   ```bash
   echo '{"cwd":"'$(pwd)'"}' | bash claude/hooks/auto_commit.sh
   ```
