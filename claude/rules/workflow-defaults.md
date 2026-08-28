# Workflow Defaults

## Plans

`plansDirectory` resolves relative to CWD, not the git root — plans land in the wrong place if the session didn't start at the repo root. The `claude()` wrapper auto-cds there; the `check_git_root.sh` SessionStart hook warns when it isn't. Set it in the global `settings.json`. Plan filenames are auto-generated, not yet configurable (claude-code [#21342](https://github.com/anthropics/claude-code/issues/21342), open as of 2026-07-27). `CLAUDE_CODE_TASK_LIST_ID` is auto-set by the `claude()` wrapper in `config/aliases/claude.sh`, **scoped to the launch**: the wrapper mints `<UTC timestamp>_UTC_<dir basename>_<pid>-<random>` just before exec and binds it function-locally, so no session leaves a task-list ID behind. The pid/random suffix is not decoration — `claude-spawn` fans parallel agents into one repo, and a bare timestamp handed them all one shared list. A **manual `export` of this variable does nothing** — an inherited ID is honored only alongside `CLAUDE_CODE_TASK_LIST_PIN=1`, because an unpinned inherited value is indistinguishable from stale residue in a long-lived shell or the tmux server environment. That residue was the 2026-08-25→28 bug: one ID minted in `~/code` was silently shared by sessions and background jobs across unrelated repos for three days. To share a list deliberately use `claude -t <name>`, `claude-new`, `claude-with <id>` or `claude-last` — all of which pin, and `-t` beats an active pin. The pin is **consumed, not inherited**: the wrapper unsets it before exec, so nested launches inside a pinned session mint fresh instead of honoring the parent's ID forever.

Two mechanics make this hold, and both are load-bearing. The ID is bound with **`local -x`, never a manual save/restore** — zsh unwinds a function-local binding on every exit including a Ctrl-C, whereas a restore placed after `command claude` is measurably skipped by SIGINT (PTY-verified: status 130 with the ID still exported). And **anything launching a session through tmux must go via `zsh -ic`** with both task-list vars blanked (`-e`), the way `custom_bins/claude-spawn` does: tmux runs a bare command string under a non-interactive shell that sources no aliases, so `claude` there is the raw binary and inherits whatever the tmux *server* environment holds — a server started from a contaminated shell re-introduces the bug through a launcher that looks fixed. Note `-e` does **not** override `PATH` for a session's initial command; the server inherits that from whoever started it. Pinned by `tests/test_claude_task_list_scope.zsh` (17 checks), `tests/test_claude_task_list_sigint.py` (PTY Ctrl-C), and `tests/test_cw_resume_env.zsh` (`CW_TEST_MUTATE=1` reproduces the pre-fix leak) — all three mutation-verified.

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
