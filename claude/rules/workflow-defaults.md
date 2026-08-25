# Workflow Defaults

## Plans

`plansDirectory` resolves relative to CWD, not the git root — plans land in the wrong place if the session didn't start at the repo root. The `claude()` wrapper auto-cds there; the `check_git_root.sh` SessionStart hook warns when it isn't. Set it in the global `settings.json`. Plan filenames are auto-generated, not yet configurable (claude-code [#21342](https://github.com/anthropics/claude-code/issues/21342), open as of 2026-07-27). `CLAUDE_CODE_TASK_LIST_ID` is auto-set by the `claude()` wrapper in `config/aliases/claude.sh`.

## Config-First

Behavioral instructions ("allow X", "always do Y", "stop doing Z") become durable config — `settings.json` permissions or hooks, or `rules/*.md` — not memory. Memory is only for what can't be encoded as config: user identity, project history, external references.

## Files

Never use `.local.md` unless explicitly asked — default to `.md`, which is version-controlled.

## Shell

Piped output that appears stuck is usually block-buffering (libc switches from line to block buffering when stdout isn't a TTY): use `stdbuf -oL cmd | ...` or Python's `-u`. Duplicate skills in the slash picker are plugin-created symlinks in `~/.claude/skills/` — run `clean-skill-dupes`.

## Experiments

Run experiments and compute-heavy jobs through `jexp` (Pueue with systemd cgroup caps from `config/resources.conf`), not bare `uv run python` — direct runs have no resource limits and can starve the machine. **`excludedCommands` does not do what its entries look like they do.** Verified on Claude Code 2.1.237 (2026-08-20): a **bare-word** entry compiles to an **exact-string** matcher against the whole command line, so `"pueue"` matches only the literal command `pueue` and never `pueue status` — measured, bare `pueue` printed the queue while `pueue status` died sandboxed on "Failed to initialize client". Every entry in the current global settings is a bare word, so **all of them are inert for any invocation carrying arguments**, `pueue` and `systemctl` included. The correct prefix form is `"pueue *"` — entries use the *content* syntax of a `Bash(...)` permission rule (docs: "an exact command, a prefix such as `docker *`, or a wildcard pattern"), **not** the `Bash(pueue:*)` rule-name colon form; and "when any part of a compound command matches an entry, Claude Code runs the whole command unsandboxed", so a prefix entry also unsandboxes any pipeline or `&&` chain containing that segment. The settings file has **not** been changed — that edit is pending Yulong's permission — so the bug is live: assume `jexp`/`pueue`/`systemctl --user` run sandboxed and need `dangerouslyDisableSandbox: true` (see `docs/sandbox-troubleshooting.md` for why no allowlist entry can fix it). If `systemd --user` is unavailable: `loginctl enable-linger $(whoami)`. If memory limits are silently ignored: `sudo systemctl set-property user-$(id -u).slice Delegate=yes`.

## Spend

Before a billed run, estimate cost from actual rates (`llm-billing` agent for current pricing). Under $100 → run now, report the estimate with the result. $100+ → propose the estimate and wait for go-ahead. SLURM allocations (Silico, MATS) are pre-paid — skip the gate.

## Research Artifacts

Non-code artifacts (specs, plans, docs, run outputs) live in the personal vault via one symlink per directory — never a single root-level `repo/vault` symlink, which breaks every existing relative-path reference. Layout: `docs/research-methodology.md`
