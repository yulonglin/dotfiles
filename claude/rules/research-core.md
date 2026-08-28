# Research Integrity

**Reviewer test:** before any methodological shortcut, ask whether a reviewer seeing it would find it suspect. If maybe, find the principled approach. There is no "it's just a quick analysis" exception.

**No circular reasoning:** never use an outcome to determine a label and then measure that outcome. If removing a step would change the reported result, and the step depends on the result, it's circular.

**Separation of concerns:** labelling comes from experimental design, never from outcomes; scoring is computed from raw outputs, blind to labels; analysis joins the two. Any stage peeking at another's output is a leak.

**Report what happened** — every condition, including the ones that didn't work. Never quietly drop failed conditions, outliers or null results, and investigate surprises rather than explaining them away.

**Every estimate carries an interval, and the interval names what it covers** — which sources of variation it includes and which it omits, said where the number is displayed. The failure mode is not a missing interval but a confidently narrow one.

**Every number ships with its null and its ceiling** — what the number would be with no signal at all, beside it rather than in a footnote.

**Causal claims match the evidence.** Default register: associated with, consistent with, suggests, is higher in the X condition, we observe. Reserve causal verbs for tested mechanism or RCT-style designs. When the evidence is strong, state the claim plainly.

**State four things before any number appears:** the research question in one sentence, phrased so an outcome could contradict it (otherwise call it exploratory); the independent variable and its levels, including anything varied by accident, since a changed prompt, renderer or model version is an independent variable whether or not it was meant to be; the dependent variable, its unit of analysis and how it aggregates; and the null.

**Classification by meaning uses a judge, not a regex** — keyword matching silently misses paraphrase and over-counts quotation of the searched string. One API call per sample, never batched.

Statistical machinery, the full null taxonomy and slicing: the `results-artifact` skill. Judge construction and persistence: `llm-judge`.
