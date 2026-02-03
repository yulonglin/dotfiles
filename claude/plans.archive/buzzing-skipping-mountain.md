# Plan: Documentation + Code Alignment for Reporting Standards

## Summary

1. Add `REPORTING_CHECKLIST.md` reference to CLAUDE.md
2. Fix k=5 defaults in scripts → k=10
3. Address missing SEM output in split mode (documentation clarification vs code fix)

---

## Part 1: Documentation Reference (Quick)

### CLAUDE.md edits

**1. Core Reference Docs (lines 18-21) - Add REPORTING_CHECKLIST.md:**
```markdown
**Core Reference Docs:**
- `ai_docs/core/CLI_REFERENCE.md` - Full command examples with parameter tables
- `ai_docs/core/STATISTICAL_ANALYSIS.md` - CV modes, multi-sample analysis, reporting
- `ai_docs/core/REPORTING_CHECKLIST.md` - Results reporting checklist (SEM, k-samples, metrics)
- `ai_docs/methods/` - Detection method deep-dives
```

**2. Documentation Index (line 729) - Add row:**
```markdown
| `ai_docs/core/REPORTING_CHECKLIST.md` | Results reporting checklist |
```

---

## Part 2: Fix k=5 Defaults in Scripts

Update these files to use k=10 as default:

| File | Line | Change |
|------|------|--------|
| `scripts/compute_ci_per_question.py` | 30 | `k_samples: int = 10` |
| `scripts/compute_ci_per_question.py` | 159 | `default=10` |
| `scripts/compute_bootstrap_ci.py` | 26 | `k_samples: int = 10` |
| `scripts/compute_bootstrap_ci.py` | 165 | `default=10` |
| `scripts/run_paraphrase_strategy_experiments.py` | 110 | `k_samples: int = 10` |
| `scripts/run_strategy_selection_experiments.py` | 104, 137 | `k_samples: int = 10` |

Also update example in `run_multisample_bootstrap_cv.py` docstring (line 15):
```python
#     classifier.k_samples=10 \
```

---

## Part 3: Add Bootstrap SEM to Split Mode (User Selected)

### Current State

| CV Mode | Variance Source | Output Key |
|---------|-----------------|------------|
| **kfold** | std across 3 folds | `std_recall` |
| **split** (ICML) | **None** | No variance output |

### Implementation: Add Bootstrap SEM

Modify `split_bootstrap_cv()` to run multiple bootstrap iterations of the full pipeline and compute std(recalls):

```python
def split_bootstrap_cv(..., sem_iterations: int = 100) -> dict:
    """
    Perform split-based bootstrap CV with SEM estimation.

    For SEM: runs the full pipeline sem_iterations times with different
    bootstrap samples, collects recalls, computes std(recalls) as SEM.
    """
    recalls = []
    aurocs = []
    partial_aucs = []

    for i in range(sem_iterations):
        seed_i = seed + i * 2000  # Different seed per iteration

        # Bootstrap aggregate dev set
        dev_agg_scores, dev_agg_labels = bootstrap_aggregate(
            dev_samples, dev_labels, k_samples, n_iterations,
            aggregation, seed_i, ...
        )

        # Bootstrap aggregate test set
        test_agg_scores, test_agg_labels = bootstrap_aggregate(
            test_samples, test_labels, k_samples, n_iterations,
            aggregation, seed_i + 1000, ...
        )

        # Compute threshold on dev
        threshold_result = compute_threshold_on_split(
            dev_agg_scores, dev_agg_labels, target_fpr, conservative
        )

        # Evaluate on test
        eval_result = evaluate_with_threshold(
            test_agg_scores, test_agg_labels, threshold_result["threshold"]
        )

        recalls.append(eval_result["recall"])
        # ... collect other metrics

    return {
        "test_recall": float(np.mean(recalls)),
        "sem_recall": float(np.std(recalls)),  # Bootstrap SEM
        "test_auroc": float(np.mean(aurocs)),
        "sem_auroc": float(np.std(aurocs)),
        # ... other fields
    }
```

### Key Changes

1. Add `sem_iterations` parameter (default 100)
2. Loop over iterations, each with different seed
3. Collect metrics from each iteration
4. Output `sem_*` fields alongside point estimates

### Backward Compatibility

- Keep existing output fields (test_recall, test_auroc, etc.)
- Add new `sem_*` fields
- Default sem_iterations=100 is fast enough (~10s) but provides good SEM estimates

---

## Files to Modify

### Documentation
- `CLAUDE.md` - Add REPORTING_CHECKLIST.md reference (2 places)

### Code (k=5 → k=10)
- `scripts/compute_ci_per_question.py` (2 places)
- `scripts/compute_bootstrap_ci.py` (2 places)
- `scripts/run_paraphrase_strategy_experiments.py` (1 place)
- `scripts/run_strategy_selection_experiments.py` (2 places)
- `src/detection_game/classifiers/run_multisample_bootstrap_cv.py` (1 docstring example)

### Code (Bootstrap SEM)
- `src/detection_game/classifiers/run_multisample_bootstrap_cv.py`:
  - Add `sem_iterations` parameter to `split_bootstrap_cv()`
  - Wrap existing logic in loop over sem_iterations
  - Add `sem_recall`, `sem_auroc`, `sem_partial_auc` to output dict
  - Update `run_split_analysis()` to pass through and display SEM

### Documentation (clarification)
- `ai_docs/core/REPORTING_CHECKLIST.md` - Update to clarify SEM comes from bootstrap iterations in split mode

---

## Verification

1. `grep -r "k_samples.*= *5" scripts/` - should find 0 matches after
2. `grep "REPORTING_CHECKLIST" CLAUDE.md` - should find 2 matches
3. Run split mode and verify `sem_recall` appears in output:
   ```bash
   python -m src.detection_game.classifiers.run_multisample_bootstrap_cv \
     classifier.dev_csv=<dev> classifier.test_csv=<test> \
     classifier.k_samples=10
   ```
4. Check sem_recall is reasonable (typically 0.02-0.10 for recall ~0.70)
