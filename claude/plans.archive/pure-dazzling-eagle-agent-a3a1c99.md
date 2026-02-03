# Plan Critique: Fire-and-Forget Batch Experiment Orchestrator

## Executive Summary

**Overall Assessment**: The plan is reasonable but may be over-engineering the solution. There is a **simpler alternative** that could solve the core memory problem with far less code.

---

## Critique Summary

### 1. Simpler Alternative Exists

**The core problem is NOT batch APIs. It's Hydra `--multirun` spawning 20+ parallel Python processes.**

**Simpler solution**: Run experiments **sequentially in a single process** instead of parallel via `--multirun`:

```bash
# Instead of: python -m ... --multirun (spawns 20 processes)
# Do this:
for config in math-c3 math-ld math-tm; do
  python -m src.detection_game.cli.run_sweep --config-name=$config
done
```

**Memory**: 5GB (single process) vs 100GB (20 processes).
**Latency**: Slower total runtime, but Inspect AI's native batch mode still gets 50% cost savings.
**LOC**: 0 (just a shell loop or Python script calling `run_sweep` sequentially).

**Why this works**: Inspect AI already has native batch API support (`batch=True` or `batch=N`). The plan's `submit_batches.py` would be reimplementing what Inspect already does.

**Recommendation**: Try sequential execution with `batch=True` before building custom infrastructure.

---

### 2. Hybrid Cache Approach: Hidden Gotchas

The plan proposes:
> "Download batch results, save to Inspect's cache format, run Inspect with cache enabled"

**Critical issues**:

1. **Cache key matching is fragile**: Inspect's cache key includes:
   - `config.model_dump()` (all generate config fields)
   - All `ChatMessage` objects including IDs
   - `base_url`, `tools`, `tool_choice`
   - `epoch` context variable
   - `policy.scopes`

   You must reconstruct the **exact same cache key** as Inspect would compute. Any mismatch = cache miss.

2. **Epoch context variable**: Inspect uses `epoch: ContextVar[int]` to differentiate cache entries per epoch. You must set this correctly when populating cache.

3. **Message IDs**: `ChatMessage` objects have IDs that are excluded from cache key, but the rest must match exactly.

4. **Serialization format**: Inspect stores `(expiry_datetime, ModelOutput)` tuples in its cache. You must serialize correctly using the same format.

**Verdict**: Not "simpler" - you're reimplementing Inspect's internal caching contract which can break on Inspect upgrades.

**Alternative**: Use Inspect's actual invocation with `batch=True` and let it handle everything natively.

---

### 3. Staged Batching for Multi-Turn: Practical Concerns

**Lie Detector = 49 batches** (1 initial + 48 follow-ups)

**Problems**:

1. **Poll latency compounds**: Each stage waits for batch completion (~2-10 min per batch). 49 stages = 1.5-8 hours just in polling overhead, even if API processing is fast.

2. **Error recovery is complex**: If stage 23 fails, you need:
   - Manifest tracking of partial progress
   - Logic to resume from stage 23
   - Logic to handle partially-completed batches

3. **State management explosion**: You're maintaining:
   - `sample_id -> previous_response` for all 1000+ samples
   - Stage-to-batch-id mapping
   - Per-sample error state

4. **OpenAI batch size limits**: 50,000 requests per batch, 200MB file size. For 1000 samples with 48 follow-ups, you're fine, but edge cases exist.

**Verdict**: 49 batches is **not fire-and-forget** - it requires persistent orchestration. The `nohup` polling script must run for hours.

**Alternative for Lie Detector**: Consider if real-time async execution with aggressive caching is actually simpler. 48 API calls per sample * 1000 samples = 48,000 calls, which completes in ~10-20 min with 100 concurrent connections.

---

### 4. Biggest Implementation Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| Cache key mismatch with Inspect | **HIGH** | Don't do hybrid cache; use Inspect's native batch |
| State corruption in multi-stage batches | **MEDIUM** | Idempotent manifest design, checksums |
| Batch API quota exhaustion (50k/batch) | **LOW** | Split into multiple batches |
| OpenAI batch timeouts (24h window) | **MEDIUM** | Stage timeout handling |
| Inspect upgrade breaks internals | **HIGH** | Don't depend on Inspect internals |

---

### 5. Critical Files/Patterns to Leverage

**Already exists - use instead of rebuilding**:

| File | What it provides |
|------|------------------|
| `src/detection_game/utils/batch_config.py` | Batch config parsing, `get_batch_param_for_inspect()` |
| Inspect's `_cache.py` | Cache key generation (but don't depend on internals) |
| Inspect's `_openai_batch.py` | Native OpenAI batch implementation |
| `run_sweep.py` `_build_models`, `_build_tasks` | Model/task construction (can reuse) |

**Pattern to follow**: The codebase already passes `batch=True` to Inspect's run function. This triggers Inspect's native batch mode which handles everything.

---

## Recommended Alternative Approach

**Phase 0: Validate if custom infrastructure is needed (1 day)**

```bash
# Test sequential execution with Inspect's native batch
for config in math-c3 math-ld math-tm; do
  python -m src.detection_game.cli.run_sweep \
    --config-name=$config \
    batch.enabled=true \
    trajectory.limit=100
done
```

If this works (uses 5GB RAM, completes overnight), you don't need custom batch infrastructure.

**If Phase 0 fails, then consider:**

1. **Sequential config runner** (~50 LOC): Simple Python script that runs configs one at a time
2. **SLURM job array**: Submit each config as a separate SLURM job (true fire-and-forget)
3. **Only then**: Custom batch orchestration for edge cases

---

## Answers to Your Specific Questions

### Q1: Are there simpler alternatives?

**Yes**. Sequential execution in a single process solves the memory problem. Inspect's native batch mode handles API batching.

### Q2: Is hybrid cache approach simpler?

**No**. It couples you to Inspect's internal cache format which is complex (serialized tuples with epoch context variables, exact message matching). Any Inspect upgrade could break it.

### Q3: Biggest implementation risks?

1. Cache key mismatch causing 100% cache misses
2. State management complexity for 49-stage Lie Detector
3. Dependency on Inspect internals that may change

### Q4: Is 49 batches practical?

**Marginally**. It works but isn't truly "fire-and-forget" - you need a persistent polling process running for hours. Consider if async real-time execution with caching is simpler for Lie Detector specifically.

### Q5: Critical files/patterns to leverage?

- Use `get_batch_param_for_inspect()` from `batch_config.py`
- Reuse `_build_models`, `_build_tasks` from `run_sweep.py`
- **Don't** try to populate Inspect's cache manually - use Inspect's native mechanisms

---

## Final Recommendation

**Start with the simplest solution that could work:**

1. Write a 30-line bash script or Python wrapper that runs configs sequentially
2. Use `batch.enabled=true` to get Inspect's native batch API support
3. Use tmux/SLURM for fire-and-forget execution

Only build custom infrastructure if you discover concrete limitations with this approach.

**Estimated effort if this works**: 1 day instead of 4-5 days.
