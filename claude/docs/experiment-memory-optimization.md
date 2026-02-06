# Experiment Memory Optimization Spec

Spec for optimizing API-heavy experiment code to prevent memory exhaustion.

## Incident Report (2026-01-27)

### Symptoms
- SSH to RunPod container became unresponsive
- RunPod console showed "120GB/120GB" memory usage
- Experiments were running but couldn't connect to monitor them

### Diagnosis

**1. Load average showed extreme historical load:**
```
$ uptime
load average: 4.01, 42.77, 97.72
              1min  5min   15min
```
Load of 97 with low CPU = processes blocked on memory allocation, not computing.

**2. Container had hidden memory limit:**
```
$ cat /sys/fs/cgroup/memory/memory.limit_in_bytes
128000000000  # 128GB limit

$ free -h
              total        used        free
Mem:          282Gi        38Gi       140Gi  # LIES - shows host, not container limit
```
`free -h` showed 282GB total (host memory), but container was capped at 128GB via cgroup.

**3. Too many parallel processes:**
```
$ ps aux | grep python | grep -E 'run_sweep|run_judge' | wc -l
20
```
20 Python processes, each using 2-5GB = 40-100GB total.

**4. Per-process memory usage:**
```
$ ps aux | grep run_sweep | awk '{printf "RSS=%.1fGB\n", $6/1024/1024}'
RSS=2.5GB
RSS=4.3GB
RSS=5.0GB
...
```

**5. In-memory cache was duplicated per process:**
```python
# src/detection_game/utils/memory_cache.py
class InMemoryCache:
    _instance = None
    _cache: Dict[str, Tuple[datetime, bytes]] = {}  # Per-process singleton!
```
Python singletons don't share across processes - each gets its own cache.

**6. Experiments from the incident period had no output:**
```
$ ls /path/to/logs/runs/*20260127_22*
# All directories had 0 json files - killed before producing results
```

### Root Cause
Container hit 128GB cgroup limit → memory pressure → fork() failures → SSH couldn't spawn new connections → appeared "unresponsive" even though processes were technically running.

### Recovery
Processes eventually completed or were killed, freeing memory. New SSH connections then worked.

---

## Problem Statement

Running multiple experiment configs in parallel (via Hydra `--multirun` or manual parallel launches) causes memory exhaustion:

```
20 parallel Python processes × 5GB each = 100GB
Container limit: 128GB
Result: OOM, SSH unresponsive, experiments killed
```

**Root causes identified:**
1. Each process loads dataset independently (duplicated N×)
2. Each process has its own in-memory API response cache (duplicated N×)
3. Each process loads model/tokenizer objects (duplicated N×)

**The irony:** Batch APIs are designed to be memory-efficient, but per-process in-memory caching defeats this.

## Current Architecture (Problematic)

```
┌─────────────────────────────────────────────────────────┐
│                    Hydra --multirun                      │
└─────────────────────────────────────────────────────────┘
                           │
          ┌────────────────┼────────────────┐
          ▼                ▼                ▼
    ┌──────────┐     ┌──────────┐     ┌──────────┐
    │ Process 1│     │ Process 2│     │ Process N│
    │ - Dataset│     │ - Dataset│     │ - Dataset│  ← Duplicated N×
    │ - Cache  │     │ - Cache  │     │ - Cache  │  ← Duplicated N×
    │ - Models │     │ - Models │     │ - Models │  ← Duplicated N×
    └──────────┘     └──────────┘     └──────────┘
         │                │                │
         ▼                ▼                ▼
    ┌─────────────────────────────────────────┐
    │              Batch API                   │
    └─────────────────────────────────────────┘
```

## Target Architecture

```
┌─────────────────────────────────────────────────────────┐
│              Single Orchestrator Process                 │
│  - Loads dataset once                                    │
│  - Shared disk cache (SQLite/JSONL)                     │
│  - Submits all batch requests                           │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
    ┌─────────────────────────────────────────┐
    │              Batch API                   │
    │  (parallelism handled server-side)      │
    └─────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│              Results retrieved async                     │
│  - Poll for completion                                   │
│  - Save incrementally to disk                           │
└─────────────────────────────────────────────────────────┘
```

## Required Changes

### 1. Replace In-Memory Cache with Disk Cache

**Current:** `src/detection_game/utils/memory_cache.py` - per-process in-memory cache

**Target:** Shared disk-based cache that works across processes

Options (in order of preference):
1. **SQLite** - Single file, concurrent reads, atomic writes
2. **JSONL append** - Simple, human-readable, works with existing tooling
3. **Redis** - If already in infrastructure

