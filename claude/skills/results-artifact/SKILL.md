---
name: results-artifact
description: Build a research results page to Yulong's review standard — intervals, nulls, chance correction, slicing, review checklist.
---

# Results Pages

The checklist Yulong applies to every research artifact (2026-08-27). Build against it before publishing; it is what he checks first. Page mechanics — collapsible units, transcripts, annotation layer, titles — are in the `artifact-writing` skill.

## Presentation

- **Numbers in prose can be a table; numbers in a table can be a plot.** Escalate to the richest form the data supports. On a page, draw charts as **native SVG** using the built-in `dataviz` skill and the hexes in `lib/plotting/tokens.json` — a matplotlib PNG bakes its light ground into the pixels and glares in dark mode. Reserve embedded images for figures whose point is what matplotlib itself produces.
- Mermaid diagrams for mechanisms and pipelines.
- Commenting layer that can save, delete and update a comment, copy all comments, and keep highlights stable with no flicker while selecting text.

## Clarity

- **Every heading is a claim (hedged appropriately) or a question.** Reading the headings alone states what the page found; the sections elaborate or provide evidence.
- **Research questions, one sentence each per section, listed at the start of the page.**
- Column names and axis labels carry hover or click definitions.
- **P0/P1/P2 are reserved for priorities.** Hypotheses and predictions are H1/H2, requirements R1/R2 — never P-numbers.
- Define Claude's habitual jargon where it appears: what an **arm** is and which arms exist; what a **smoke test** is, what it exercises, and what it does and does not show.
- A **Terminology** and an **FAQ** section at the bottom.
- Write for a new colleague: context first, no buzzwords, no corporate phrasing, no fluffy transitions.
- **Enumerations are lists, never prose.** Anything listing three or more items — models, settings, arms, what is held constant versus varied — is a bulleted or numbered list, or one comma-separated line (Yulong, 2026-08-27).

## Visibility, per set of experiments

- The research question it answers.
- Models, datasets, hyperparameters: what is held constant, what is varied.
- Prompts and prompt templates in full, verbatim, collapsible.
- A full example task or transcript, ideally one positive and one negative, verbatim, collapsible, roles colour-coded with emoji and label per model (agent, monitor, judge).
- Agent and monitor affordances: tools, and what each can see.
- Environment components and how the environment state changes.

## Rigour

- The metric's ground truth: pre-labelled, or an LLM judge or scorer. For classification, which is the positive and which the negative class, the data distribution and skew, and known issues with the data.
- Model inputs and outputs verbatim in a collapsible block, for every model in the loop.
- Every estimate with its interval and what the interval covers; every rate beside its null.

## Intervals

**Every estimate carries an interval, and the interval names what it covers.** No bare point estimate. Proportions get Wilson, never the normal approximation, which misbehaves at 0 and 1. Differences on paired data get a paired interval or an exact test — overlapping intervals are never a substitute for a paired test on paired data. Anything without a closed form gets a bootstrap.

Small denominators are stated as counts next to the percentage (0/7, not "0%"), because the Wilson upper bound on 0/7 is 35.4% and the percentage alone hides that.

**The failure mode is not a missing interval but a confidently narrow one**: a CI covering only sampling over items, while the measurement instrument itself is stochastic across repeats, looks rigorous and understates the truth. Say which sources of variation the interval includes and which it omits, and when a known source is omitted, say so where the number is displayed rather than only in the write-up.

## Nulls and ceilings

A rate alone is uninterpretable, because the trivial baseline that produces it is usually most of it. State the null next to the number itself, never in a footnote:

- **Chance value** — what a signal-free procedure scores. Often far from zero: for agreement, chance agreement from the two base rates (two raters flagging 94% each agree ~89% by coincidence); for TPR, the flag rate, since a monitor flagging everything has TPR 1.0; for a union or ensemble gain, the same component used twice.
- **Degenerate value** — what a constant predictor scores (always-flag, never-flag, always-majority-class). If a degenerate predictor beats the method, the method has no result.
- **Marginal-preserving null** — permute the labels or the correspondence while holding the marginals fixed, and report the distribution. Prefer this wherever it is cheap: it is the same claim as the closed form but demonstrated, and it catches structure the closed form misses. Report the resolution floor, 1/(N+1), so an under-powered permutation is not read as a null result.
- **Behaviour-free null** — a predictor seeing only the scaffold (condition label, task metadata, lengths, counts, timings) and none of the behaviour under study. If it performs, the experiment is measuring the scaffold. This fires more often than expected and is the cheapest way to catch a confound before publication.

State the **ceiling** where one exists: the same instrument measured twice bounds how much any difference between instruments can mean. Report chance-corrected effects (kappa, lift over shuffled) alongside raw ones, and when a raw number moves a lot, decompose the move into base-rate and signal parts. A significant but negligible margin is described as "small and real", never as "at chance" and never as the raw figure alone.

## Variables, stated per requirement

Each requirement or section that produces a number names its own four: the **research question** in one sentence, phrased so an outcome could contradict it; the **independent variable** and its levels, including anything varied by accident, since a treatment arm that also changed the prompt, renderer, model version or temperature has those as independent variables whether or not they were meant to be — naming them is how a confound becomes a stated limitation rather than a hidden claim; the **dependent variable**, its unit of analysis (per sample, per task, per episode, per cluster) and how it aggregates, since the same numbers give different intervals depending on whether the denominator is episodes or independent clusters; and the **null**.

## Slicing

State the factors the result can be sliced by, and slice by them when a slice could reverse or hide the finding. A pooled number across strata that differ in base rate is a Simpson's paradox waiting to be found by a reviewer. Where one stratum contains none of a class, say so — a metric conditioned on a stratum is not the same estimand as the pooled one.
