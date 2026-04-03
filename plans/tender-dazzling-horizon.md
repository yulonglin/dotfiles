# Local Resource Management (Pueue + systemd) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Set up local job queuing and resource enforcement so experiments and coding agents can't starve the server.

**Architecture:** Pueue (Rust job queue) manages task groups with parallelism limits. systemd user slices enforce hard CPU/memory caps via cgroups v2. A config file (`config/resources.conf`) uses absolute values for predictable resource partitioning (currently 4 cores / 32GB, planned 32 cores / 128GB — edit config when scaling). systemd-oomd provides OOM safety within the cgroup hierarchy. A Claude Code skill (`/jobs`) documents the workflow.

**Tech Stack:** Pueue, pueued, systemd (user slices + scopes + service + oomd), cgroups v2, shell (zsh)

**Decisions from critique:**
- earlyoom dropped — conflicts with systemd-oomd (`ManagedOOMMemoryPressure=kill` in slices). Use systemd-oomd exclusively.
- `cargo install pueue pueued` — they're separate crates (not just `pueue`).
- jrun() fails loudly when systemd-run unavailable (no silent fallback).
- jguard simplified to ~20 lines (was over-engineered).
- deploy.sh uses `sed` not `sd` for templating (sd edits in-place, piping doesn't work).
- deploy.sh waits for pueued startup before creating groups (race fix).
- Absolute resource values (not percentages) for predictability.

---

## File Structure

| File | Action | Purpose |
|------|--------|---------|
| `config/resources.conf` | Create | Resource partitioning (absolute values, edit when scaling) |
| `config/systemd-user/experiments.slice` | Create | systemd user slice for ML experiments |
| `config/systemd-user/agents.slice` | Create | systemd user slice for coding agents |
| `config/systemd-user/pueued.service` | Create | Auto-start pueue daemon on login |
| `config/pueue.yml` | Create | Pueue daemon config |
| `config/aliases.sh` | Edit (~line 840) | `j*` aliases and wrapper functions |
| `config.sh` | Edit | Add `INSTALL_PUEUE` and `DEPLOY_PUEUE` flags |
| `install.sh` | Edit | Add pueue installation |
| `deploy.sh` | Edit | Add pueue/systemd deployment block |
| `custom_bins/jguard` | Create | Memory pressure check (lean, follows ccusage-guard pattern) |
| `claude/skills/jobs/SKILL.md` | Create | Claude Code skill for job management |

---

## Limitations (honest)

- **No automatic preemption.** Pueue supports manual pause/resume. systemd OOM-kills at MemoryMax but doesn't preempt CPU. Use `jpause experiments` to free resources manually.
- **User-level systemd slices** require `loginctl enable-linger` (one-time, deploy handles it).
- **Cgroup delegation** may need one-time: `sudo systemctl set-property user-$(id -u).slice Delegate=yes`. Without this, MemoryMax is silently ignored. Deploy checks and warns.
- **`systemd --user` unavailable inside Claude Code sandbox** (bubblewrap). Works from normal shell.
- **Interactive claude TUI doesn't work through Pueue** (captures stdout). `jclaude` is for `--print` / headless only.

---

### Task 1: Resource Config File

**Files:**
- Create: `config/resources.conf`

- [ ] **Step 1: Create config/resources.conf**

```bash
# Resource partitioning for local job management
# Edit these absolute values when scaling the machine
#
# CPUQuota: 100% = 1 core (200% = 2 cores, 2000% = 20 cores)
# Memory: systemd suffixes G, M

# Experiments: ML training, data processing, heavy compute
EXPERIMENTS_CPU_QUOTA=200%        # 2 cores (→ 2000% for 20 cores)
EXPERIMENTS_MEMORY_MAX=24G        # Hard cap — OOM-killed above this (→ 96G)
EXPERIMENTS_MEMORY_HIGH=20G       # Soft cap — triggers reclaim pressure (→ 80G)
EXPERIMENTS_PARALLEL=1            # Max concurrent experiment jobs (→ 2)

# Agents: Claude Code, Codex CLI, coding agents
AGENTS_CPU_QUOTA=200%             # 2 cores (→ 1200% for 12 cores)
AGENTS_MEMORY_MAX=8G              # Hard cap (→ 32G)
AGENTS_MEMORY_HIGH=6G             # Soft cap (→ 24G)
AGENTS_PARALLEL=3                 # Max concurrent agent jobs (→ 6)
```

- [ ] **Step 2: Commit**

```bash
git add config/resources.conf
git commit -m "feat: add resource partitioning config for local job management"
```

---

### Task 2: systemd Unit Files

**Files:**
- Create: `config/systemd-user/experiments.slice`
- Create: `config/systemd-user/agents.slice`
- Create: `config/systemd-user/pueued.service`

- [ ] **Step 1: Create config/systemd-user/ directory**

```bash
mkdir -p config/systemd-user
```

- [ ] **Step 2: Create experiments.slice**

```ini
[Unit]
Description=ML Experiments slice
Before=slices.target

[Slice]
# Values templated by deploy.sh from config/resources.conf
CPUQuota=200%
MemoryMax=24G
MemoryHigh=20G
ManagedOOMMemoryPressure=kill
```

- [ ] **Step 3: Create agents.slice**

```ini
[Unit]
Description=Coding Agents slice (Claude Code, Codex CLI)
Before=slices.target

[Slice]
CPUQuota=200%
MemoryMax=8G
MemoryHigh=6G
ManagedOOMMemoryPressure=kill
```

- [ ] **Step 4: Create pueued.service**

```ini
[Unit]
Description=Pueue Daemon

[Service]
ExecStart=%h/.cargo/bin/pueued --verbose
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
```

- [ ] **Step 5: Commit**

```bash
git add config/systemd-user/
git commit -m "feat: add systemd user slices and pueued service"
```

---

### Task 3: Pueue Config

**Files:**
- Create: `config/pueue.yml`

- [ ] **Step 1: Create config/pueue.yml**

```yaml
# Pueue daemon configuration
# Groups are created at runtime by deploy.sh (persist in Pueue state)
shared:
  use_unix_socket: true
  host: "127.0.0.1"
  port: "6924"

daemon:
  default_parallel_tasks: 1
  pause_group_on_failure: false
  pause_all_on_failure: false
  callback: ""
  callback_log_lines: 15
```

- [ ] **Step 2: Commit**

```bash
git add config/pueue.yml
git commit -m "feat: add pueue daemon config"
```

---

### Task 4: Install Pueue

**Files:**
- Modify: `config.sh` (~line 31)
- Modify: `install.sh`

- [ ] **Step 1: Add feature flags to config.sh**

Add after `INSTALL_EXTRAS=false`:

```bash
INSTALL_PUEUE=true               # Pueue job scheduler (Linux only)
```

And after `DEPLOY_SHELL=true`:

```bash
DEPLOY_PUEUE=true                # Pueue + systemd slices for resource management
```

- [ ] **Step 2: Add install block to install.sh**

Find the section that installs cargo/rust tools and add:

```bash
# Pueue (local job scheduler + daemon) — separate crates
if [[ "$INSTALL_PUEUE" == "true" ]] && is_linux; then
  if ! cmd_exists pueue; then
    log_info "Installing pueue + pueued..."
    if cmd_exists cargo; then
      cargo install pueue pueued --quiet
    else
      log_warning "cargo not found — install Rust first, then: cargo install pueue pueued"
    fi
  else
    log_info "pueue already installed ($(pueue --version 2>/dev/null || echo 'unknown'))"
  fi
fi
```

- [ ] **Step 3: Verify install.sh parses cleanly**

Run: `bash -n install.sh`
Expected: no output (clean parse)

- [ ] **Step 4: Commit**

```bash
git add config.sh install.sh
git commit -m "feat: add pueue + pueued installation"
```

---

### Task 5: Deploy Function

**Files:**
- Modify: `deploy.sh` (add deployment block before scheduled tasks section, ~line 815)

- [ ] **Step 1: Add pueue + systemd deployment block**

```bash
# Pueue + systemd resource management (Linux only)
if [[ "$DEPLOY_PUEUE" == "true" ]] && is_linux; then
  log_section "PUEUE + RESOURCE MANAGEMENT"

  # Verify systemd --user works
  if ! systemctl --user status &>/dev/null; then
    log_warning "systemd --user not available — skipping resource management"
    log_info "  Try: loginctl enable-linger $(whoami)"
  else
    # Source resource config
    local resources_conf="$DOT_DIR/config/resources.conf"
    if [[ -f "$resources_conf" ]]; then
      source "$resources_conf"
    else
      log_warning "config/resources.conf not found — using defaults"
      EXPERIMENTS_CPU_QUOTA=200%; EXPERIMENTS_MEMORY_MAX=24G; EXPERIMENTS_MEMORY_HIGH=20G; EXPERIMENTS_PARALLEL=1
      AGENTS_CPU_QUOTA=200%; AGENTS_MEMORY_MAX=8G; AGENTS_MEMORY_HIGH=6G; AGENTS_PARALLEL=3
    fi

    # Deploy systemd user units
    local systemd_user_dir="$HOME/.config/systemd/user"
    mkdir -p "$systemd_user_dir"

    # Template slice files with values from resources.conf
    for slice in experiments agents; do
      local src="$DOT_DIR/config/systemd-user/${slice}.slice"
      local dst="$systemd_user_dir/${slice}.slice"
      if [[ -f "$src" ]]; then
        local cpu_var="${slice^^}_CPU_QUOTA"
        local mem_max_var="${slice^^}_MEMORY_MAX"
        local mem_high_var="${slice^^}_MEMORY_HIGH"
        sed -e "s|CPUQuota=.*|CPUQuota=${!cpu_var}|" \
            -e "s|MemoryMax=.*|MemoryMax=${!mem_max_var}|" \
            -e "s|MemoryHigh=.*|MemoryHigh=${!mem_high_var}|" \
            "$src" > "$dst"
        log_info "Deployed ${slice}.slice (CPU=${!cpu_var}, Mem=${!mem_max_var})"
      fi
    done

    # Deploy pueued service
    local pueued_src="$DOT_DIR/config/systemd-user/pueued.service"
    [[ -f "$pueued_src" ]] && cp "$pueued_src" "$systemd_user_dir/pueued.service"

    systemctl --user daemon-reload
    log_success "systemd user units deployed"

    # Check cgroup delegation
    local uid; uid=$(id -u)
    local user_cgroup="/sys/fs/cgroup/user.slice/user-${uid}.slice"
    if [[ -f "$user_cgroup/cgroup.subtree_control" ]]; then
      local controls; controls=$(< "$user_cgroup/cgroup.subtree_control")
      if [[ "$controls" != *"memory"* ]] || [[ "$controls" != *"cpu"* ]]; then
        log_warning "cgroup delegation incomplete: $controls"
        log_info "Run once: sudo systemctl set-property user-${uid}.slice Delegate=yes && sudo systemctl daemon-reload"
      else
        log_success "cgroup delegation OK: $controls"
      fi
    fi

    # Deploy Pueue config and create groups
    if cmd_exists pueue; then
      local pueue_config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/pueue"
      mkdir -p "$pueue_config_dir"
      cp "$DOT_DIR/config/pueue.yml" "$pueue_config_dir/pueue.yml"

      # Enable and start pueued via systemd (with startup wait)
      systemctl --user enable pueued.service 2>/dev/null
      systemctl --user start pueued.service 2>/dev/null || {
        log_info "systemd start failed, falling back to direct pueued..."
        pueued --daemonize 2>/dev/null
      }

      # Wait for pueued to be ready (race fix: group creation needs running daemon)
      local retries=0
      while ! pueue status &>/dev/null && (( retries < 10 )); do
        sleep 0.5
        retries=$((retries + 1))
      done

      if pueue status &>/dev/null; then
        # Create groups (idempotent — errors if exists, that's fine)
        pueue group add experiments 2>/dev/null
        pueue group add agents 2>/dev/null
        pueue parallel "$EXPERIMENTS_PARALLEL" --group experiments
        pueue parallel "$AGENTS_PARALLEL" --group agents
        log_success "Pueue groups: experiments(${EXPERIMENTS_PARALLEL}), agents(${AGENTS_PARALLEL})"
      else
        log_warning "pueued failed to start — groups not configured"
      fi

      # Enable linger (services persist after logout)
      loginctl enable-linger "$(whoami)" 2>/dev/null
    else
      log_warning "pueue not installed — run: ./install.sh --pueue"
    fi
  fi
fi
```

- [ ] **Step 2: Add --pueue flag parsing**

In the `while` loop that parses flags, add:

```bash
--pueue) DEPLOY_PUEUE=true ;;
--no-pueue) DEPLOY_PUEUE=false ;;
```

- [ ] **Step 3: Update help text**

```
  --pueue           Deploy Pueue + systemd resource management (Linux)
```

- [ ] **Step 4: Verify**

Run: `bash -n deploy.sh`
Expected: clean parse

- [ ] **Step 5: Commit**

```bash
git add deploy.sh
git commit -m "feat: add pueue + systemd slice deployment to deploy.sh"
```

---

### Task 6: Shell Aliases and Wrappers

**Files:**
- Modify: `config/aliases.sh` (insert after Slurm section, ~line 840)

- [ ] **Step 1: Add j* aliases section**

Insert after line 839 (`}` closing `qrun`), before the `AI CLI Tools` section:

```bash
# -------------------------------------------------------------------
# Pueue (local job queue + resource slices)
# -------------------------------------------------------------------
# j* prefix to avoid collision with q* (SLURM)
if command -v pueue &>/dev/null; then

  # Submit job to a group with systemd cgroup enforcement
  # Usage: jrun <group> <cmd...>
  jrun() {
    local group="${1:?Usage: jrun <group> <cmd...> (groups: experiments, agents)}"
    shift
    if [[ "$group" != "experiments" && "$group" != "agents" ]]; then
      echo "Unknown group: $group (expected: experiments, agents)" >&2; return 1
    fi
    if ! pueue status &>/dev/null; then
      echo "pueued not running. Start with: systemctl --user start pueued" >&2; return 1
    fi
    if ! systemctl --user status &>/dev/null; then
      echo "ERROR: systemd --user not available — cannot enforce resource limits" >&2
      echo "  Jobs would run without CPU/memory caps. Aborting." >&2
      echo "  Fix: loginctl enable-linger $(whoami)" >&2
      return 1
    fi
    pueue add --group "$group" --label "$(basename "$1")" -- \
      systemd-run --user --scope --slice="${group}.slice" -- "$@"
  }

  # Shortcuts
  jexp() { jrun experiments "$@"; }
  jagent() { jrun agents "$@"; }
  jclaude() { jrun agents claude --print "$@"; }

  # Status
  alias jls='pueue status'
  alias jlog='pueue log'
  alias jfollow='pueue follow'
  alias jclean='pueue clean'
  alias jwatch='watch -n2 pueue status'

  # Control
  jpause() {
    local group="${1:?Usage: jpause <group|all>}"
    [[ "$group" == "all" ]] && pueue pause || pueue pause --group "$group"
  }
  jresume() {
    local group="${1:?Usage: jresume <group|all>}"
    [[ "$group" == "all" ]] && pueue start || pueue start --group "$group"
  }
  alias jkill='pueue kill'

  # Overview with resource usage
  jtop() {
    pueue status
    echo ""
    systemctl --user status experiments.slice agents.slice 2>/dev/null \
      || echo "(systemd slices not available)"
  }

fi
```

- [ ] **Step 2: Verify**

Run: `zsh -n config/aliases.sh`
Expected: clean parse

- [ ] **Step 3: Commit**

```bash
git add config/aliases.sh
git commit -m "feat: add j* aliases for pueue local job management"
```

---

### Task 7: Memory Pressure Monitor

**Files:**
- Create: `custom_bins/jguard`

- [ ] **Step 1: Create custom_bins/jguard**

```bash
#!/usr/bin/env bash
set -euo pipefail
# jguard — check memory pressure (PSI) for resource-managed workloads
# Usage: jguard [--threshold N] [--watch]

THRESHOLD="${2:-50}"
PSI="/proc/pressure/memory"
[[ -f "$PSI" ]] || { echo "PSI not available"; exit 1; }

check() {
  local avg10
  avg10=$(awk '/^some/{for(i=1;i<=NF;i++) if($i ~ /^avg10=/) print substr($i,7)}' "$PSI")
  local int="${avg10%%.*}"
  if (( int >= THRESHOLD )); then
    echo "⚠ Memory pressure: avg10=${avg10}% (threshold: ${THRESHOLD}%)" >&2
    command -v pueue &>/dev/null && pueue status 2>/dev/null
    return 1
  fi
  echo "✓ Memory pressure: avg10=${avg10}%"
}

case "${1:-}" in
  --watch) while true; do clear; check || true; sleep 10; done ;;
  --threshold) check ;;
  -h|--help) echo "Usage: jguard [--watch] [--threshold N]" ;;
  *) check ;;
esac
```

- [ ] **Step 2: Make executable**

```bash
chmod +x custom_bins/jguard
```

- [ ] **Step 3: Commit**

```bash
git add custom_bins/jguard
git commit -m "feat: add jguard memory pressure monitor"
```

---

### Task 8: Claude Code Skill

**Files:**
- Create: `claude/skills/jobs/SKILL.md`

- [ ] **Step 1: Create claude/skills/jobs/SKILL.md**

```markdown
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
```

- [ ] **Step 2: Commit**

```bash
git add claude/skills/jobs/
git commit -m "feat: add /jobs skill for Claude Code job management"
```

---

### Task 9: Integration Test

All tests from normal shell (not Claude Code sandbox).

- [ ] **Step 1: Verify systemd user session**

```bash
systemctl --user status
```

Expected: active user manager

- [ ] **Step 2: Verify pueue daemon**

```bash
systemctl --user status pueued
```

Expected: active (running)

- [ ] **Step 3: Test experiment submission**

```bash
jexp sleep 10
jls
```

Expected: job running in "experiments" group

- [ ] **Step 4: Verify cgroup enforcement**

```bash
jexp -- bash -c 'cat /proc/self/cgroup'
sleep 2 && jlog
```

Expected: cgroup path containing `experiments.slice`

- [ ] **Step 5: Test memory limit (OOM kill)**

```bash
jexp -- python3 -c "x = bytearray(30 * 1024**3)"
sleep 5 && jlog
```

Expected: killed/failed (30GB exceeds 24G MemoryMax)

- [ ] **Step 6: Test agent queue depth**

```bash
for i in 1 2 3 4; do jagent sleep 30; done
jls
```

Expected: 3 running, 1 queued in "agents" group

- [ ] **Step 7: Test jguard**

```bash
jguard
```

Expected: PSI pressure reading

- [ ] **Step 8: Test skill**

In Claude Code, type `/jobs`. Expected: skill loads with command reference.

---

## Scaling Notes

When upgrading to 32 cores / 128GB, edit `config/resources.conf`:

```bash
EXPERIMENTS_CPU_QUOTA=2000%       # 20 cores
EXPERIMENTS_MEMORY_MAX=96G
EXPERIMENTS_MEMORY_HIGH=80G
EXPERIMENTS_PARALLEL=2

AGENTS_CPU_QUOTA=1200%            # 12 cores
AGENTS_MEMORY_MAX=32G
AGENTS_MEMORY_HIGH=24G
AGENTS_PARALLEL=6
```

Then: `./deploy.sh --pueue`
