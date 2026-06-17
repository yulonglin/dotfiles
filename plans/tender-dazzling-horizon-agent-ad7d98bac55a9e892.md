# Local Resource Management Tools Research

Research date: 2026-04-03

## 1. Cgroup v2 / systemd Wrappers for Resource-Limited Job Execution

### Tier 1: Production-Ready, Well-Maintained

| Tool | GitHub | Stars | Language | Last Updated | What It Does |
|------|--------|-------|----------|-------------|--------------|
| **nsjail** | [google/nsjail](https://github.com/google/nsjail) | 3,803 | C++ | 2026-04 | Full sandbox: namespaces + cgroups v2 + rlimits + seccomp. CLI flags for `--cgroup_mem_max`, `--cgroup_cpu_ms_per_sec`, `--cgroup_pids_max`. Originally for CTF/contest judging, now used broadly. **Best "run this command with limits" tool.** |
| **isolate** | [ioi/isolate](https://github.com/ioi/isolate) | 1,407 | C | 2026-03 | IOI competitive programming sandbox. cgroups v1/v2, namespaces, wall/CPU time limits, memory limits. Used by Judge0. More focused than nsjail (contest-oriented). |
| **firejail** | [netblue30/firejail](https://github.com/netblue30/firejail) | 7,241 | C | 2026-04 | SUID sandbox using namespaces, seccomp-bpf, capabilities, cgroups. Has `--rlimit-as`, `--rlimit-cpu`, `--cpu` (core pinning). More security-focused than resource-focused but does both. |
| **bubblewrap** | [containers/bubblewrap](https://github.com/containers/bubblewrap) | 6,507 | C | 2026-04 | Lightweight unprivileged sandboxing (used by Flatpak). Namespace isolation only -- **no built-in resource limits**. Must pair with `systemd-run` for cgroup limits. |

### Tier 2: Smaller/Niche but Relevant

| Tool | GitHub | Stars | Language | Last Updated | What It Does |
|------|--------|-------|----------|-------------|--------------|
| **sandbox-rs** | [ErickJ3/sandbox-rs](https://github.com/ErickJ3/sandbox-rs) | 72 | Rust | 2026-03 | Rust sandbox with cgroups v2, seccomp, Landlock. CLI tool `sandbox-ctl` for running with resource limits. Newer, actively maintained. |
| **go-sandbox** | [criyle/go-sandbox](https://github.com/criyle/go-sandbox) | 252 | Go | 2026-04 | Go library/CLI: namespaces + cgroups + ptrace + seccomp. Originally for online judges, reusable. |
| **proclimit** | [aoldershaw/proclimit](https://github.com/aoldershaw/proclimit) | 17 | Go | 2025-11 | Minimal Go library/CLI: `proclimit -cpu=50 -memory=512M cmd`. Cross-platform (Linux cgroups, Windows Job Objects). Very small, focused. |
| **cielcg** | [cielavenir/cielcg](https://github.com/cielavenir/cielcg) | 8 | Python | 2025-07 | cgexec alternative for cgroups v1 and v2. Tiny, minimal. |
| **mk-fg/fgtk** (cg-exec) | [mk-fg/fgtk](https://github.com/mk-fg/fgtk) | 179 | Python | 2026-03 | Toolkit with `cg-exec` -- a systemd-run wrapper that runs commands in transient scopes within pre-defined slices. Supports CPUWeight, IOWeight, MemoryHigh, MemoryMax via hierarchical slices. **Closest to "nicer systemd-run".** |

### Built-in (No Install Required)

| Tool | What It Does | Limitations |
|------|-------------|-------------|
| **systemd-run --scope** | `systemd-run --scope -p MemoryMax=2G -p CPUQuota=200% ./cmd` | Verbose flags, no queueing, no persistence |
| **cgexec** (libcgroup-tools) | Classic cgroups v1 tool, `cgexec -g memory,cpu:mygroup cmd` | cgroups v1 only, deprecated on modern distros |
| **ulimit / prlimit** | Per-process resource limits (not cgroup-based) | No memory cgroup enforcement, soft limits only |

## 2. Job Queuing Tools (No Built-in Resource Limits)

| Tool | GitHub | Stars | Language | Resource Limits? | Notes |
|------|--------|-------|----------|-----------------|-------|
| **Pueue** | [Nukesor/pueue](https://github.com/nukesor/pueue) | 6,120 | Rust | **No** -- parallelism control only (slots per group) | No cgroup/rlimit integration. No open feature request found for it. Groups control *concurrency* not *resources*. |
| **task-spooler** | [justanhduc/task-spooler](https://github.com/justanhduc/task-spooler) | 403 | C | **No** -- slot-based concurrency, GPU device visibility | `TS_SLOTS` for max concurrent jobs, `TS_VISIBLE_DEVICES` for GPU selection. No memory/CPU cgroup limits. |
| **nq** | [leahneukirchen/nq](https://github.com/leahneukirchen/nq) | 3,110 | C | **No** | Daemonless directory-based queue. Pure sequencing, no resource awareness at all. |

**Key finding: None of these job queues have built-in resource enforcement.** You'd need to compose them (e.g., `pueue add -- systemd-run --scope -p MemoryMax=4G ./train.py`).

## 3. OOM Protection Daemons

| Tool | GitHub | Stars | Language | Approach | Best For |
|------|--------|-------|----------|----------|----------|
| **earlyoom** | [rfjakob/earlyoom](https://github.com/rfjakob/earlyoom) | 3,954 | C | Polls available memory/swap, kills highest oom_score when below threshold | Simple workstations, embedded, old kernels |
| **nohang** | [hakavlad/nohang](https://github.com/hakavlad/nohang) | 1,254 | Python | Highly configurable earlyoom alternative with desktop notifications, per-app rules, PSI support | Desktop users wanting fine-grained control |
| **systemd-oomd** | (part of systemd) | N/A | C | Uses PSI (Pressure Stall Information) + cgroups v2, kills cgroup-level not process-level | Modern distros (Fedora default since 34), per-slice policies |

**Recommendation:** systemd-oomd if on a modern distro (cgroups v2 + systemd 248+). earlyoom as a fallback for simplicity. nohang if you need per-app kill policies or desktop notifications.

## 4. CPU Limiting (Per-Process, No Cgroups)

| Tool | GitHub | Stars | Language | What It Does |
|------|--------|-------|----------|--------------|
| **cpulimit** | [opsengine/cpulimit](https://github.com/opsengine/cpulimit) | 1,766 | C | Sends SIGSTOP/SIGCONT to throttle a process to N% CPU. Works without cgroups or root. Crude but effective. |

## 5. ML Experiment Schedulers (Local, Resource-Aware)

| Tool | GitHub | Stars | Language | What It Does |
|------|--------|-------|----------|--------------|
| **ml-scheduler** | [huyiwen/ml_scheduler](https://github.com/huyiwen/ml_scheduler) | 6 | Python | Lightweight Python experiment scheduler with GPU/model resource pools and async execution. Very small. |
| **mle-scheduler** | [mle-infrastructure/mle-scheduler](https://mle-infrastructure.github.io/mle_scheduler/) | ~100 | Python | Job queue for Slurm/SGE/SSH/GCP. Overkill for single-machine. |

## 6. Claude Code Skills/Plugins for Resource Management

**Nothing found.** Searched across:
- [awesome-claude-code](https://github.com/hesreallyhim/awesome-claude-code) (curated list)
- [claude-code-plugins-plus-skills](https://github.com/jeremylongshore/claude-code-plugins-plus-skills) (340 plugins, 1367 skills)
- [awesome-agent-skills](https://github.com/VoltAgent/awesome-agent-skills) (1000+ skills)
- [awesome-claude-code-toolkit](https://github.com/rohitg00/awesome-claude-code-toolkit) (135 agents, 35 skills)

No existing skill/plugin for resource management, job scheduling, pueue integration, or cgroup enforcement. This is a gap.

## 7. "Coding Agents Eating Resources" (2024-2026)

### What Exists

- **systemd 260-rc3** (2026): Added `AGENTS.md` documentation for AI agents -- but this is about agents *contributing to systemd*, not resource-limiting agents.
- **Northflank guide** (2026): [How to sandbox AI agents](https://northflank.com/blog/how-to-sandbox-ai-agents) -- covers microVMs, gVisor, containers for agent isolation. Cloud-focused, not local workstation.
- **No dedicated tool found** specifically for "limit Claude Code / Codex / coding agents on a shared workstation." This is genuinely a new pain point without a purpose-built solution.

### The Gap

The problem is real but unsolved by any single tool:
- Coding agents spawn many subprocesses (npm install, cargo build, pytest, etc.)
- These inherit no resource limits by default
- Multiple agents running in parallel can exhaust memory/CPU
- No tool combines: (a) job queueing, (b) cgroup enforcement, (c) agent-awareness

## Comparison: Approaches for Your Use Case

| Approach | Queueing | CPU Limit | Memory Limit | Ease of Use | Root Required? |
|----------|----------|-----------|-------------|-------------|---------------|
| **Pueue + systemd-run** (compose) | Yes (Pueue) | Yes (systemd) | Yes (systemd) | Medium -- manual composition | No (user scope) |
| **nsjail** | No | Yes (cgroup) | Yes (cgroup) | Good CLI UX | Yes (or user ns) |
| **systemd slices** (manual) | No | Yes | Yes | Low -- lots of config | No (user slices) |
| **firejail** | No | Partial (rlimit) | Partial (rlimit) | Good -- single command | SUID binary |
| **cpulimit** | No | Yes (SIGSTOP) | No | Trivial | No |
| **sandbox-rs** | No | Yes (cgroup v2) | Yes (cgroup v2) | CLI tool | Needs cgroup delegation |
| **mk-fg/fgtk cg-exec** | No | Yes (systemd) | Yes (systemd) | Good -- slice presets | No (user scope) |
| **Custom skill (Pueue + systemd-run + earlyoom)** | Yes | Yes | Yes + OOM safety | Would need building | No |

## Recommendation

**Best pragmatic stack for "coding agents on shared workstation":**

1. **Pueue** for job queueing and concurrency control (already excellent)
2. **systemd-run --user --scope** for per-job cgroup limits (compose with Pueue via wrapper)
3. **earlyoom** or **systemd-oomd** as safety net for OOM prevention
4. **A thin wrapper script** or Claude Code skill that composes these three

**If you want a single binary:** nsjail is the closest -- it does cgroup enforcement + process isolation in one tool, but has no queueing.

**If you want minimal setup:** `cpulimit` for CPU + `ulimit -v` for memory + Pueue for queueing. Crude but zero-config.
