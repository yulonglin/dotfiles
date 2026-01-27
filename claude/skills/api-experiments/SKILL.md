---
name: api-experiments
description: Use when running API-heavy experiments (LLM evals, batch processing). Covers memory-efficient patterns, batch APIs vs async, and avoiding the parallel process anti-pattern.
---

# API Experiment Patterns

Guidance for running API-heavy experiments efficiently without exhausting memory.

> **For implementation work**: See `~/.claude/ai_docs/experiment-memory-optimization.md` for full spec with incident report, architecture diagrams, code examples, and migration path.

## The Anti-Pattern (Don't Do This)

```
20 parallel Python processes → each caches API responses in memory
20 × 5GB = 100GB → hits container limit → SSH dies → experiments killed
```

**Why it happens**: Hydra `--multirun` or manual parallel launches spawn separate processes. Each process:
- Loads the dataset independently (duplicated N×)
- Has its own in-memory response cache (duplicated N×)
- Loads model/tokenizer objects (duplicated N×)

**The irony**: Batch APIs are designed to be memory-efficient (fire-and-forget), but per-process caching defeats this.

## The Correct Pattern

### For Batch APIs (Preferred for Large Runs)

Batch APIs handle parallelism server-side. You need **one process** to:
1. Submit all batches
2. Poll for completion
3. Retrieve results

```python
async def run_all_experiments(configs: list[Config]):
    """Single process submits all batches."""
    batch_ids = []

    # Submit all (fast, no waiting)
    for config in configs:
        batch_id = await submit_batch(config)
        batch_ids.append((config.name, batch_id))
        print(f"Submitted {config.name}: {batch_id}")

    # Poll and retrieve (can disconnect and come back)
    results = {}
    for name, batch_id in batch_ids:
        result = await poll_until_complete(batch_id)
        results[name] = result
        save_results(name, result)  # Incremental save

    return results
```

**Memory**: ~5GB total regardless of number of configs.

### For Real-Time Async (Interactive Work)

Use `asyncio` with semaphore for rate limiting:

```python
async def run_async_experiment(samples: list, concurrency: int = 100):
    """Single process, many concurrent API calls."""
    semaphore = asyncio.Semaphore(concurrency)

    async def call_with_limit(sample):
        async with semaphore:
            return await api_call(sample)

    results = await asyncio.gather(*[call_with_limit(s) for s in samples])
    return results
```

**Memory**: ~5GB total for thousands of concurrent calls.

## When to Use What

| Scenario | Approach | Why |
|----------|----------|-----|
| Large eval (>1000 samples) | **Batch API** | 50% cheaper, fire-and-forget |
| Interactive iteration | **Real-time async** | Fast feedback loop |
| Multiple configs to sweep | **Sequential batch submission** | One process submits all |
| CPU-heavy post-processing | **Multiprocessing** | Actually needs parallelism |

## Memory Check Before Running

Always check available memory, especially in containers:

```bash
# Container limit (the REAL limit - free -h lies)
if [[ -f /sys/fs/cgroup/memory/memory.limit_in_bytes ]]; then
    LIMIT=$(awk '{printf "%.0f", $1/1024/1024/1024}' /sys/fs/cgroup/memory/memory.limit_in_bytes)
    USED=$(awk '{printf "%.0f", $1/1024/1024/1024}' /sys/fs/cgroup/memory/memory.usage_in_bytes)
    echo "Container: ${USED}GB / ${LIMIT}GB (${LIMIT}GB is your REAL limit)"
fi
```

**Rule**: Stay under 80% of limit. If limit is 128GB, keep total under ~100GB.

## Refactoring Existing Code

If you have code that spawns parallel processes for API work:

### Before (Bad)
```bash
# Spawns 10 processes, each with 5-10GB memory
for config in configs/*.yaml; do
    python run_experiment.py --config $config &
done
wait
```

### After (Good)
```python
# Single process, submits all configs
async def main():
    configs = load_all_configs("configs/*.yaml")

    # Submit all batches
    for config in configs:
        batch_id = await submit_batch(config)
        print(f"Submitted: {config.name} -> {batch_id}")

    # Results retrieved later or polled
```

## Signs You're Doing It Wrong

- **20+ Python processes** running simultaneously for API work
- **Load average >> CPU count** with low CPU% (processes blocked on memory)
- **SSH becomes unresponsive** (can't fork new connections)
- **`free -h` shows plenty of memory** but things are dying (check cgroup limit instead)

## Caching Strategy for Parallel Configs

If you must run multiple configs and want caching:

| Approach | Memory | Persistence |
|----------|--------|-------------|
| **Shared disk cache** (SQLite, JSONL) | 1× | Survives restarts |
| **Redis** | 1× (external) | Shared across processes |
| **Per-process in-memory** | N× (bad) | Lost on crash |

Prefer disk-based caching for experiment reproducibility anyway.

## Checklist

Before running API experiments at scale:

- [ ] Using batch API (not real-time) for large runs?
- [ ] Single process submitting all configs (not parallel processes)?
- [ ] Checked container memory limit (cgroup, not `free -h`)?
- [ ] Cache is shared (disk/Redis) not per-process in-memory?
- [ ] Estimated total memory: processes × per-process < 80% limit?

## References

- **Full implementation spec**: `~/.claude/ai_docs/experiment-memory-optimization.md` - incident report, architecture diagrams, code changes, migration path
- **Anthropic Batch API**: https://docs.anthropic.com/en/docs/build-with-claude/batch-processing
- **OpenAI Batch API**: https://platform.openai.com/docs/guides/batch
- **Inspect AI cache**: https://github.com/UKGovernmentBEIS/inspect_ai/blob/main/src/inspect_ai/model/_cache.py
