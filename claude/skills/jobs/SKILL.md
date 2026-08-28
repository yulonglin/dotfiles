---
name: jobs
description: Submit experiments or agent jobs with resource limits, check queue status, pause/resume workloads, troubleshoot slow machine
---

# Job Management (Pueue + systemd)

Local job queue with cgroup-enforced CPU/memory limits.

**Not every job belongs here**: this queue is for memory-heavy or long-lived work (>~2 GB RSS or >~1 h). Pure API fan-out (monitor/judge passes, rollout batches throttled by `max_connections`) runs via Bash `run_in_background` from main context instead — pueue's cgroup caps buy nothing for API-bound work and the queue only adds latency behind whatever else is running (`rules/experiments.md`). **Never launch detached work from inside a subagent**: it is orphaned when the subagent's turn ends (`rules/delegation.md`).

## Commands

| Command | What it does |
|---------|-------------|
| `jexp <cmd>` | Submit experiment (resource-capped, API keys auto-loaded) |
| `jagent <cmd>` | Submit agent job (resource-capped, API keys auto-loaded) |
| `jclaude <args>` | Headless claude --print through agent queue |
| `jls` | Queue status |
| `jlog [id]` | Job output (falls back to the unit's journal when pueue captured none) |
| `jfollow <id>` | Stream live output |
| `jwait <id...>` | Block until tasks finish; exit 0 only if all succeeded |
| `jkeys` | Write/refresh the mode-600 API-key file for the current repo |
| `jpause <group\|all>` | Pause group |
| `jresume <group\|all>` | Resume group |
| `jkill <id>` | Kill job |
| `jclean` | Remove completed |
| `jwatch` | Live dashboard |
| `jtop` | Status + cgroup usage |
| `jguard` | Memory pressure check |

## Automatic API-key loading (2026-08-27)

direnv/bws never resolves inside systemd user units, so pueue jobs used to start keyless and die on auth. `jexp`/`jagent` now handle this automatically: on submit they find (or create, from the repo's main-checkout `.envrc` via `direnv exec`) a mode-600 key file under `~/.local/state/jkeys/`, and the job execs through `jkeys exec`, which sources it. Nothing to wrap manually — a bare `jexp python foo.py` just works.

- Opt out: `JEXP_NO_KEYS=1 jexp <cmd>`. Override the file: `JEXP_KEY_FILE=<path>`.
- The key file is a snapshot — re-run `jkeys` after rotating keys.
- Outside a git repo (or a repo without `.envrc`) the shim is skipped silently.

## Where job output lives

`jrun` submits via `systemd-run --pipe --same-dir`, so the job's stdout/stderr lands in **pueue's log** (`jlog <id>`) and the job runs in the **submission cwd**. For tasks submitted before 2026-08-27 output went only to the journal; `jlog` detects that (pueue log holding only systemd-run status lines) and automatically appends `journalctl --user -u jrun-*/run-uNNN.service -o cat`.

## Groups

| Group | Use | Parallel | CPU | Memory |
|-------|-----|----------|-----|--------|
| experiments | ML training, heavy compute | 3 | per resources.conf | per resources.conf |
| agents | Claude Code, Codex CLI | 3 | per resources.conf | per resources.conf |

Parallel=3 because most jobs are API-bound (at 1, ~10 independent jobs serialised for an hour on 2026-08-27). `config/resources.conf` is the source of truth and `deploy.sh --pueue` applies it; `jrun` also applies it when it self-heals a missing group. For a memory-heavy stage (USACO-style sandboxes, big `.eval` readers), drop it live first: `pueue parallel 1 --group experiments`, restore after.

## Common Scenarios

**Run an experiment:** `jexp python train.py --epochs 100`

**Machine feels slow:** `jguard` to check pressure, `jpause experiments` to free resources

**Multiple agents:** `jagent claude --print "review src/"` — queued if slots full

**Chain on completion:** `jwait 12 13 && python analyze.py`

**Scale up:** Edit `config/resources.conf`, run `./deploy.sh --pueue`

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Job dies instantly with auth error | Should no longer happen (keys auto-load); if it does: `jkeys` in the repo, check `jkeys path` file exists and lists the right names, ensure `JEXP_NO_KEYS` isn't set |
| `jlog` shows only "exit 1" / status lines | Pre-2026-08-27 task — `jlog <id>` now appends the journal automatically; raw fallback: `journalctl --user -u run-uNNN.service -o cat` |
| `systemd --user not available` | `loginctl enable-linger $(whoami)` |
| Memory limits silently ignored | `sudo systemctl set-property user-$(id -u).slice Delegate=yes` |
| pueued not running | `systemctl --user start pueued` |

## Memory caps: never `MemoryHigh` as the safety limit

Any reader or analysis process expected past ~2 GB RSS runs under `capped -- <cmd>` (`custom_bins/capped`), which applies `MemoryMax`, takes an exclusive lock so only one heavy reader runs per box, and fails closed rather than running uncapped. Full-file log parsers cost order-30× file size in RSS — stream per-sample where the API allows.

`MemoryHigh` throttles rather than kills, and with `MemorySwapMax=0` a runaway sits between High and Max indefinitely instead of dying. Measured 2026-08-18: a 2 GB allocation under `MemoryMax=256M` survived past 90 s with High at 80% and 95%; without High it was killed in ~1 s. A cap that hangs is worse than no cap, because nothing reports the stall.

Disk is shared across sessions: bulk pulls (Modal volumes, HF snapshots) target a data volume or a checked path, never the root fs, and a free-space watchdog runs whenever a long job is in flight.

## Check group parallelism before a fan-out

A serial group turns N independent jobs into N× wall-clock, and this is invisible in `pueue status` unless you read the group header — run `pueue group` first. Measured 2026-08-27: ~10 independent API-bound jobs sat an hour behind `experiments` at `parallel=1`. Both groups default to 3 now (`config/resources.conf`, applied by `deploy.sh --pueue` and by `jrun`'s group self-heal). Drop it live for a memory-heavy stage: `pueue parallel 1 --group experiments`.

## `excludedCommands` does not do what its entries look like they do

Verified on Claude Code 2.1.237 (2026-08-20): a **bare-word** entry compiles to an **exact-string** matcher against the whole command line, so `"pueue"` matches only the literal command `pueue` and never `pueue status` — measured, bare `pueue` printed the queue while `pueue status` died sandboxed on "Failed to initialize client". Every entry in the current global settings is a bare word, so all of them are inert for any invocation carrying arguments, `pueue` and `systemctl` included. The prefix form `"pueue:*"` is what matches an invocation with arguments.

Assume `jexp`/`pueue`/`systemctl --user` run sandboxed and need `dangerouslyDisableSandbox: true`. If `systemd --user` is unavailable: `loginctl enable-linger $(whoami)`. If memory limits are silently ignored: `sudo systemctl set-property user-$(id -u).slice Delegate=yes`.

## Sandbox failure modes

| Symptom | Reality | Fix |
|---|---|---|
| Temp writes fail | `/tmp` is restricted | `$TMPDIR` (`/tmp/claude/`) or project-local `./tmp/` |
| Heredoc (`<<EOF`) in a command | The shell writes its temp file to a denied path → **empty commit message**, failed commit | `mkdir -p "$TMPDIR" && printf '%s\n' "subject" "" "body" > "$TMPDIR/msg.txt" && git commit -F "$TMPDIR/msg.txt"`. `-m` is fine for one-liners |
| Background job writing `$CLAUDE_JOB_DIR/tmp/…` | Writes under `~/.claude/jobs` are denied, so the redirect **silently creates nothing** and `git commit -F` then fails with "could not read log file" | Use `$TMPDIR` with a job-unique name (`$TMPDIR/<jobid>-commit-msg.txt`) |
| `git pull`/`merge`/`stash` → "Read-only file system" or "unable to unlink" | Runtime `denyWithinAllow` on `config/`, `.claude/settings.json`, `.claude/skills/`, injected by Claude Code and not user-configurable — `git` being in `excludedCommands` does not help | Retry immediately with `dangerouslyDisableSandbox: true`. Do not reach for patch files or sparse checkout |
| Phantom dotfiles in `git status`/`ls -la` as `crw-rw-rw- … 1, 3 … nobody` | **Linux bubblewrap only** — denied paths are masked by bind-mounting `/dev/null` over them. Not repo content; `git fetch`/submodule ops hit "Permission denied" on them (e.g. `.gitmodules`). macOS Seatbelt does not do this | Confirm with `find . -maxdepth 2 -type c`. Never `git add -A`. If a git op genuinely needs the masked path, `dangerouslyDisableSandbox: true` |
