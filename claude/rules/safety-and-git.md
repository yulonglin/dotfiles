# Safety & Git Rules

## Zero Tolerance Rules

| Rule | Consequence |
|------|-------------|
| **NEVER delete files** (`rm -rf`) unless explicitly asked | Prefer: `archive/` > `trash` (macOS) > `rm`. Violation → termination |
| **NEVER use mock data** in production code | Only in unit tests. ASK if data unavailable |
| **NEVER fabricate information** | Say "I don't know" when uncertain |
| **NEVER ignore unexpected results** | Surprisingly good/bad → investigate before concluding. A hidden bug is worse than a failed experiment |
| **NEVER commit secrets** | API keys, tokens, credentials |
| **NEVER run `git checkout --`** or any destructive Git (e.g. `git reset --hard`, `git clean -fd`): ALWAYS prefer safe, reversible alternatives, and ask the user if best practice is to do so | Can trigger catastrophic, irreversible data loss |
| **NEVER use `sys.path.insert`** directly | Crashes Claude Code session (see `rules/coding-conventions.md` for safe pattern) |
| **NEVER rewrite full file during race conditions** | If Edit fails with "file modified since read", pause and wait (exponential backoff), then ask user—NEVER use Write to overwrite entire file as workaround |

## Sandbox Awareness (Proactive)

Before running deployment scripts, file system operations, or configuration tasks, anticipate these common sandbox failure patterns:

| Pattern | Problem | Workaround |
|---------|---------|------------|
| Writing to `/tmp` | Sandbox may restrict `/tmp` | Use `$TMPDIR` (set to `/tmp/claude/`) or project-local `./tmp/` |
| `rm -rf` / `rm` | Blocked by sandbox | Use `trash` (macOS) or `mv` to `.bak`/`archive/` |
| `chmod` / `chown` | May fail on sandboxed filesystems | Test with a single file first; skip if not strictly needed |
| Symlink creation | Target path may not be writable | Verify with `ls -ld <parent>` before `ln -s` |
| `deploy.sh` / `install.sh` | Multiple operations may fail in sequence | Run with `--minimal` first to test subset |
| Git hooks (pre-commit, etc.) | May lack execute permission or fail in sandbox | Check with `ls -la .git/hooks/`; use `--no-verify` only if user approves |
| `launchd` / `cron` setup | May not have permissions to install agents | Warn user upfront; suggest manual installation |
| Heredocs in commands | Shell creates temp file in `/tmp` → blocked | Use `git commit -F` with file in `$TMPDIR`, or `printf` piping (see Git Commands) |
| `.claude/settings*.json` | Sandbox denies write/unlink on Claude Code's own settings files | Cannot `git stash` or `git checkout` these files. Commit everything else in `.claude/` normally (`.gitignore`, `settings.json` staging works). For pull-rebase with dirty settings, push first or use `git push` directly instead of stash-pull-push |

**When planning a task involving file system operations:** List anticipated sandbox issues BEFORE executing. Don't discover them one-by-one through failures — that wastes context and user patience.

## Git Commands (Readability)

- **Prefer rebase over merge** for `git pull` — keeps history linear and clean
- **Default pull behavior**: When user says "pull", run `git stash && git pull --rebase && git stash pop`
  - Handles unstaged changes automatically
  - If merge conflicts occur after stash pop, notify user and help resolve
  - If stash fails due to sandbox (e.g., `.claude/settings*.json` unlink errors), push directly or commit the non-settings files first
- **Use readable refs** over commit hashes: branch names, tags, `origin/branch`
- Examples:
  - ✅ `git log origin/main..feature-branch`
  - ✅ `git diff main..yulong/dev`
  - ❌ `git log 5f41114..a8084f7` (hard to read)
- Only use hashes when refs don't exist (e.g., comparing arbitrary commits)

### Commit Messages (Sandbox-Safe)

**NEVER use heredoc (`<<EOF`) in commit commands** — the shell creates a temp file in `/tmp` which the sandbox blocks, producing an empty message and a failed commit.

Instead, write the message to a file first (ensure `$TMPDIR` directory exists):
```bash
mkdir -p "$TMPDIR" && printf '%s\n' "feat: subject line" "" "Body details here" > "$TMPDIR/commit_msg.txt" && git commit -F "$TMPDIR/commit_msg.txt"
```

For single-line messages, `-m "message"` works fine without heredocs.
