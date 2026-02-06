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

## Memory Management

Prefer async over multiprocessing for API experiments (processes duplicate memory).

| Approach | Memory | Use when |
|----------|--------|----------|
| **Async (single process)** | 1x | API experiments, I/O-bound work |
| **Threads** | 1x (shared) | I/O-bound, need shared state |
| **Processes** | Nx (duplicated) | CPU-bound only (NumPy, sklearn) |

**Rule of thumb**: Stay under 80% of available memory. For containers, check cgroup limit, not `free -h`.

## References

- Primary: [latteries caller.py](https://raw.githubusercontent.com/thejaminator/latteries/refs/heads/main/latteries/caller.py)
- Alternatives: LiteLLM, safety-research/safety-tooling
