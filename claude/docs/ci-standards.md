# Confidence Interval Standards for Experiment Design and Analysis

Canonical reference for statistical reporting in all research experiments.

---

## 1. Unit of Analysis

- Compute CI across **questions/samples**, not seeds
- If multiple seeds: average per-question first, then compute 95% CI across questions
- **n = number of questions**, not number of seeds

## 2. Formula

```
SE = std(scores) / sqrt(n)
95% CI = mean ± 1.96 * SE
```

## 3. Paired Comparisons

When comparing methods on the same questions:

1. Compute per-question difference first: `diff = score_A - score_B` (element-wise, one value per question)
2. `SE_diff = std(diff) / sqrt(n)`
3. CI on the difference is tighter when models are correlated (which they usually are on same questions)

## 4. Reporting

- **Report SE (SEM) alongside each score** - the fundamental uncertainty measure
- 95% CI is derived: `mean ± 1.96 × SE` (report if helpful, but SE is primary)
- Format: `mean ± SE` or `mean (SE=X)` or `mean [95% CI]`
- Define in figure/table captions what error bars represent
- Bold best method, but **only if CIs don't overlap with second-best**

## 4a. Clustered Standard Errors

When questions are **grouped** (e.g., multiple questions per passage/image/conversation):

```
SE_clustered = std(cluster_means) / sqrt(n_clusters)
```

**Not**:
```
SE_naive = std(all_scores) / sqrt(n_questions)  # WRONG when grouped
```

Clustered SE can be **3x larger** than naive SE. Always check if your eval has question groupings.

## 5. Small-n Groups

When n is small (e.g., 3-5 model organisms, seeds, or datasets):

- Report **mean and range**, no CI (CI would be meaningless)
- Show per-item results with their own CIs (each has n = num_questions)
- Optionally report pooled summary in text

Same logic applies to any small-n grouping: seeds, datasets, model families.

## 6. Experiment Planning (Power Analysis)

To detect a difference of δ (e.g., 0.03 for 3 percentage points) at 80% power with 5% false positive rate:

```
n ≈ 8 * Var(diff) / δ²
```

**Rough guide** (assuming typical variance):
- ~1000 questions for 3pp difference
- ~250 questions for 6pp difference
- ~100 questions for 10pp difference

**Key insight**: If your eval has fewer questions, you can only reliably detect larger effects. A non-significant result with small n may be **underpowered, not evidence of no effect**.

---

## Quick Reference

| Situation | What to report |
|-----------|----------------|
| Single method, n questions | mean ± SE (or mean [95% CI]) |
| Comparing methods on same questions | diff ± SE_diff |
| Multiple seeds | Average per-question first, then CI |
| Small n (3-5 items) | Mean and range, no CI |
| Per-item breakdown | Each item's mean [95% CI] |

## Common Mistakes

- **Wrong n**: Using n=seeds instead of n=questions
- **Reporting std instead of SE**: std measures spread, SE measures uncertainty in the mean
- **Unpaired comparison**: Computing CIs separately then comparing (loses power)
- **CI on small n**: Computing 95% CI with n=3 seeds (meaningless)
- **Claiming significance**: When CIs overlap (they might still be significant, but can't claim from CI alone)

## 7. Sensitivity & Robustness

After computing main results, check at least one:
- Drop outliers (top/bottom 5%): same conclusion?
- Alternative aggregation (median, trimmed mean): same direction?
- Subset analysis: consistent across subgroups?

If conclusion changes → report as fragile. Always state which checks were run.

## 8. Reporting Null Results

Non-significant ≠ no effect. When reporting null findings:
- Report the CI of the difference (not just "p > 0.05")
- State the detectable effect size at your N (power analysis)
- Example: "No significant difference (Δ = 1.2pp, 95% CI: [-2.1, 4.5], N=200, powered to detect ≥6pp)"
