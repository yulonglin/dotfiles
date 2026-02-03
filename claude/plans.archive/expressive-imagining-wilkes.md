# Memory Optimization Plan for Experiment Sweeps

## Problem Summary

Running multiple experiment configs in parallel (GPQA/MATH × LD/TM/C3/BP) via Hydra `--multirun` caused memory exhaustion:
- 20 parallel Python processes × 2-5GB each = 40-100GB
- Container had 128GB limit (hidden by `free -h` showing host's 282GB)
- Result: OOM, SSH unresponsive, experiments killed without output

**Root causes:**
1. Hydra spawns separate processes for each config
2. Each process duplicates: datasets, in-memory caches, model objects
3. No memory limits on parallelism

---

## Recommended Changes

### 1. CLAUDE.md: Add Critical Warning (Immediate)

Add to Critical Warnings section:

```markdown
> **⚠️ Parallel sweeps and memory**: Running multiple configs via `--multirun` spawns separate Python processes. Each process uses 2-5GB RAM. With 20 configs = 40-100GB. **Check container memory before large sweeps:**
> ```bash
> # Container limit (the REAL limit - free -h lies in containers)
> cat /sys/fs/cgroup/memory/memory.limit_in_bytes | awk '{printf "%.0fGB\n", $1/1024^3}'
> cat /sys/fs/cgroup/memory/memory.usage_in_bytes | awk '{printf "%.0fGB\n", $1/1024^3}'
> ```
> **For large sweeps:** Run configs sequentially, use batch mode, or limit parallelism.
```

**File:** `CLAUDE.md`, after the batch mode warning

### 2. CLAUDE.md: Add Performance Tuning Section (Immediate)

Expand the existing "Performance Tuning" section:

```markdown
### Memory-Safe Sweep Strategies

| Sweep Size | Strategy | Command |
|------------|----------|---------|
| 1-4 configs | Direct multirun OK | `--multirun` |
| 5-10 configs | Limit parallelism | `hydra.launcher.n_jobs=4` |
| 10+ configs | Sequential batches | Run in 2-3 batches |
| Large + batch API | Single orchestrator | Submit all, retrieve later |

**Sequential execution** (safest for large sweeps):
```bash
# Run configs one at a time
for config in math-c3 math-ld math-tm math-bp; do
  python -m src.detection_game.cli.run_sweep --config-name=$config
done
```
```

**File:** `CLAUDE.md`, Performance Tuning section

### 3. Config: Add Hydra Launcher Limits (Immediate)

Create a joblib launcher config that limits parallelism:

```yaml
# src/detection_game/configs/hydra/launcher/memory_safe.yaml
defaults:
  - joblib

n_jobs: 4  # Max 4 parallel processes
prefer: processes
```

Usage: `hydra/launcher=memory_safe`

**File:** New file `src/detection_game/configs/hydra/launcher/memory_safe.yaml`

### 4. Code: Add Memory Pre-flight Check (Short-term)

Add to `run_sweep.py` at the start of `run_sweep()`:

```python
def check_memory_headroom(required_gb: float = 10.0) -> bool:
    """Warn if insufficient memory available in container."""
    try:
        limit_path = Path("/sys/fs/cgroup/memory/memory.limit_in_bytes")
        usage_path = Path("/sys/fs/cgroup/memory/memory.usage_in_bytes")

        if limit_path.exists():
            limit_gb = int(limit_path.read_text()) / 1024**3
            used_gb = int(usage_path.read_text()) / 1024**3
            available_gb = limit_gb - used_gb

            if available_gb < required_gb:
                logger.warning(
                    f"⚠️ LOW MEMORY: {available_gb:.1f}GB available, "
                    f"{required_gb:.1f}GB recommended. "
                    f"Container limit: {limit_gb:.0f}GB. "
                    f"Consider: sequential execution or hydra.launcher.n_jobs=4"
                )
                return False
    except Exception:
        pass  # Not in container or cgroup v1
    return True
```

**File:** `src/detection_game/cli/run_sweep.py`

### 5. Global CLAUDE.md: Add Container Memory Check (Immediate)

Add to "Shell Commands" or create new "Container Environment" section:

```markdown
### Container Memory Check

**CRITICAL**: `free -h` lies in containers (shows host memory, not cgroup limit).

```bash
# Check actual container limits
if [[ -f /sys/fs/cgroup/memory/memory.limit_in_bytes ]]; then
    echo "Container limit: $(awk '{printf "%.0fGB", $1/1024^3}' /sys/fs/cgroup/memory/memory.limit_in_bytes)"
    echo "Current usage: $(awk '{printf "%.0fGB", $1/1024^3}' /sys/fs/cgroup/memory/memory.usage_in_bytes)"
else
    free -h | head -2
fi
```
```

**File:** `~/.claude/CLAUDE.md` (global)

---

## Files to Modify

| File | Change Type | Priority |
|------|-------------|----------|
| `CLAUDE.md` | Add warning + sweep strategies | Immediate |
| `~/.claude/CLAUDE.md` | Add container memory check | Immediate |
| `src/detection_game/configs/hydra/launcher/memory_safe.yaml` | New file | Immediate |
| `src/detection_game/cli/run_sweep.py` | Add memory check function | Short-term |

---

## Verification

After implementation:

1. **Test memory check**:
   ```bash
   python -c "from src.detection_game.cli.run_sweep import check_memory_headroom; print(check_memory_headroom())"
   ```

2. **Test limited parallelism**:
   ```bash
   python -m src.detection_game.cli.run_sweep \
     --config-name=math-paraphrase \
     hydra/launcher=memory_safe \
     trajectory.eval.limit=5 \
     --multirun
   ```

3. **Monitor during sweep**:
   ```bash
   watch -n 5 'ps aux | grep python | wc -l; cat /sys/fs/cgroup/memory/memory.usage_in_bytes | awk "{printf \"%.1fGB\n\", \$1/1024^3}"'
   ```

---

## Out of Scope (Future Work)

These are documented in `~/.claude/ai_docs/experiment-memory-optimization.md` but deferred:
- Replace in-memory cache with shared disk/Redis cache
- Single orchestrator pattern for batch submission
- Memory monitoring daemon
