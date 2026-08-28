# Workflow Defaults

## Plans

`plansDirectory` resolves relative to CWD, not the git root — plans land in the wrong place if the session didn't start at the repo root. The `claude()` wrapper auto-cds there; the `check_git_root.sh` SessionStart hook warns when it isn't. Set it in the global `settings.json`. Plan filenames are auto-generated, not yet configurable (claude-code [#21342](https://github.com/anthropics/claude-code/issues/21342), open as of 2026-07-27). **`CLAUDE_CODE_TASK_LIST_ID` is deliberately NOT set by the `claude()` wrapper.** Claude Code already gives every session its own task list when the variable is unset — measured 2026-08-28 in `~/.claude/tasks/`: **683** `session-<id>` lists it created itself against **11** `<ts>_UTC_<dir>` from ~2 months of the wrapper auto-generating. The auto-generated ID therefore bought nothing the platform was not already doing, and cost a leak no wrapper can close: the ID must be exported into the claude process for Claude Code to read it, so every session that process spawns — **the `claude agents` view included** — inherits it. That is a different path from the shell leak, and it is unreachable from the shell. Do not reintroduce auto-generation; if a session's tasks look wrong, check what set the variable rather than adding logic to manage it.

`claude -t <name>` is the **only** way to set one, and it binds with `local -x` so it is unwound on every exit including a Ctrl-C (PTY-verified: a plain `export` leaks the ID at status 130). The `claude-new` / `claude-with` / `claude-last` / `claude-tasks-list` helpers and the `CLAUDE_CODE_TASK_LIST_PIN` marker were **deleted on 2026-08-28**: zsh history showed zero real uses across 1,283 lines, while they were the last code able to set the variable — i.e. the only remaining way to reintroduce a shared list. Do not restore them; a test asserts they stay gone.

**Every inherited ID is removed from the child's environment**, via `env -u`, with no exceptions — `-t` sets its own, so nothing legitimate arrives by inheritance. This matters because `source ~/.zshrc` cannot unset what an older wrapper already exported, so a long-lived shell keeps its stale ID until it dies; honoring inherited values is how the cross-repo leak survived a re-source (observed 2026-08-28, now pinned by a test). `env -u` rather than `local +x` or `unset` because the value must be absent from the **child**, and `local +x` does not shadow a globally exported variable under bash.

**The `claude daemon` is the last place a stale ID can hide, and no shell fix reaches it.** Sessions started from the `claude agents` view are spawned by the daemon (`claude daemon run`), not by the shell — verified by parentage: every `bg-pty-host` / `bg-spare` is its child. The daemon inherits its environment once, at start, and hands that to every session it spawns for its whole lifetime. So a daemon started from a shell carrying a stale ID keeps distributing it *hours after* the wrapper is fixed and `~/.zshrc` re-sourced (observed 2026-08-28: a daemon from 01:51 still handing out `20260825_060521_UTC_code` to children spawned at 06:38). You cannot unset it from inside a session either — the list is chosen at spawn.

Diagnose by reading the process environment directly, never by inference: `tr '\0' '\n' < /proc/<pid>/environ | grep CLAUDE_CODE_TASK_LIST`, across `pgrep -f claude` with `ps -o lstart=` so start times separate pre- from post-fix processes. Fix by restarting the daemon from a clean shell — `unset CLAUDE_CODE_TASK_LIST_ID && claude daemon stop --any --keep-workers`; `--keep-workers` leaves detached sessions running, and the daemon respawns on demand.

Anything that launches a session through tmux must **`unset` both vars inside the command**, not blank them with `-e`: the wrapper no longer regenerates from an empty value, so a blank is passed through as a literal empty list name, and tmux's `-e` can set a variable but not remove one. `custom_bins/claude-spawn` and `_cw_launch` both do this. Such launchers must also go through `zsh -ic` — tmux runs a bare command string under a non-interactive shell that sources no aliases, so `claude` there is the raw binary. Two measured gotchas: tmux `-e` does **not** override `PATH` for a session's initial command, and zsh's `printf %q` emits `$'\t'` which dash (Debian/Ubuntu `/bin/sh`) mis-parses — use POSIX single-quote escaping. Pinned by `tests/test_claude_task_list_scope.zsh` (15), `tests/test_task_list_pin_bash.sh` (8, bash — `deploy.sh` sources these aliases into `~/.bashrc`, and bash/zsh have diverged here before), `tests/test_claude_task_list_sigint.py` (PTY Ctrl-C) and `tests/test_cw_resume_env.zsh` (`CW_TEST_MUTATE=1` reproduces the leak) — all four mutation-verified.

## Config-First

Behavioral instructions ("allow X", "always do Y", "stop doing Z") become durable config — `settings.json` permissions or hooks, or `rules/*.md` — not memory. Memory is only for what can't be encoded as config: user identity, project history, external references.

## Files

Never use `.local.md` unless explicitly asked — default to `.md`, which is version-controlled.

## Shell

Piped output that appears stuck is usually block-buffering (libc switches from line to block buffering when stdout isn't a TTY): use `stdbuf -oL cmd | ...` or Python's `-u`. Duplicate skills in the slash picker are plugin-created symlinks in `~/.claude/skills/` — run `clean-skill-dupes`.

## Experiments

The job runner is chosen by the job's resource profile, not by habit (Yulong's decision 2026-08-27, from a live 12-hour multi-agent run):

- **Memory-heavy or long-lived work** — dataset readers, `.eval` parsers, USACO-style sandboxes, anything expected past ~2 GB RSS or ~1 h — goes to pueue via `jexp` (systemd cgroup caps from `config/resources.conf`), never bare `uv run python`: the cgroup caps are what stop the box OOMing, and a direct run has no limits and can starve the machine.
- **Pure API fan-out** — monitor passes, judge passes, rollout batches whose concurrency is `max_connections` — runs via Bash `run_in_background` from MAIN context: pueue's cgroup caps buy nothing for API-bound work, and the queue adds latency behind whatever else is running.
- **Never** launch detached work from inside a subagent — it is orphaned when the subagent's turn ends (`rules/agents-and-delegation.md`, "Never Run Detached Long-Jobs Inside a Subagent").

Evidence: 2026-08-27, ~10 independent API-bound jobs sat serialised behind the `experiments` group's `parallel=1` for an hour; both groups now default to 3 (`config/resources.conf`, applied by `deploy.sh --pueue` and by `jrun`'s group self-heal). Drop it live for memory-heavy stages: `pueue parallel 1 --group experiments`.

### Pueue key loading and output are handled by the wrappers — as of 2026-08-27

A pueue job runs in a systemd user unit, where the `direnv`/bws shell hook never fires, so a raw `pueue add` starts with **no API keys** and its stdout goes to the journal, not pueue's log. The `jexp`/`jagent` wrappers now fix both automatically: they snapshot the repo's `.envrc` keys via `jkeys` (`custom_bins`, mode-600 file under `~/.local/state/jkeys/`) and exec the job through `jkeys exec`; they submit with `systemd-run --pipe --same-dir`, so `jlog <id>` shows the job's real stdout/stderr and the job runs in the submission cwd. `JEXP_NO_KEYS=1` opts out of key loading; re-run `jkeys` after rotating keys. For pre-fix tasks whose output went journal-only, `jlog` appends `journalctl --user -u <unit> -o cat` automatically. `jwait <ids>` blocks until tasks finish (exit 0 only if all succeeded). The `jobs` skill has the full reference.

**`excludedCommands` does not do what its entries look like they do.** Verified on Claude Code 2.1.237 (2026-08-20): a **bare-word** entry compiles to an **exact-string** matcher against the whole command line, so `"pueue"` matches only the literal command `pueue` and never `pueue status` — measured, bare `pueue` printed the queue while `pueue status` died sandboxed on "Failed to initialize client". Every entry in the current global settings is a bare word, so **all of them are inert for any invocation carrying arguments**, `pueue` and `systemctl` included. The prefix form `"pueue:*"` is what matches an invocation with arguments — asserted, not measured here, since settings.json is unchanged. The settings file has **not** been changed — that edit is pending Yulong's permission — so the bug is live: assume `jexp`/`pueue`/`systemctl --user` run sandboxed and need `dangerouslyDisableSandbox: true` (see `docs/sandbox-troubleshooting.md` for why no allowlist entry can fix it). If `systemd --user` is unavailable: `loginctl enable-linger $(whoami)`. If memory limits are silently ignored: `sudo systemctl set-property user-$(id -u).slice Delegate=yes`.

## Spend

Before a billed run, estimate cost from actual rates (`llm-billing` agent for current pricing). Under $100 → run now, report the estimate with the result. $100+ → propose the estimate and wait for go-ahead. SLURM allocations (Silico, MATS) are pre-paid — skip the gate.

## Research Artifacts

Non-code artifacts (specs, plans, docs, run outputs) live in the personal vault via one symlink per directory — never a single root-level `repo/vault` symlink, which breaks every existing relative-path reference. Layout: `docs/research-methodology.md`
