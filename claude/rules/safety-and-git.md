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
| **NEVER drop a git stash** without first running `git stash show -p stash@{N}` to verify contents. If a stash/pop partially failed (sandbox), retry with `dangerouslyDisableSandbox: true` — the stash data is fine, only the restore was blocked. Use `git stash apply` (keeps stash) over `git stash pop` (deletes stash) when uncertain | Dropped stash = irreversible data loss. A "broken" stash usually just needs sandbox bypass to restore |
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
| Writing to `$CLAUDE_JOB_DIR/tmp` (background jobs) | Sandbox denies writes under `~/.claude/jobs` (harness-injected `denyWithinAllow`), so `printf > $CLAUDE_JOB_DIR/tmp/msg.txt` silently creates nothing and a later `git commit -F` fails with "could not read log file" | Put commit-msg and similar small files in `$TMPDIR` with a job-unique name (e.g. `$TMPDIR/<jobid>-commit-msg.txt`). `settings.json` allowlists `~/.claude/jobs/*/tmp`, but the injected deny may still win — verify with a test write before relying on it |
| `.claude/settings*.json` | Sandbox denies write/unlink on Claude Code's own settings files | Cannot `git stash` or `git checkout` these files. Commit everything else in `.claude/` normally (`.gitignore`, `settings.json` staging works). For pull-rebase with dirty settings, push first or use `git push` directly instead of stash-pull-push |
| `git pull/merge/stash` failing with "Read-only file system" or "unable to unlink" | Runtime `denyWithinAllow` blocks git's unlink+rename on `config/`, `.claude/settings.json`, and `.claude/skills/` — even though `git` is in `excludedCommands`. This is injected by Claude Code, not user-configurable | Use `dangerouslyDisableSandbox: true` on `git pull`, `git merge`, `git stash` when they fail with these errors. Retry immediately — don't try workarounds (patch files, sparse checkout) first |
| `modal` CLI: "Could not connect to the Modal server" (modal <1.5.1 only) | modal <1.5.1's gRPC client (grpclib) does its own DNS + direct TCP to `api.modal.com`, bypassing the sandbox's proxy-based network allowlist → "Temporary failure in name resolution". `allowedHosts`/`excludedCommands` don't help. **FIXED in modal 1.5.1+**: install `modal[api-proxy-support]` and the client honors `HTTPS_PROXY`/`ALL_PROXY` (HTTP CONNECT via python-socks, proxy-side DNS), which the sandbox exports — verified 2026-07-18: sandboxed `modal app list` succeeds with modal 1.5.2, no bypass | Upgrade to `modal[api-proxy-support]>=1.5.1` and run modal sandboxed normally. Only on modal <1.5.1 (or if the proxy env vars are absent) fall back to `dangerouslyDisableSandbox: true`. **Fail fast either way:** before launching a long background `modal run`, preflight with `timeout 20 modal app list` in the foreground — connectivity/auth errors surface in seconds instead of after a long silent background wait. Same preflight pattern for other providers: cheapest authenticated list endpoint with a short timeout (OpenAI/Anthropic `GET /v1/models`, OpenRouter `GET /api/v1/key` (also shows credits), `runpodctl get pod`, `vastai show user`) |
| Stray dotfiles appear in `ls -la` / `git status` (`.bashrc`, `.gitconfig`, `.idea`, `.gitmodules`, `.claude/skills`…) shown as `crw-rw-rw- … 1, 3 … nobody` | **Linux bubblewrap only.** The sandbox masks denied paths by bind-mounting `/dev/null` (char device, major 1 / minor 3) over them. They are NOT repo content — and `git fetch`/submodule ops will hit "Permission denied" reading them (e.g. `.gitmodules`). macOS Seatbelt does NOT do this — it restricts writes but leaves denied paths visible as normal files (verified: write-denied `.claude/settings.json` still `stat`s as a regular file, not a char device) | Recognize `crw` + `1, 3` + `nobody` as a sandbox mask, not a file. **Never `git add -A`** — it would stage these artifacts; use explicit pathspecs (`git add <file>`). To confirm: `find . -maxdepth 2 -type c` lists masked paths. If a git op genuinely needs the masked path, retry with `dangerouslyDisableSandbox: true` |

**When planning a task involving file system operations:** List anticipated sandbox issues BEFORE executing. Don't discover them one-by-one through failures — that wastes context and user patience.

## Git Commands (Readability)

- **Smart pull strategy** — choose the safest sync method based on context, not unconditional rebase:
  ```
  After git fetch origin:
  +-- Local ahead, remote has nothing     -> just push (no pull needed)
  +-- Local behind, no local commits      -> git pull --ff-only
  +-- Diverged:
  |   +-- Local has merge commits?        -> git pull --no-rebase (merge)
  |   +-- >20 local commits to replay?    -> git pull --no-rebase (merge)
  |   +-- Few commits, no merges          -> git pull --rebase
  |   +-- Any pull fails?                 -> abort, show state, ask user
  +-- @{u} not configured                 -> commit, git push -u origin <branch>
  ```
  **Principle:** Rebase only when cheap and safe (few commits, no merges). Never rebase merge commits — rebase drops them and replays their individual commits, causing massive conflicts.
- **Default pull behavior**: When user says "pull":
  1. Determine correct remote: `UPSTREAM_REMOTE=$(git rev-parse --abbrev-ref @{u} 2>/dev/null | cut -d/ -f1)` then `git fetch "${UPSTREAM_REMOTE:-origin}"` (always)
  2. Evaluate state: `git log @{u}.. --oneline`, `git log ..@{u} --oneline`, `git log @{u}.. --merges --oneline`
  3. Apply decision tree above
  4. If unstaged changes: stash first, sync, then stash pop
  - If stash fails due to sandbox (e.g., `.claude/settings*.json` unlink errors), commit the non-settings files first, then push directly
  - If merge conflicts occur after stash pop, notify user and help resolve
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

**Background jobs**: keep the msg file in `$TMPDIR` too — just make the name job-unique (e.g. `$TMPDIR/<jobid>-commit-msg.txt`). Do NOT use `$CLAUDE_JOB_DIR/tmp` for it despite the harness suggesting that dir for temp files: the sandbox denies writes under `~/.claude/jobs`, the redirect silently creates nothing, and `git commit -F` then fails with "could not read log file".
