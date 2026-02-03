# Prompt Selection CI Computation - Summary & Plan

## What We're Trying To Do

Run the prompt selection pipeline for USACO with **gpt-4.1-nano** and **gpt-5-nano** to get **confidence intervals (CIs)** for the sandbagging gap. The pipeline filters prompts based on:
1. Refusal rate ≤10%
2. Sandbagging gap ≥10pp AND 95% CI excludes 0
3. Leakage rate ≤10%

## What Went Wrong

### Initial Run (with cache)
- Pipeline completed quickly using cached JSON measurement files
- **Problem**: Cached JSON files only had aggregate accuracy, no per-sample scores
- **Result**: CIs showed as "n/a" in the report

### Re-run with `skip_cache=true`
- Pipeline started running NEW Docker evaluations instead of reading existing .eval files
- USACO requires Docker sandboxes for code execution → very slow
- **Problem**: `skip_cache=true` bypasses ALL cache, including existing .eval files
- User correctly noted: "there are eval files" - we shouldn't need Docker

### Root Cause Discovery
The pipeline has two-level caching:
1. **Measurement cache** (`data/prompt_selection/{dataset}/measurements/*.json`) - JSON files with aggregate stats
2. **Eval cache** (`data/prompt_selection/{dataset}/evals/**/*.eval`) - Inspect AI evaluation logs with per-sample data

The pipeline flow:
```
Check JSON cache → if miss → Run NEW evaluation (ignores existing .eval files!)
```

The existing .eval files from Jan 22 have per-sample scores, but the pipeline doesn't use them as a fallback.

## What I Changed

### 1. Updated `scripts/regenerate_cache_from_evals.py`
- **Added per-sample score extraction** (was only extracting aggregate accuracy)
- **Added `verify_usaco` score key** for USACO dataset (was missing)
- **Added `reasoning_effort` to filename** for gpt-5-* models (cache key mismatch)

Key changes:
```python
# Before: Only returned (accuracy, n_samples)
def extract_accuracy_from_log(log_file: Path) -> tuple[float, int]:

# After: Returns (accuracy, n_samples, per_sample_scores)
def extract_accuracy_from_log(log_file: Path, dataset: str) -> tuple[float, int, list[float]]:
```

### 2. Archived Files
- `archive/prompt_selection_cache_20260124/` - 164 old JSON cache files
- `archive/incomplete_evals_20260124/` - 2 incomplete .eval files from aborted runs

## What We Learned

1. **Cache architecture matters**: The pipeline uses JSON cache as primary, .eval files only during fresh evaluation. No fallback to read existing .eval files when JSON cache is stale.

2. **Per-sample scores are essential for CIs**: Can't compute confidence intervals without individual sample scores. The original cache didn't store them.

3. **Reasoning models need special handling**: gpt-5-* models require `reasoning_effort` in the cache filename, otherwise cache lookup fails.

4. **Docker isn't always needed**: Existing .eval files contain all the data. The `regenerate_cache_from_evals.py` script can rebuild JSON cache from them.

## Current State (Updated)

✅ **Regeneration complete**:
- gpt-4.1-nano: 81 cache files with per-sample scores
- gpt-5-nano: 81 cache files with per-sample scores (with `_low_` suffix)
- All .eval files intact in `data/prompt_selection/usaco/evals/`

## Remaining Steps

1. **Run prompt selection pipeline** for both models (will read from regenerated cache):
   ```bash
   python -m src.detection_game.cli.run_prompt_selection \
     --config-name=prompt_selection/usaco 'pipeline.models=[openai/gpt-4.1-nano]'

   python -m src.detection_game.cli.run_prompt_selection \
     --config-name=prompt_selection/usaco 'pipeline.models=[openai/gpt-5-nano]'
   ```

2. **Verify CIs appear** in the report

## Verification

Check the final report for CI values:
```
| Prompt | Family | gpt-5-nano Gap | 95% CI | Status |
|--------|--------|----------------|--------|--------|
| ... | ... | 24.0pp | [X, Y] | ✅ Pass |  ← Should have actual CI, not "n/a"
```
