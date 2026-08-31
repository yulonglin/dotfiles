---
name: mats-slurm
description: SLURM helpers for the MATS compute cluster — interactive and batch GPU jobs on A100 and L40, queue and GPU-availability monitoring, log tailing, and the one-time alias setup. Use when submitting or watching a job on MATS, when `grun`, `gbatch`, `arun`, `jlog` or `te` appear, or when a cluster job is queued, pending or failing to get a GPU.
---

# MATS SLURM

Cluster-specific mechanics only. What makes a run worth submitting, and what makes it trustworthy when it lands, is in `~/.claude/checklists/experiments.md` — read that before you submit, not this file.

## Quick Setup

1. **Create log directories**: `mkdir -p ~/slurmlogs ~/slurmerrors`
2. **Install aliases**: source `~/.claude/skills/mats-slurm/templates/slurm_aliases.sh` from your shell config.

## Detailed Reference

`~/.claude/skills/mats-slurm/REFERENCE.md` has the full command list (`grun`, `gbatch`, `jlog`, `te`, `arun`), the GPU types and the configuration variables. Read it when you need a flag rather than the shape.

## Working Pattern

Submit long runs with `gbatch`, watch them with `jlog` and `te`, and use `arun` for an interactive shell when a run needs debugging on the node itself.

## Reach for a neighbour instead when

- the machine is **not** the MATS cluster — local pueue, `jexp`, resource caps and sandbox failure modes are the `jobs` skill
- the question is whether the run is **designed** right — pilot gates, spend gates, manifests, resumability: `~/.claude/checklists/experiments.md`
- the run has finished and the question is what it **means**: `~/.claude/checklists/results-analysis.md`
