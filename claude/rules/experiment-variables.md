# Experiment Variables and Nulls

Every experiment, spec, analysis and results write-up states four things **before** any number appears. They are cheap to write and they are what makes a result readable by someone who was not in the room. A document that reports numbers without them is incomplete, whatever else it contains.

## The four

**Research question / hypothesis.** What is being asked, in one sentence, phrased so an outcome could contradict it. "Does X help?" is not enough — "does X raise TPR at matched FPR?" is. If an experiment cannot be phrased so that some result would count against it, say so explicitly and label it exploratory rather than dressing it as a test.

**Independent variable — what is deliberately varied**, and its levels. Include the things varied *by accident*: if the treatment arm also changed the prompt, the renderer, the model version or the sampling temperature, those are independent variables too, whether or not they were meant to be. Naming them is how a confound becomes a stated limitation rather than a hidden claim.

**Dependent variable — what is measured**, at what unit of analysis (per sample, per task, per episode, per cluster), and how it aggregates. The unit is load-bearing: the same numbers give different intervals depending on whether the denominator is episodes or independent clusters.

**Null — what the number would be with no signal at all.** Not a p-value: the value itself. State it next to the number, never in a footnote.

## Nulls are the part that gets skipped

A rate alone is uninterpretable, because the trivial baseline that produces it is usually most of it. So state, per metric:

- **The chance value.** What a signal-free procedure scores. This is often not zero — a product metric, an agreement rate, or anything with a skewed base rate has a chance value well above it.
- **The degenerate value.** What a constant predictor scores — always-flag, never-flag, always-majority-class. If a degenerate predictor beats the method, the method has no result.
- **The marginal-preserving null**, wherever it is cheap: permute the labels or the correspondence while holding the marginals fixed, and report the distribution. This is the same claim as the closed-form null but demonstrated rather than asserted, and it catches structure the closed form misses. Report the resolution floor, 1/(N+1), so an under-powered permutation is not read as a null result.
- **The behaviour-free null.** A predictor that sees only the scaffold — condition label, task metadata, lengths, counts, timings — and none of the behaviour under study. If it performs, the experiment is measuring the scaffold. This one fires more often than expected and is the cheapest way to catch a confound before publication.

Report the chance-corrected effect beside the raw one, and when a raw number moves a lot, decompose the move into its base-rate and signal parts.

## Slicing

State the factors the result can be sliced by, and slice by them when a slice could reverse or hide the finding. A pooled number across strata that differ in base rate is a Simpson's-paradox waiting to be found by a reviewer. Where one stratum contains none of a class, say so — a metric conditioned on a stratum is not the same estimand as the pooled one.

## Where this lives

In a spec, these belong per requirement, not once at the top: each requirement that produces a number names its own question, variables and null. In a results document they belong beside the number. In both, a metric defined once in a shared reference can be cross-linked rather than restated.

Related: `research-integrity.md` for interval discipline and causal register; `llm-judges.md` for judged dependent variables.
