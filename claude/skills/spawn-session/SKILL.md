---
name: spawn-session
description: Spawn a detached tmux session running Claude Code in a chosen directory, seeded with an initial prompt, optionally reachable by Remote Control.
disable-model-invocation: true
---

# Spawn a seeded Claude session

`custom_bins/claude-spawn` does the whole thing in one command: new tmux session, cd to the directory, launch Claude Code, submit the seed prompt.

**This skill is user-invoked only** (`disable-model-invocation: true`). A spawned session outlives the conversation that created it and was never watched starting, so the decision to create one stays with the user. If you are Claude and a task looks like it wants a spawned agent, say so and print the command — do not reach for this yourself, and note that a subagent is usually the right tool instead.

## Use it

```bash
claude-spawn -d ~/code/some-repo "Investigate the flaky test in tests/test_auth.py and propose a fix"
```

Creates a detached session named `some-repo-MMDD-HHMM` running Claude Code in that directory with the prompt already submitted.

**It is the session you would have started by hand.** `claude-spawn` aims to be exactly `cd <dir> && claude "<prompt>"`, differing only in being detached, in tmux, and seeded without typing. Your Claude configuration applies unchanged — so if your settings enable Remote Control at startup, or the directory has a Telegram/iMessage channel configured, the spawned session has those too. `-r` asks for Remote Control explicitly; **omitting it does not make the session local-only**, it just means this tool did not ask for it.

The session ends when the agent does — no shell is left behind, so a finished spawn stops showing up as something still running.

**A directory inside a git repo becomes the repo root.** The `claude()` wrapper cds to the git root before launching (so `plansDirectory` resolves), which means `-d ~/code/repo/packages/api` starts the agent at `~/code/repo` with the whole repository in view, not just that package. `claude-spawn` prints a note when this applies. If the task must stay narrow, say so in the prompt — the working directory will not do it for you.

`claude-spawn --help` for the full list. The ones that matter:

