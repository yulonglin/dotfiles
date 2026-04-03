---
name: jobs
description: Submit experiments or agent jobs with resource limits, check queue status, pause/resume workloads, troubleshoot slow machine
---

# Job Management (Pueue + systemd)

Local job queue with cgroup-enforced CPU/memory limits.

## Commands

| Command | What it does |
|---------|-------------|
| `jexp <cmd>` | Submit experiment (resource-capped) |
| `jagent <cmd>` | Submit agent job (resource-capped) |
| `jclaude <args>` | Headless claude --print through agent queue |
| `jls` | Queue status |
| `jlog [id]` | Job output |
| `jfollow <id>` | Stream live output |
| `jpause <group\|all>` | Pause group |
| `jresume <group\|all>` | Resume group |
| `jkill <id>` | Kill job |
| `jclean` | Remove completed |
| `jwatch` | Live dashboard |
| `jtop` | Status + cgroup usage |
| `jguard` | Memory pressure check |

## Groups

| Group | Use | Parallel | CPU | Memory |
|-------|-----|----------|-----|--------|
| experiments | ML training, heavy compute | 1 | per resources.conf | per resources.conf |
| agents | Claude Code, Codex CLI | 3 | per resources.conf | per resources.conf |

## Common Scenarios

**Run an experiment:** `jexp python train.py --epochs 100`

**Machine feels slow:** `jguard` to check pressure, `jpause experiments` to free resources

**Multiple agents:** `jagent claude --print "review src/"` — queued if slots full

**Scale up:** Edit `config/resources.conf`, run `./deploy.sh --pueue`

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `systemd --user not available` | `loginctl enable-linger $(whoami)` |
| Memory limits silently ignored | `sudo systemctl set-property user-$(id -u).slice Delegate=yes` |
| pueued not running | `systemctl --user start pueued` |
