---
name: results-artifact
description: Statistical machinery for a research results or findings page — which interval or test a number gets, the nulls a rate must be read against, chance correction and ceilings, and when to slice. Use when building or reviewing a results page, findings report or analysis writeup, when picking an interval or a significance test, when asking what a number would be with no signal, when correcting for chance or agreement, or when a pooled number spans strata that differ.
---

# Results Pages

The standard for what a results page must show, and how it is reviewed, lives in **`~/.claude/checklists/results-analysis.md`**. Read it when building or reviewing the page; it is the content, and this file adds only the statistical machinery it deliberately does not carry.

The checklist covers the null-and-ceiling and interval principles, causal register, metric hygiene (ground truth, positive class, base rate and skew, judge-not-regex), the ingredients a reader needs to reconstruct the run, every aggregate being one click from its examples, sampled and rejoinable transcript review, provenance, the annotation layer, the fixed per-finding shape, and separation of concerns. Its `Related` section names this file as the home for what follows.

## Which interval, which test

Proportions get **Wilson**, never the normal approximation, which misbehaves at 0 and 1. Differences on paired data get a **paired interval or an exact test** — overlapping intervals are never a substitute for a paired test on paired data. Anything without a closed form gets a **bootstrap**.

Small denominators are stated as counts next to the percentage (0/7, not "0%"), because the Wilson upper bound on 0/7 is 35.4% and the percentage alone hides that.

The unit of analysis sets the denominator, and the same numbers give different intervals depending on whether it is episodes or independent clusters — name it before computing.

A CI covering only sampling over items, while the measurement instrument itself is stochastic across repeats, looks rigorous and understates the truth: say which sources of variation the interval includes and which it omits, where the number is displayed.

## The four nulls

A rate alone is uninterpretable, because the trivial baseline that produces it is usually most of it.

- **Chance value** — what a signal-free procedure scores. Often far from zero: for agreement, chance agreement from the two base rates (two raters flagging 94% each agree ~89% by coincidence); for TPR, the flag rate, since a monitor flagging everything has TPR 1.0; for a union or ensemble gain, the same component used twice.
- **Degenerate value** — what a constant predictor scores (always-flag, never-flag, always-majority-class). If a degenerate predictor beats the method, the method has no result.
- **Marginal-preserving null** — permute the labels or the correspondence while holding the marginals fixed, and report the distribution. Prefer this wherever it is cheap: it is the same claim as the closed form but demonstrated, and it catches structure the closed form misses. Report the resolution floor, 1/(N+1), so an under-powered permutation is not read as a null result.
- **Behaviour-free null** — a predictor seeing only the scaffold (condition label, task metadata, lengths, counts, timings) and none of the behaviour under study. If it performs, the experiment is measuring the scaffold. This fires more often than expected and is the cheapest way to catch a confound before publication.

## Chance correction and ceilings

State the **ceiling** where one exists: the same instrument measured twice bounds how much any difference between instruments can mean.

Report chance-corrected effects (kappa, lift over shuffled) alongside raw ones, and when a raw number moves a lot, decompose the move into base-rate and signal parts. A significant but negligible margin is described as "small and real", never as "at chance" and never as the raw figure alone.

## Slicing

State the factors the result can be sliced by, and slice by them when a slice could reverse or hide the finding. A pooled number across strata that differ in base rate is a Simpson's paradox waiting to be found by a reviewer. Where one stratum contains none of a class, say so — a metric conditioned on a stratum is not the same estimand as the pooled one.

## Reach for a neighbour instead when

- the question is what the page must **show** or how it is reviewed — evidence links, provenance, transcript review, annotation, the per-finding shape: `~/.claude/checklists/results-analysis.md`
- the question is the page's **form** — headings as claims, numbers in plots, terminology and FAQ, attention and progressive disclosure, slides: `~/.claude/checklists/presentation.md`
- you need **page mechanics** — collapsible units, transcript rendering, the annotation layer, `md2artifact`, publishing and republishing: the `artifact-writing` skill
- the metric's ground truth is a **judge**: the `llm-judge` skill, for prompt design, blinding, fan-out and persistence
- the thing being analysed is a **monitor or judge** — errors, disagreements, comparative advantage: `~/.claude/checklists/results-analysis/monitoring.md`
- a chart needs drawing: `house-plots` for papers, the built-in `dataviz` for artifact pages

## Why this file keeps content

Five checklists hold the standards and skills route to them, but the machinery above is deliberately not in a checklist: it is reference a reader reaches for while computing a number, not an item to judge a draft against. `~/.claude/checklists/README.md` has the split; `claude/rules/research-core.md` carries the always-on integrity red lines, and `~/.claude/checklists/research.md` the four variables every design states.