| Flag | When |
|---|---|
| `-r` / `-n <name>` | You want to drive it by Remote Control from the phone. Off by default |
| `-s <name>` | The session name matters (you'll `tmux attach` to it by hand) |
| `-a` | Attach immediately instead of leaving it detached |
| `--auto` | Long unattended run that should resume itself after a rate limit — prefixes the window with the `tmux-resume` opt-in prefix |
| `--prompt-file <p>` / `-` | The seed prompt is long or multi-line |
| `-y` | Skip permission prompts. Meant for a worktree you've already accepted risk in |
| `--dry-run` | Show what would happen, change nothing |

## The gates, and why

**The gates are speed bumps, not guarantees.** They catch a combination you stated explicitly and would regret. They do not neutralise capability your own configuration grants — an earlier version tried, and the list of routes to neutralise only grew: every new way to reach a session was a silent hole until someone reviewed for it, and suppressing them quietly countermanded settings chosen on purpose.

**`-y` together with `-r` is refused** unless you add `--allow-remote-yolo`. An unrestricted agent that is also drivable from off-machine is the one combination worth stopping to think about; either alone is ordinary. Note this checks the *flags you passed*, not the capability that results — see the paragraph above.

**Spawning from inside a spawned session is refused** (`CLAUDE_SPAWN_DEPTH`). `--allow-nested` overrides it, but if you're hitting this, check that you meant to. Note what this is: an inherited environment variable. It stops accidental fan-out — the failure mode where a seeded agent reads a task as "spawn more agents" and you find twelve tmux sessions. It is not a containment boundary, because anything running in that session can unset it.

**Every spawn is logged** to `~/.local/state/claude-spawn/spawn.log` — timestamp, session, directory, flags, and a truncated SHA-256 of the prompt. The prompt text is not written to *that log*, only its hash, so an unexpected session can be traced back to a known spawn without the log itself holding the text.

That is a statement about the audit log and nothing else. The seed does reach disk by the ordinary route: it becomes the session's first user message, so it lands in the Claude transcript like anything else you type, and a positional invocation can also be captured in shell history. Hashing in the log narrows one exposure; it does not make the prompt ephemeral.

The prompt is hashed in the log but it is *not* hidden from the machine, and not only for a moment: it is passed to the agent positionally, so it stays in the running Claude process's argv and any local user can read it from `ps` or `/proc/<pid>/cmdline` for as long as the session lives. Claude Code takes its prompt positionally, so seeding inherently means this. Don't put anything in a seed prompt that you would not paste into a shared terminal.

The log is append-only and nothing reaps it — one short line per spawn, so it will not matter for years, but it is not self-limiting either. Truncate it by hand if it ever does, or wire it into the same daily hook as `claude-jobs-reap`.

## Never seed with untrusted text

Do not pipe a web page, an issue body, a PR description, or a file you did not write into the seed prompt. A fresh agent has no conversation context to weigh an injected instruction against, which makes it a softer target than a session that has been running for an hour. If the task is "act on this issue", pass the issue *reference* and let the spawned agent fetch it with its own judgement intact.

## Why not hand-roll it

Three things fail silently if you script this yourself with `tmux new-session` + `send-keys`:

1. **`send-keys` races the shell.** Keys sent to a new pane land before the zsh line editor is ready and get swallowed or mangled. The script uses Claude Code's positional `[prompt]` argument instead — no timing element at all.
2. **A bare command string loses the `claude()` wrapper.** tmux runs command strings under a non-interactive shell, which sources `.zshenv` only, and `.zshenv` does not source aliases. You silently get the raw binary without venv activation, git-root cd, `CLAUDE_CODE_TASK_LIST_ID`, or channel auto-detection. The script uses `zsh -ic`.
3. **Quoting the prompt through bash → sh → zsh eats it.** The script passes it as a tmux session environment variable (`new-session -e`) and clears it from the session environment immediately after, so no quoting layer ever sees the text and it never lingers in `tmux show-environment`.

## A seed is an argument, exactly as if you typed it

The seed goes to Claude positionally, with no option terminator, because that is what a hand-typed session does. Two consequences worth knowing rather than being surprised by:

- A seed that *is* a subcommand name runs that subcommand. `claude-spawn "doctor"` runs `claude doctor`, just as typing it would. Verified against Claude Code 2.1.222.
- A seed starting with a dash is read as an option.

An earlier version put `--` before the seed to prevent both. It was removed: it made the spawned session behave *differently* from one you start yourself, and it pushed the `claude()` wrapper's auto-detected `--channels` past the terminator, silently disabling the channel. If a seed might collide, phrase it as a sentence — "run the doctor command" rather than "doctor".

`claude --tmux` is not an alternative — it requires `--worktree`, so it cannot target an arbitrary directory.

## Task lists scope themselves; setting the ID is only for sharing one on purpose

`CLAUDE_CODE_TASK_LIST_ID` is deliberately NOT auto-generated by the `claude()` wrapper. Claude Code already gives every session its own task list when the variable is unset — measured 2026-08-28 in `~/.claude/tasks/`: **683** `session-<id>` lists it created itself against **11** `<ts>_UTC_<dir>` from ~2 months of the wrapper auto-generating. The auto-generated ID bought nothing the platform was not already doing, and cost a leak no wrapper can close: the ID must be exported into the claude process for Claude Code to read it, so every session that process spawns — **the `claude agents` view included** — inherits it. That is a different path from the shell leak, and it is unreachable from the shell. Do not reintroduce auto-generation; if a session's tasks look wrong, check what set the variable rather than adding logic to manage it.

Setting the variable is for **one purpose only: making two sessions share one list on purpose**. `claude -t <name>` binds one for that launch with `local -x`, so it is unwound on every exit including a Ctrl-C (PTY-verified: a plain `export` leaks the ID at status 130). `claude-new`, `claude-with <id>` and `claude-last` pass one via prefix-env; an inherited ID is passed straight through untouched.

Anything that launches a session through tmux must **`unset` both vars inside the command**, not blank them with `-e`: the wrapper no longer regenerates from an empty value, so a blank is passed through as a literal empty list name, and tmux's `-e` can set a variable but not remove one. `custom_bins/claude-spawn` and `_cw_launch` both do this. Such launchers must also go through `zsh -ic` — tmux runs a bare command string under a non-interactive shell that sources no aliases, so `claude` there is the raw binary. Two measured gotchas: tmux `-e` does **not** override `PATH` for a session's initial command, and zsh's `printf %q` emits `$'\t'` which dash (Debian/Ubuntu `/bin/sh`) mis-parses — use POSIX single-quote escaping.

Pinned by `tests/test_claude_task_list_scope.zsh` (15), `tests/test_task_list_pin_bash.sh` (8, bash — `deploy.sh` sources these aliases into `~/.bashrc`, and bash/zsh have diverged here before), `tests/test_claude_task_list_sigint.py` (PTY Ctrl-C) and `tests/test_cw_resume_env.zsh` (`CW_TEST_MUTATE=1` reproduces the leak) — all four mutation-verified.
