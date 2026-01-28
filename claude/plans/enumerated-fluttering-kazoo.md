# Plan: Update Bootstrap CV to Bootstrap Entire Pipeline

## Problem Statement

The current `split_bootstrap_cv` mode computes a **fixed threshold** from the dev set, then only bootstraps the test set evaluation. This underestimates uncertainty because it doesn't capture threshold selection variance.

**Current flow (Option 1 - Fixed Threshold):**
```
1. Bootstrap aggregate dev → single aggregated dev scores
2. Compute threshold ONCE on aggregated dev
3. Bootstrap aggregate test → single aggregated test scores
4. Evaluate ONCE with fixed threshold
5. Report single recall value (no variance estimate)
```

**Proposed flow (Option 2 - Full Pipeline Bootstrap):**
```
For each bootstrap iteration i:
  1. Sample k questions from dev (with replacement)
  2. Aggregate dev scores → compute threshold_i at target FPR
  3. Sample k questions from test (with replacement)
  4. Aggregate test scores → compute recall_i at threshold_i
  5. Collect recall_i

Report: mean(recalls), SEM = std(recalls), 95% CI
```

## Key Change

The threshold is **recomputed for each bootstrap iteration** from a fresh dev sample, not computed once and held fixed.

## Evidence Supporting Option 2

1. **Two-stage estimation literature**: Plug-in methods that treat stage-one estimates as fixed underestimate uncertainty
2. **Nested CV best practices**: Selection processes must be included in resampling loop
3. **Anthropic's eval framework**: Emphasizes capturing all variance sources
4. **Efron & Tibshirani (1993) Chapter 19**: For multi-stage procedures, bootstrap the entire procedure

| Variance Source | Option 1 | Option 2 |
|-----------------|----------|----------|
| Test sampling variance | ✓ | ✓ |
| k-question aggregation variance | ✓ | ✓ |
| **Dev sampling variance** | ✗ | ✓ |
| **Threshold selection variance** | ✗ | ✓ |

## Implementation Plan

### Files to Modify

1. **`src/detection_game/classifiers/run_multisample_bootstrap_cv.py`** - Main implementation
2. **`src/detection_game/configs/classifier/bootstrap_cv.yaml`** - Add new parameter

### Changes

#### 1. Add new parameter `full_pipeline_bootstrap` (default: True)

```yaml
# bootstrap_cv.yaml
full_pipeline_bootstrap: true  # Bootstrap dev threshold selection + test evaluation
```

#### 2. Refactor `split_bootstrap_cv()` function

**Current signature:**
```python
def split_bootstrap_cv(
    dev_df: pd.DataFrame,
    test_df: pd.DataFrame,
    k_samples: int,
    aggregation: str,
    n_iterations: int,
    target_fpr: float,
    ...
) -> dict:
```

**New implementation logic:**

```python
def split_bootstrap_cv(..., full_pipeline_bootstrap: bool = True):
    if full_pipeline_bootstrap:
        # Option 2: Bootstrap entire pipeline
        recalls = []
        fprs = []
        thresholds = []

        for i in range(n_iterations):
            # Stage 1: Sample dev, compute threshold
            dev_bootstrap = sample_k_questions_per_model(dev_df, k_samples, seed=i)
            dev_agg = aggregate_scores(dev_bootstrap, aggregation)
            threshold_i = compute_threshold_at_fpr(dev_agg, target_fpr)

            # Stage 2: Sample test, evaluate at that threshold
            test_bootstrap = sample_k_questions_per_model(test_df, k_samples, seed=i + n_iterations)
            test_agg = aggregate_scores(test_bootstrap, aggregation)
            recall_i, fpr_i = evaluate_at_threshold(test_agg, threshold_i)

            recalls.append(recall_i)
            fprs.append(fpr_i)
            thresholds.append(threshold_i)

        return {
            'recall_mean': np.mean(recalls),
            'recall_sem': np.std(recalls),  # Full variance
            'recall_ci_lower': np.percentile(recalls, 2.5),
            'recall_ci_upper': np.percentile(recalls, 97.5),
            'fpr_mean': np.mean(fprs),
            'threshold_mean': np.mean(thresholds),
            'threshold_sem': np.std(thresholds),  # New: threshold variance
            'n_iterations': n_iterations,
            'full_pipeline_bootstrap': True
        }
    else:
        # Option 1: Fixed threshold (current behavior, for backwards compatibility)
        # ... existing code ...
```

#### 3. Update output reporting

Add new fields to JSON output:
- `recall_sem` - Standard error of recall (full variance)
- `recall_ci_lower`, `recall_ci_upper` - 95% CI via percentile method
- `threshold_sem` - Standard error of threshold (shows dev set stability)
- `full_pipeline_bootstrap` - Flag indicating which method was used

#### 4. Helper function for sampling k questions

