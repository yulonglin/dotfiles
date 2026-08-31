# Why Sessions Share A Task List, And Where To Look

Read this when tasks from unrelated repos show up in one session, or when someone proposes making the `claude()` wrapper set `CLAUDE_CODE_TASK_LIST_ID`.

## The wrapper deliberately sets no task-list ID

Claude Code already gives every session its own list when the variable is unset. Measured 2026-08-28 in `~/.claude/tasks/`: **683** `session-<id>` lists it created itself, against **11** `<ts>_UTC_<dir>` from ~2 months of the wrapper auto-generating one. The auto-generated ID bought nothing the platform was not already doing, and cost a leak no wrapper can close.

So `config/aliases/claude.sh` strips the variable with `env -u` on every launch. `claude -t <name>` is the only way to set one, for the rare case of pointing two sessions at one list on purpose. The old `claude-new` / `claude-with` / `claude-last` / `claude-tasks-list` helpers and the `CLAUDE_CODE_TASK_LIST_PIN` marker were deleted — zsh history showed zero real uses across 1,283 lines, and they were the last code able to set the variable. Do not restore them; `tests/test_claude_task_list_scope.zsh` asserts they stay gone.

## The three ways it has actually broken

**Residue in a long-lived shell.** `source ~/.zshrc` does *not* unset an already-exported variable, so any shell that ran an older wrapper keeps its ID until it dies. Honoring inherited values is how the original cross-repo leak survived a re-source. Hence `env -u` unconditionally, rather than a "is this deliberate?" test — that test was wrong twice.

**`local +x` under bash.** It does not shadow a *globally exported* variable in bash, and `deploy.sh` sources these aliases into `~/.bashrc`, so bash is a real target. Measured, same script both shells with the pin exported globally: bash child saw `PIN=[1]`, zsh saw `unset`. Use `env -u`, which removes it from the child in both.

**The daemon, which no shell fix reaches.** Sessions started from the `claude agents` view are spawned by `claude daemon run`, not by the shell — verified by parentage: every `bg-pty-host` / `bg-spare` is its child. The daemon captures its environment once at start and hands that copy to every session it spawns for its whole lifetime. A daemon started from a contaminated shell keeps distributing the stale ID *hours* after the wrapper is fixed and `~/.zshrc` re-sourced (observed: a daemon from 01:51 still handing `20260825_060521_UTC_code` to children spawned at 06:38, while a direct launch at 06:38 correctly showed none). You cannot unset it from inside a session either — the list is chosen at spawn.

## Diagnose by reading process state, never by inference

Inference cost two wrong fixes here before anyone looked at a process environment. One command separates pre- from post-fix processes:

```bash
for p in $(pgrep -f "^claude|/claude "); do
  printf '%-8s %s | %s\n' "$p" "$(ps -o lstart= -p $p)" \
    "$(tr '\0' '\n' < /proc/$p/environ | grep '^CLAUDE_CODE_TASK_LIST_ID=' || echo '<none>')"
done
```

A process started *after* the wrapper fix that still shows an ID is inheriting it from a parent, and `ps -o ppid=` names the parent. Remedy for the daemon, from a shell with the variable unset:

```bash
unset CLAUDE_CODE_TASK_LIST_ID && command claude daemon stop --any --keep-workers
```

`--keep-workers` leaves detached sessions running; the daemon runs on demand and respawns clean. Use `command` — `daemon` is a **hidden** subcommand, absent from `claude --help`, so a wrapper that scrapes that help text can misclassify it as a session prompt and prepend `--settings=…`, after which the parser rejects the daemon's own flags (`error: unknown option '--any'`). The wrapper now special-cases it; `tests/test_claude_hidden_subcommands.zsh` guards that.

## Anything launching through tmux must unset, not blank

`custom_bins/claude-spawn` and `_cw_launch` `unset` both variables inside the launched command. Blanking them to empty via tmux `-e` is wrong now: the wrapper no longer regenerates from an empty value, so a blank would be passed through as a literal empty list name, and tmux's `-e` can set a variable but not remove one. Such launchers must also go through `zsh -ic` — tmux runs a bare command string under a non-interactive shell that sources no aliases, so `claude` there is the raw binary.

Two measured gotchas in that area: tmux `-e` does **not** override `PATH` for a session's initial command (the server inherits it from whoever started it), and zsh's `printf %q` emits `$'\t'` for a control character, which dash — Debian/Ubuntu `/bin/sh` — mis-parses; use POSIX single-quote escaping.
