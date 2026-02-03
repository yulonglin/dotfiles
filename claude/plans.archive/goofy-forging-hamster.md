# Plan: Fix GPQA gpt-4.1-nano Prompt Selection Results

## Problem Summary

The FINAL report for GPQA gpt-4.1-nano shows **26 prompts** passing Stage 1, but current evaluation shows only **9 prompts** passing.

**Root cause**: The FINAL report was generated with `epochs=4` configuration, which was removed 3 hours later in commit a937419.

| Configuration | N Samples | Stage 1 Pass | Benign Accuracy |
|---------------|-----------|--------------|-----------------|
| **FINAL report** (epochs=4) | 79 × 4 = 316 | 26 prompts | ~67% |
| **Current** (no epochs) | 79 × 1 = 79 | 9 prompts | 36.7% |

## How `epochs` Worked

1. Passed to Inspect AI's evaluation function as `epochs=N` parameter
2. Ran each sample N times, bundling results in `.eval` file
3. Increased statistical power by 4× sample size
4. Tighter confidence intervals → more prompts meet ≥15pp threshold

## Options

### Option A: Re-add `epochs` support (Recommended)
**Effort**: ~30 min
**Files to modify**:
1. `src/detection_game/prompt_selection/runner.py` - Add epochs to PipelineConfig and evaluation calls
2. `src/detection_game/prompt_selection/cache.py` - Add epochs to cache key
3. `src/detection_game/cli/run_prompt_selection.py` - Extract epochs from Hydra config
4. `src/detection_game/configs/prompt_selection/gpqa.yaml` - Add `epochs: 4`

**Pros**: Reproducible, matches FINAL report methodology
**Cons**: Need to re-run pipeline with fresh evaluations

### Option B: Trust FINAL report as-is
**Effort**: None
**Action**: Use existing FINAL report results (26 prompts)

**Pros**: No work needed, results already exist
**Cons**: Can't reproduce, cache/eval files don't match report

### Option C: Use single-epoch results
**Effort**: None (already done)
**Action**: Accept 9 prompts passing

**Pros**: Reproducible, simpler methodology
**Cons**: Different from FINAL report, fewer prompts pass

## Recommendation

**Option A: Re-add `epochs` support**

This is the cleanest solution because:
1. Makes results reproducible
2. Matches the methodology used for the FINAL report
3. The implementation is well-understood (was working 3 hours before removal)
4. Provides higher statistical power for the small GPQA dataset (N=79)

## Implementation Plan (if Option A chosen)

### Step 1: Re-add epochs to runner.py
- Add `epochs: int = 1` to `PipelineConfig` dataclass
- Modify `_run_inspect_eval_subprocess()` to pass epochs to Inspect AI
- Update `_get_cached_measurement()` to include epochs in cache key

### Step 2: Re-add epochs to cache.py
- Add `epochs: int = 1` to `CachedMeasurement` dataclass
- Update `_get_cache_path()` to append `_eN` suffix when epochs > 1
- Update `get()` and `store()` to handle epochs parameter

### Step 3: Update CLI
- Add epochs extraction in `_config_from_hydra()`: `epochs=pipeline.get("epochs", 1)`

### Step 4: Update config
- Add to `gpqa.yaml`: `pipeline.epochs: 4`
- Update `n_samples_stage2` comment to reflect epochs

### Step 5: Re-run pipeline
```bash
python -m src.detection_game.cli.run_prompt_selection \
  --config-name=prompt_selection/gpqa \
  'pipeline.models=[openai/gpt-4.1-nano]' \
  execution.skip_cache=true
```

### Step 6: Regenerate docs
```bash
uv run python scripts/generate_prompt_selection_docs.py \
  --dataset gpqa --model gpt-4.1-nano \
  --output docs/prompt_selection/gpqa/gpt-4.1-nano.md
```

## Verification

1. Check that `epochs` parameter is passed to Inspect AI correctly
2. Verify `.eval` files contain 4× samples (316 instead of 79)
3. Compare results with FINAL report (should be similar, ~26 prompts passing Stage 1)
4. Ensure cache files use `_e4` suffix for epochs=4 runs
