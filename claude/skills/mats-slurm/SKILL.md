---
name: mats-slurm
description: Set up and use SLURM helpers for the MATS compute cluster with A100 and L40 GPUs.
---

# MATS SLURM Skill

Set up and use SLURM helpers for the MATS compute cluster with A100 and L40 GPUs.

## When to Use This Skill
- Setting up SLURM aliases for a new MATS cluster user
- Running interactive GPU jobs (A100 or L40)
- Submitting batch jobs
- Monitoring job queues and GPU availability
- Viewing and tailing job logs

## Quick Setup
1. **Create Log Directories**: `mkdir -p ~/slurmlogs ~/slurmerrors`
2. **Install Aliases**: Source `~/.claude/skills/mats-slurm/templates/slurm_aliases.sh` in your shell config.

## Detailed Reference
For a complete list of commands (`grun`, `gbatch`, `jlog`, etc.), GPU types, and configuration variables, read:
`~/.claude/skills/mats-slurm/REFERENCE.md`

## Integration with Claude Code
- **Run experiments**: Use `gbatch` for long-running experiments
- **Monitor**: Use `jlog` and `te` to show logs to Claude
- **Debug**: Use `arun` to get shell access for debugging