**Implementation:**
```python
# Before: Per-process singleton (BAD)
class InMemoryCache:
    _cache: Dict[str, bytes] = {}  # Duplicated per process

# After: Shared disk cache (GOOD)
class DiskCache:
    def __init__(self, cache_dir: Path = Path(".cache/api_responses")):
        self.cache_dir = cache_dir
        self.cache_dir.mkdir(parents=True, exist_ok=True)

    def _key_to_path(self, key: str) -> Path:
        return self.cache_dir / f"{hashlib.sha256(key.encode()).hexdigest()[:16]}.json"

    def get(self, key: str) -> Optional[dict]:
        path = self._key_to_path(key)
        if path.exists():
            return json.loads(path.read_text())
        return None

    def set(self, key: str, value: dict):
        path = self._key_to_path(key)
        path.write_text(json.dumps(value))
```

### 2. Sequential Config Submission (Not Parallel Processes)

**Current:** Each config spawns a separate Python process

**Target:** Single process iterates through configs, submits batch requests

**Implementation options:**

**Option A: Modify CLI to accept multiple configs**
```python
# run_sweep.py
@hydra.main(...)
def main(cfg):
    if cfg.get("batch_mode"):
        # Submit and return immediately
        batch_id = submit_batch(cfg)
        save_batch_id(cfg.name, batch_id)
        return

    # Original synchronous behavior for single runs
    run_experiment(cfg)
```

**Option B: Wrapper script that submits all batches**
```python
# scripts/submit_all_batches.py
async def main():
    configs = discover_configs("configs/*.yaml")

    for config in configs:
        batch_id = await submit_batch(config)
        print(f"{config.name}: {batch_id}")

    # Save batch IDs for later retrieval
    save_batch_manifest(batch_ids)
```

**Option C: Use Hydra's joblib launcher with shared cache**
```yaml
# config.yaml
defaults:
  - override hydra/launcher: joblib

hydra:
  launcher:
    n_jobs: 4  # Limit parallelism
```
Combined with disk cache, this limits memory while allowing some parallelism.

### 3. Async Batch Submission and Retrieval

**For batch APIs:** No need for local parallelism - the API provider handles it.

```python
async def run_experiment_suite(configs: list[Config]):
    """Submit all, then retrieve all."""

    # Phase 1: Submit all batches (fast)
    batch_ids = {}
    for config in configs:
        batch_id = await client.batches.create(...)
        batch_ids[config.name] = batch_id
        log.info(f"Submitted {config.name}: {batch_id}")

    # Phase 2: Poll and retrieve (can be interrupted/resumed)
    for name, batch_id in batch_ids.items():
        result = await poll_until_complete(batch_id)
        save_result(name, result)
        log.info(f"Completed {name}")
```

### 4. Memory Monitoring

Add pre-flight memory check:

```python
def check_memory_headroom(required_gb: float = 10.0):
    """Warn if insufficient memory available."""
    try:
        # Container limit (the real constraint)
        limit_path = Path("/sys/fs/cgroup/memory/memory.limit_in_bytes")
        usage_path = Path("/sys/fs/cgroup/memory/memory.usage_in_bytes")

        if limit_path.exists():
            limit_gb = int(limit_path.read_text()) / 1024**3
            used_gb = int(usage_path.read_text()) / 1024**3
            available_gb = limit_gb - used_gb

            if available_gb < required_gb:
                log.warning(
                    f"Low memory: {available_gb:.1f}GB available, "
                    f"{required_gb:.1f}GB recommended. "
                    f"Container limit: {limit_gb:.0f}GB"
                )
                return False
    except Exception:
        pass  # Not in container, skip check

    return True
```

## Acceptance Criteria

1. **Memory usage**: Running 20 configs uses <10GB total (not 100GB)
2. **Cache sharing**: API responses cached once, readable by all configs
3. **Resumability**: Can interrupt and resume batch jobs
4. **No SSH issues**: System remains responsive during large runs

## Migration Path

1. **Phase 1**: Add disk cache alongside in-memory cache (feature flag)
2. **Phase 2**: Add sequential batch submission mode
3. **Phase 3**: Deprecate parallel process spawning for batch API work
4. **Phase 4**: Remove in-memory cache, disk cache is default

## Testing

```bash
# Before optimization
ps aux | grep python | wc -l  # Should show 20+ processes
free -h  # Shows high memory usage

# After optimization
ps aux | grep python | wc -l  # Should show 1-2 processes
free -h  # Shows low memory usage
```

## Files to Modify

| File | Change |
|------|--------|
| `src/.../utils/memory_cache.py` | Replace with disk cache |
| `src/.../cli/run_sweep.py` | Add batch submission mode |
| `configs/config.yaml` | Add batch_mode option |
| New: `scripts/submit_batches.py` | Orchestrator for batch submission |
| New: `scripts/retrieve_batches.py` | Retrieve completed batches |

## References

- Anthropic Batch API: https://docs.anthropic.com/en/docs/build-with-claude/batch-processing
- OpenAI Batch API: https://platform.openai.com/docs/guides/batch
- Inspect AI cache implementation: https://github.com/UKGovernmentBEIS/inspect_ai/blob/main/src/inspect_ai/model/_cache.py
