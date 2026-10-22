# Research Integrity

**Reviewer test:** before any methodological shortcut, ask whether a reviewer would find it suspect. If maybe, find the principled approach. There is no "just a quick analysis" exception.

**No circular reasoning:** never use an outcome to set a label and then measure that outcome. If removing a step would change the reported result, and the step depends on that result, it's circular.

**Separation of concerns:** *condition* labels come from design, never from the quantity being measured; scoring is blind to labels and condition; analysis joins the two. Any stage peeking at another's output is a leak. Annotating outcomes is fine — but freeze the codebook on a named discovery slice and estimate prevalence only on episodes that did not form it.

**Report what happened** — every condition. Never quietly drop failed conditions, outliers or nulls, and investigate surprises rather than explaining them away.

**Every model call is shown with its input beside its output.** For monitors, judges and graders, any results page, review artifact or transcript viewer shows, per sample, the exact input the model received (the rendered prompt and the text, tokens or lens readout it judged) next to its output and rationale — never the verdict or rationale alone, which cannot be checked without what produced it. Every monitor or judge call therefore yields a rationale, not a bare label: when a fixed protocol asks for a single letter, keep that scored call unchanged and capture the rationale beside it (the API's reasoning summary, or a separately versioned rationale prompt) (Yulong, 2026-10-07).

**Say which findings you went looking for:** each is pre-specified or discovered in this data, with the number of slices and comparisons stated. A discovered finding is a hypothesis until fresh episodes test it.

The rest — nulls, ceilings, intervals and their unit of analysis, causal register, scorer versus judge: `~/.claude/checklists/results-analysis.md`; statistical machinery and slicing: `results-artifact`.
