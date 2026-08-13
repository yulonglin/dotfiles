# Safety & Git Rules

## Irreversible — never do these

- **Deleting files**: prefer `archive/` > `trash` > `rm`. Never `rm -rf` unless asked.
- **Stashes**: the stack is shared across worktrees. `stash push -u -m '<tag>'`, `apply <sha>`, never `pop`; `stash show -p` before dropping. A restore that failed under the sandbox is intact — retry with `dangerouslyDisableSandbox: true`.
- **Secrets**: never commit API keys, tokens, credentials.
- **Edit races**: `Edit` failing with "file modified since read" means re-read and retry, never `Write` over the file.
- **`git add -A`**: never in-sandbox — it stages the mask artifacts below. Use explicit pathspecs.

Enforced by hook, not by this file: `block_destructive_git.sh` (`reset --hard`, `checkout -- <path>`, `clean -f`, bare `stash`, `stash pop`). `nudge_syspath.sh` is advisory PostToolUse feedback, controlled by `hooks/features.conf`; it does not prevent a write.

## Sandbox failure modes

| Symptom | Reality | Fix |
|---|---|---|
| Temp writes fail | `/tmp` is restricted | `$TMPDIR` (`/tmp/claude/`) or project-local `./tmp/` |
| Heredoc (`<<EOF`) in a command | The shell writes its temp file to a denied path → **empty commit message**, failed commit | `mkdir -p "$TMPDIR" && printf '%s\n' "subject" "" "body" > "$TMPDIR/msg.txt" && git commit -F "$TMPDIR/msg.txt"`. `-m` is fine for one-liners |
| Background job writing `$CLAUDE_JOB_DIR/tmp/…` | Writes under `~/.claude/jobs` are denied, so the redirect **silently creates nothing** and `git commit -F` then fails with "could not read log file" | Use `$TMPDIR` with a job-unique name (`$TMPDIR/<jobid>-commit-msg.txt`) |
| `git pull`/`merge`/`stash` → "Read-only file system" or "unable to unlink" | Runtime `denyWithinAllow` on `config/`, `.claude/settings.json`, `.claude/skills/`, injected by Claude Code and not user-configurable — `git` being in `excludedCommands` does not help | Retry immediately with `dangerouslyDisableSandbox: true`. Do not reach for patch files or sparse checkout |
| Phantom dotfiles in `git status`/`ls -la` as `crw-rw-rw- … 1, 3 … nobody` | **Linux bubblewrap only** — denied paths are masked by bind-mounting `/dev/null` over them. Not repo content; `git fetch`/submodule ops hit "Permission denied" on them (e.g. `.gitmodules`). macOS Seatbelt does not do this | Confirm with `find . -maxdepth 2 -type c`. Never `git add -A`. If a git op genuinely needs the masked path, `dangerouslyDisableSandbox: true` |

More patterns (chmod, symlinks, git hooks, launchd/cron, modal, codex-companion): `docs/sandbox-troubleshooting.md`.
