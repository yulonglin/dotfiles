# Async & Performance Patterns

## The Rule

**Parallelise API calls: ~100 concurrent calls.** Exponential backoff if things aren't working or seem slow. Track rate limit errors and retries needed.

## Batch APIs (Prefer for High Throughput)

| Provider | API | Benefits | Best For |
|----------|-----|----------|----------|
| Anthropic | [Message Batches](https://docs.anthropic.com/en/docs/build-with-claude/batch-processing) | 50% off, higher throughput, async | Large evals, bulk processing |
| OpenAI | [Batch API](https://platform.openai.com/docs/guides/batch) | 50% off, higher throughput, async | Embeddings, completions at scale |

**When to use batch APIs**: Large runs (>1000 calls) you can leave overnight, evaluation sweeps, bulk processing.
**When to use real-time async**: Interactive work, iterative development, small runs you're monitoring.

## Required Async Patterns

- `async def` + `await` for all API calls, file I/O, network operations
- `asyncio.Semaphore(100)` for rate limiting
- `asyncio.gather()` for parallel execution of independent tasks
- `tqdm.asyncio.tqdm.gather()` for progress tracking on async operations
- `tenacity` for retry logic (exponential backoff for rate limits, fixed wait for transient errors)

## Caching (Required)

References: [Inspect AI cache](https://github.com/UKGovernmentBEIS/inspect_ai/blob/main/src/inspect_ai/model/_cache.py), [latteries caller](https://github.com/thejaminator/latteries/blob/main/latteries/caller.py), [safety-tooling cache](https://github.com/safety-research/safety-tooling/blob/main/safetytooling/apis/inference/cache_manager.py)

- Keys: `hashlib.sha1(model.model_dump_json(exclude_none=True).encode()).hexdigest()`
- Storage: serialized files (Inspect AI), JSONL (latteries), JSON bins (safety-tooling)
- Concurrency: `anyio.Semaphore` (async) or `filelock.FileLock` (multi-process)
- Cache-aside pattern, validate before caching, provide `--clear-cache` option

## Best Practices & Anti-Patterns

Good: Streaming/incremental processing, progress bars with ETA, early validation (`--max-samples N`), checkpointing for resume capability.

Bad: Sequential API calls in loops, blocking I/O in async code, loading entire datasets into memory, no caching, concurrency < 50 for API calls, no progress bars, missing retry logic.

## Performance Decision Tree

```
Slow code? -> Profile first (scalene/py-spy)
|- I/O-bound (80%)? -> Async + caching (10-100x speedup)
|- CPU-bound (15%)? -> NumPy vectorize -> multiprocessing
\- GPU-bound (5%)?  -> Mixed precision -> DataLoader tuning
```

That tree covers compute, but memory-boundedness is a separate axis a workload can hit independently of (or on top of) compute — the sections below break out I/O-bound, CPU-bound, and memory-bound as three distinct questions, since a job can be CPU-bound *and* memory-bound at once and the right compute answer (multiprocessing) can be the wrong memory answer (Nx duplication -> OOM).

### I/O-bound (network calls, disk, subprocess wait)

Python's GIL releases during I/O waits, so asyncio, threads, and sequential batching all "work" here — the question is overhead and control granularity, not parallelism correctness.

| Approach | When |
|----------|------|
| **asyncio** (default) | Library is async-native (httpx, aiofiles, most modern SDKs). Cheapest per-task overhead (no OS thread), scales to thousands of concurrent tasks, best control via `Semaphore`. |
| **`ThreadPoolExecutor`** | Library is blocking/sync-only (older SDKs, `requests`, subprocess wrappers) and an async rewrite isn't worth it. Threads share memory (1x); GIL releases during I/O so this still parallelizes. Cap pool size (~20-50) — OS threads are heavier than asyncio tasks. |
| **Sequential** | <10 calls, one-off script, correctness over speed. |

### CPU-bound (tight Python loops, non-vectorized math, pure-Python parsing)

The GIL serializes pure-Python bytecode across threads, so threads give ~0 speedup here.

| Approach | When |
|----------|------|
| **Vectorize first** (NumPy/pandas/polars) | Almost always the right first move — replaces the Python loop with C, often 10-100x before touching parallelism at all. |
| **`ProcessPoolExecutor` / `multiprocessing`** | The loop genuinely can't vectorize (complex per-item logic). Each process gets its own GIL — real parallelism — at the cost of Nx memory (fork/copy per process) and IPC serialization overhead (pickling args/results). Only worth it when per-item work >> IPC cost. |
| **Threads** | Rarely useful for CPU-bound Python — skip, unless the hot loop is inside a C extension that releases the GIL (some NumPy ops, `re`, `hashlib`). |

### Memory-bound (large arrays/models/datasets, not enough RAM for Nx copies)

| Situation | Approach |
|-----------|----------|
| Large shared read-only data (embeddings, a loaded model) needed by every worker | `multiprocessing.shared_memory` or a memory-mapped file (`np.memmap`), not a naive `ProcessPoolExecutor` — avoids the Nx copy multiprocessing would otherwise force. |
| Dataset too big for one process's memory | Stream/chunk instead of loading fully (generator + `itertools.islice`, or a `DataLoader`-style iterator) — parallelism doesn't fix a dataset that doesn't fit; only chunking does. |
| Many concurrent I/O tasks each holding a large payload | Cap `asyncio.Semaphore` concurrency by memory budget, not just rate limit — 100 concurrent 50MB responses is 5GB resident regardless of how "async" it is. |
| GPU work | Mixed precision + gradient checkpointing before adding data-parallel workers — VRAM is the constraint, not thread count. |

**Rule of thumb**: default to **asyncio** for API/network work (cheapest, most controllable). Reach for **threads** only when the library forces blocking calls. Reach for **processes** only when you're CPU-bound *and* already vectorized *and* the per-item work justifies the memory/IPC cost — and check the memory-bound axis separately, since it can veto multiprocessing even when you're compute-bound. Stay under 80% of available memory; for containers, check the cgroup limit, not `free -h`.

| Approach | Memory | Use when |
|----------|--------|----------|
| **Async (single process)** | 1x | API experiments, I/O-bound work |
| **Threads** | 1x (shared) | I/O-bound with blocking libraries, need shared state |
| **Processes** | Nx (duplicated, unless using shared memory) | CPU-bound only, already vectorized (NumPy, sklearn) |

## References

- Primary: [latteries caller.py](https://raw.githubusercontent.com/thejaminator/latteries/refs/heads/main/latteries/caller.py)
- Alternatives: LiteLLM, safety-research/safety-tooling
