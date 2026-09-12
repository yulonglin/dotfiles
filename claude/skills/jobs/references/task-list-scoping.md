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

**A deleted `env` key is the sticky case, and nothing about it is a bug in the restart command.** Measured along the live spawn chain on 2026-09-11: the daemon hands its whole environment to each `bg-pty-host`, stripping only `ANTHROPIC_BASE_URL`, `_CLAUDE_CODE_ASSUME_FIRST_PARTY_BASE_URL` and `SSH_*`; the session process under it then re-applies the settings `env` block, which is where those two gateway keys come back. So a key **still present** in `settings.json` is rewritten by every new session and its edits land immediately — while a key **deleted** from `settings.json` is never written over, survives by plain inheritance in every process that already held it, and is inherited again by everything those processes spawn. Editing a value is self-healing; deleting one is not, and only killing the holding processes clears it.

**`--keep-workers` is right for a stale task list and wrong for a deleted `env` key.** A task list is chosen at spawn, so a surviving worker's list is already fixed and restarting it changes nothing; an environment variable is carried for the worker's whole life, so a kept worker keeps handing the stale value to every child it forks. Drop `--keep-workers` when clearing an `env` key — or keep it and follow with `claude respawn --all`, which restarts every background session under the new daemon (`claude respawn <id>` for one). **Respawn is not a substitute for the daemon stop**: its stated job is picking up the current Claude binary, and the replacement session is spawned by the same daemon, so it re-inherits whatever that daemon holds. Respawn clears a stale key only when the daemon is already clean and the workers are the stragglers — which is exactly the state `--keep-workers` creates.

**Kill the stale holders before stopping the daemon, or the next daemon inherits the same environment.** Service install is disabled in this version, so the daemon is transient: it is spawned on demand by whichever client next needs it and inherits *that client's* environment. `claude daemon status` names the candidates under `holding this daemon open`, so a long-lived `claude agents` viewer is a re-infection vector rather than a leftover, and which one wins the next spawn is a race — which is why a daemon restart clears the value on one attempt and not the next. Measured 2026-09-11: `claude agents` pid 3576048, started 13 August, still carried `CLAUDE_CODE_ATTRIBUTION_HEADER`, absent from `settings.json` since 10 September 09:49 UTC, while its three sibling holders and the live daemon were clean — so that day's sessions escaped it only by which client happened to spawn the daemon. List the holders, run the loop above against each with the key you are chasing, and kill the stale ones first.

## Anything launching through tmux must unset, not blank

`custom_bins/claude-spawn` and `_cw_launch` `unset` both variables inside the launched command. Blanking them to empty via tmux `-e` is wrong now: the wrapper no longer regenerates from an empty value, so a blank would be passed through as a literal empty list name, and tmux's `-e` can set a variable but not remove one. Such launchers must also go through `zsh -ic` — tmux runs a bare command string under a non-interactive shell that sources no aliases, so `claude` there is the raw binary.

Two measured gotchas in that area: tmux `-e` does **not** override `PATH` for a session's initial command (the server inherits it from whoever started it), and zsh's `printf %q` emits `$'\t'` for a control character, which dash — Debian/Ubuntu `/bin/sh` — mis-parses; use POSIX single-quote escaping.
