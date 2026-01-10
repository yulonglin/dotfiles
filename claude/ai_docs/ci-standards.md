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

- **Report 95% CI** (not stderr, not std)
- Format as `mean [lower, upper]` or `mean ± halfwidth`
- Define in figure/table captions what CI represents
- Bold best method, but **only if its CI doesn't overlap with second-best**

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
| Single method, n questions | mean [95% CI] |
| Comparing methods on same questions | diff [95% CI on diff] |
| Multiple seeds | Average per-question first, then CI |
| Small n (3-5 items) | Mean and range, no CI |
| Per-item breakdown | Each item's mean [95% CI] |

## Common Mistakes

- **Wrong n**: Using n=seeds instead of n=questions
- **Reporting SE or std**: Always convert to 95% CI for final reporting
- **Unpaired comparison**: Computing CIs separately then comparing (loses power)
- **CI on small n**: Computing 95% CI with n=3 seeds (meaningless)
- **Claiming significance**: When CIs overlap (they might still be significant, but can't claim from CI alone)