```python
def sample_k_questions_per_model(
    df: pd.DataFrame,
    k: int,
    seed: int
) -> pd.DataFrame:
    """Sample k questions per model (sandbagging and normal).

    Samples QUESTIONS (sample_id), not individual rows, to preserve
    paraphrase correlation structure.
    """
    rng = np.random.default_rng(seed)
    samples = []

    for label in df['label'].unique():
        label_df = df[df['label'] == label]
        unique_questions = label_df['sample_id'].unique()

        # Sample k questions with replacement
        sampled_questions = rng.choice(unique_questions, size=k, replace=True)

        # Get all rows for sampled questions
        for q in sampled_questions:
            samples.append(label_df[label_df['sample_id'] == q])

    return pd.concat(samples, ignore_index=True)
```

### Verification

1. **Unit test**: Verify that with `full_pipeline_bootstrap=True`, the SEM captures threshold variance (should be larger than with `full_pipeline_bootstrap=False`)

2. **Integration test**: Run on existing GPQA data:
   ```bash
   python -m src.detection_game.classifiers.run_multisample_bootstrap_cv \
     classifier.dev_csv=out/gpqa_c3_dev.csv \
     classifier.test_csv=out/gpqa_c3_test.csv \
     classifier.k_samples=10 \
     classifier.full_pipeline_bootstrap=true \
     classifier.output_json=out/bootstrap_test.json
   ```

3. **Comparison test**: Run both modes on same data, verify Option 2 SEM ≥ Option 1 SEM

### K-fold CV Mode (Unchanged)

The k-fold CV mode (`cross_validate_bootstrap`) already recomputes threshold for each fold, providing fold-based threshold variance. This is a reasonable approximation of full pipeline variance for k-fold use cases. No changes needed.

### Backwards Compatibility

- Default `full_pipeline_bootstrap=true` (principled approach)
- Existing scripts can set `full_pipeline_bootstrap=false` to get old behavior
- Output JSON includes flag so consumers know which method was used

## Additional: K-Fold Bootstrap SEM

### Problem

Current k-fold mode outputs `std_recall` = std across K folds (N=3), which is NOT a proper SEM. Folds are correlated (share (K-1)/K training data), so naive SEM formula doesn't apply.

### Solution: Bootstrap K-Fold

For each bootstrap iteration:
1. Re-assign folds with different seed
2. Run full k-fold CV (train on K-1 folds, test on holdout)
3. Record mean recall across K folds

Then `sem_recall = std(bootstrap_mean_recalls)`.

### Implementation

```python
def kfold_bootstrap_cv(..., sem_iterations: int = 1000):
    bootstrap_mean_recalls = []

    for i in range(sem_iterations):
        # Re-run k-fold with different fold seed
        fold_recalls = []
        kf = KFold(n_splits=k_folds, shuffle=True, random_state=seed_base + i)

        for train_idx, test_idx in kf.split(df):
            train_df = df.iloc[train_idx]
            test_df = df.iloc[test_idx]
            # Sample k questions, aggregate, compute threshold on train
            # Evaluate on test
            recall_fold = evaluate_fold(train_df, test_df, k_samples, ...)
            fold_recalls.append(recall_fold)

        bootstrap_mean_recalls.append(np.mean(fold_recalls))

    return {
        'recall_mean': np.mean(bootstrap_mean_recalls),
        'sem_recall': np.std(bootstrap_mean_recalls),
        'ci_lower': np.percentile(bootstrap_mean_recalls, 2.5),
        'ci_upper': np.percentile(bootstrap_mean_recalls, 97.5),
    }
```

---

## Documentation Changes (Also Required)

### 1. CLAUDE.md - Add REPORTING_CHECKLIST.md references

Add to Core Reference Docs section (~line 15):
```markdown
- `ai_docs/core/REPORTING_CHECKLIST.md` - Reporting standards and checklist
```

Add to Documentation Index section (~line 445):
```markdown
| `ai_docs/core/REPORTING_CHECKLIST.md` | Reporting standards checklist |
```

### 2. Fix k=5 → k=10 defaults in scripts

| File | Lines |
|------|-------|
| `scripts/compute_ci_per_question.py` | 30, 159 |
| `scripts/compute_bootstrap_ci.py` | 26, 165 |
| `scripts/run_paraphrase_strategy_experiments.py` | 110 |
| `scripts/run_strategy_selection_experiments.py` | 104, 137 |

### 3. Update STATISTICAL_ANALYSIS.md variance documentation

Add section clarifying variance sources:

| Mode | Before | After |
|------|--------|-------|
| **split** | No SEM | `sem_recall` (full pipeline bootstrap) |
| **k-fold** | `std_recall` (std across folds) | `sem_recall` (bootstrap k-fold) |

---

## Summary

| Aspect | Before | After |
|--------|--------|-------|
| Split threshold | Fixed from dev | Resampled each iteration |
| Split variance captured | Test only | Dev + Test |
| K-fold variance | std across K folds | Bootstrap SEM |
| SEM interpretation | Conditional/partial | Full experiment variance |
| Default behavior | N/A | Full pipeline bootstrap |
