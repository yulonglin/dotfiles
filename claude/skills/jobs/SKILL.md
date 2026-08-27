---
name: jobs
description: Submit experiments or agent jobs with resource limits, check queue status, pause/resume workloads, troubleshoot slow machine
---

# Job Management (Pueue + systemd)

Local job queue with cgroup-enforced CPU/memory limits.

**Not every job belongs here**: this queue is for memory-heavy or long-lived work (>~2 GB RSS or >~1 h). Pure API fan-out (monitor/judge passes, rollout batches throttled by `max_connections`) runs via Bash `run_in_background` from main context instead — see `claude/rules/workflow-defaults.md` § Experiments.

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
