# Research Integrity

Principles for scientific rigor. These aren't edge cases — they're the kind of mistakes that invalidate results.

## The Reviewer Test

Before any methodological shortcut, workaround, or "it's fine" reasoning, ask:

**"If a reviewer or advisor saw me do this, would they find it suspect?"**

If yes — or even maybe — stop and find the principled approach. The principled approach is almost always: derive from source of truth, don't peek at outcomes, don't skip steps because you "already know" the answer.

This applies to everything: data labeling, sample filtering, metric computation, baseline comparisons, hyperparameter choices, figure generation. There is no "it's just a quick analysis" exception — quick analyses become paper figures.

## No Circular Reasoning

Never use an outcome to determine the label, then measure that outcome.

| Bad | Why | Do instead |
|-----|-----|------------|
| Match eval files to conditions by accuracy | Labels derived from the metric you're measuring → tautological | Content-based fingerprinting (unique text in prompts, metadata, config order verified independently) |
| Select hyperparameters on test set, report test metrics | Overfitting to held-out data | Tune on dev/train, evaluate once on test |
| Filter "bad" samples after seeing their scores | Cherry-picking → inflated metrics | Define exclusion criteria before looking at results |
| Validate a detector using the same data used to build it | Training = test → meaningless accuracy | Held-out split or cross-validation |

**General test:** If removing the step would change the reported result, and the step depends on the result, it's circular.

## Report What Happened, Not What You Wanted

- Report all conditions, including ones that didn't work (censorship improving accuracy is a finding, not an inconvenience)
- Don't quietly drop failed conditions, outliers, or null results
- If a result is surprising, investigate the cause — don't explain it away
- State effect sizes with uncertainty (CI/SE), not just significance

## Shortcuts That Aren't

When data is messy or a mapping is unclear, the temptation is to hack around it. Don't.

| Tempting shortcut | What to do instead |
|------|------|
| "I know which file is which from the accuracy" | Find an identifier in the data itself (metadata, content, config) |
| "Let me just hardcode the mapping" | Derive it programmatically from source of truth |
| "Close enough — the numbers look right" | Verify the pipeline end-to-end on a case you can check by hand |
| "It probably doesn't matter" | If you're not sure it doesn't matter, check |

## Separation of Concerns

Keep labels, scores, and analysis in separate stages with clear data flow:

1. **Labeling** — determined by experimental design (config, condition assignment), never by outcomes
2. **Scoring** — computed from raw outputs, blind to labels
3. **Analysis** — joins labels and scores, computes metrics

If any stage peeks at another stage's output to do its job, the pipeline has a leak.
