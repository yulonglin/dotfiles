# Plan: Add Dataset Sample Counts to CLAUDE.md

## Goal
Add explicit sample counts for all datasets to CLAUDE.md so experiments can verify completeness.

## Key Information Gathered

### Default Split Ratios (from base.yaml)
- Train: 20%
- Val: 20%
- Test: 60%
- Seed: 42 (deterministic)

### Dataset Sample Counts

**Note**: Run the script below to get exact counts after implementing the splitting fix.

| Dataset | Total | Train | Val | Test | Train+Val (for CV) |
|---------|-------|-------|-----|------|--------------------|
| **GPQA Diamond** | 198 | 39 | 40 | 119 | 79 |
| **MATH** (all levels) | [RUN SCRIPT] | - | - | - | - |
| **MATH** (level 5 only) | [RUN SCRIPT] | - | - | - | - |
| **USACO** | 307 | 61 | 61 | 185 | 122 |

### Script to Get Exact Counts

```python
# Run: uv run python tmp/count_dataset_samples.py
from datasets import load_dataset

# GPQA - already known: 198 total
print("GPQA Diamond: 198 samples (from CSV)")

# MATH - count from HuggingFace
subjects = ['algebra', 'counting_and_probability', 'geometry',
            'intermediate_algebra', 'number_theory', 'prealgebra', 'precalculus']

total_all = 0
total_level5 = 0
for subject in subjects:
    ds = load_dataset("EleutherAI/hendrycks_math", subject, split="train")
    total_all += len(ds)
    # Count level 5 only
    level5 = sum(1 for x in ds if x.get('level') == 'Level 5')
    total_level5 += level5

print(f"MATH (all levels): {total_all} samples")
print(f"MATH (level 5 only): {total_level5} samples")

# After custom splitting (20/20/60):
# With cumulative logic: train_end = int(n * 0.2), val_end = int(n * 0.4)
def compute_splits(n):
    train_end = int(n * 0.2)
    val_end = int(n * 0.4)
    return train_end, val_end - train_end, n - val_end, val_end

for name, n in [("GPQA", 198), ("MATH-all", total_all), ("MATH-L5", total_level5), ("USACO", 307)]:
    train, val, test, train_val = compute_splits(n)
    print(f"{name}: Total={n}, Train={train}, Val={val}, Test={test}, Train+Val={train_val}")
```

### CV Fold Size Analysis (3-fold)

| Dataset | Train+Val | Samples per 3-fold |
|---------|-----------|-------------------|
| GPQA | 79 | ~26 |
| USACO | 122 | ~41 |
| MATH | ~3,000 | ~1,000 |

**Recommendation**: 3-fold CV
- GPQA with 5-fold would have only ~16 samples per fold (high variance, statistically unreliable)
- 3-fold gives ~26 samples per fold minimum (small but workable)
- Standardizing on 3-fold ensures consistency across all datasets

## Proposed Changes to CLAUDE.md

### Location
Add new section after "## Cross-Validation and Multi-Sample Analysis" (around line 419-429)

### Content to Add (after getting exact counts)
```markdown
## Dataset Sample Counts

**Default split ratios** (from `configs/dataset/base.yaml`):
- Train: 20%, Val: 20%, Test: 60%
- Split seed: 42 (deterministic)

| Dataset | Total | Train | Val | Test | Train+Val |
|---------|-------|-------|-----|------|-----------|
| GPQA Diamond | 198 | 39 | 40 | 119 | 79 |
| MATH (all levels) | [EXACT] | [EXACT] | [EXACT] | [EXACT] | [EXACT] |
| MATH (level 5 only) | [EXACT] | [EXACT] | [EXACT] | [EXACT] | [EXACT] |
| USACO | 307 | 61 | 61 | 185 | 122 |

**MATH level selection**: Use [all levels / level 5 only] based on whether there's a
sufficient performance gap between sandbagging and normal models.

**Standard: 3-fold CV** on train+val combined.

| Dataset | Train+Val | Samples per 3-fold |
|---------|-----------|-------------------|
| GPQA | 79 | 26 |
| USACO | 122 | 40 |
| MATH | [EXACT] | [EXACT] |

**Validation checklist** (for complete runs):
- GPQA: Expect 79 samples (train+val) or 119 samples (test)
- USACO: Expect 122 samples (train+val) or 185 samples (test)
- MATH: Expect [EXACT] samples (train+val) or [EXACT] samples (test)
```

## Decision: 3-fold CV (Confirmed)

User confirmed standardizing on **3-fold CV**:
- GPQA with 79 samples → ~26 samples/fold (acceptable)
- Consistent across all datasets
- Avoids high-variance estimates from smaller folds

## Implementation Steps

### Step 0: Get exact counts
Run the script above to get exact MATH counts, then update the plan with concrete numbers.

```bash
uv run python tmp/count_dataset_samples.py
```

### Step 1: Run MATH baselines to determine difficulty level
Before deciding on MATH levels, run baselines to check model capabilities:

**Models to test**: gpt-4.1-nano, gpt-5-nano, claude-3.5-haiku, claude-4.5-haiku

**Level configurations**:
1. Level 5 only
2. Levels 4+5
3. All levels

**Purpose**: If strong models (5-nano, 4.5-haiku) already perform poorly on level 5,
there's no sandbagging gap to detect. Choose the level configuration where:
- Normal (non-sandbagging) models perform reasonably well (>50% accuracy)
- There's a detectable gap when those same models sandbag

```bash
# Example baseline run (limit 100 for testing)
python -m src.detection_game.cli.run_sweep \
  --config-name=math-paraphrase-benign \
  trajectory.eval.limit=100 \
  dataset.levels=[5]  # Try level 5 first, then [4,5], then []
```

### Step 2: Fix splitting logic
This affects all counts, so do it first.

## Files to Modify

### 1. CLAUDE.md - Add dataset sample counts section
Add documentation of sample counts and 3-fold CV standard.

### 2. Fix splitting logic (data_splitting.py)
Change from additive to cumulative boundaries to avoid losing samples:

```python
# Current (additive):
train_end = int(n * train_ratio)
val_end = train_end + int(n * val_ratio)  # Double truncation

# Fixed (cumulative):
train_end = int(n * train_ratio)
val_end = int(n * (train_ratio + val_ratio))  # Single truncation
```

File: `src/detection_game/utils/data_splitting.py` (lines 125-128)

### 3. Update hardcoded 5-fold defaults to 3-fold

| File | Line | Change |
|------|------|--------|
| `src/detection_game/classifiers/run_embedding_entropy.py` | 170 | `cv_folds: int = 5` → `cv_folds: int = 3` |
| `src/detection_game/utils/cv_utils.py` | 24 | `n_folds: int = 5` → `n_folds: int = 3` |
| `scripts/plot_multisample_recall_vs_k.py` | 35, 291 | default 5 → 3 |
| `src/detection_game/utils/data_splitting.py` | 171 | docstring example `n_folds=5` → `n_folds=3` |

### 4. Update config file comments with correct sample counts
- `configs/dataset/gpqa-train-val.yaml`: Comment says "78 samples" → "79 samples"
- `configs/dataset/usaco-train-val.yaml`: Remove "limit 100" from comment (that's for testing, not paper runs)

### 5. Update test file to use 3-fold
- `tests/test_cv_utils.py` - update all `n_folds=5` to `n_folds=3` for consistency
