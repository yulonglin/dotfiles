# Results

Turning a finished run into something a reader can check.

## Every number ships with its null and its ceiling

What would this number be with no signal at all? Put that beside it, not in a footnote. What is the maximum it could reach given the task and the labels? Same. A number without both is uninterpretable, and a reader who has to reconstruct them will reconstruct them wrong.

**Every estimate carries an interval, and the interval names what it covers** — which sources of variation it includes and which it omits, stated where the number is displayed. The failure mode is not a missing interval; it is a confidently narrow one.

**Causal claims match the evidence.** Default register: *associated with*, *consistent with*, *suggests*, *is higher in the X condition*, *we observe*. Reserve causal verbs for tested mechanism or RCT-style designs. When the evidence is strong, say it plainly.

## Metric, before anything else

- **Ground truth**: where does it come from — existing labels, or an LLM judge? If a judge, it is a measuring instrument and needs its own validation.
- **Classification**: name the positive and negative class explicitly.
- **Distribution and skew**: what is the base rate? A 95%-accurate classifier on a 95%-negative set has learned nothing.
- **Known problems with the data**, stated rather than discovered by the reader.
- **Chance correction** where the metric admits it.

**Classification by meaning uses a judge, not a regex.** Keyword matching misses paraphrase and over-counts quotation of the searched string. One call per sample, never batched.

## Analysing monitors and judges

The goal is interesting qualitative behaviour and comparative failure modes, not another aggregate.

- **Target-model behaviour**: use judges to categorise what the model actually did, and prefer a taxonomy that *emerges* from the rollouts over forcing examples into predefined buckets.
- **Monitor evidence**: for each example show the most relevant part of the monitor's input and output, with the full raw text in a collapsible beside it.
- **Monitor errors first**: prioritise the cases a monitor got wrong, and characterise *why* it failed.
- **Disagreements**: find where A is right and B is wrong, where B is right and A is wrong, and where both agree for apparently different reasons.
- **Comparative advantage**: identify recurring example types where one monitor beats another, and propose why.
- **Several examples per pattern**, not one anecdote and a summary statistic.

**Quantify how common each discovered pattern is**, so a robust recurring finding is distinguishable from an interesting anecdote. The page should make it easy to walk from aggregate finding → selected examples → highlighted evidence → full raw transcript.

## Transcript review

Sample deliberately and say how. Look for scorer misconfiguration, eval awareness, refusals, tool errors and format parsing failures — the things aggregate metrics hide by construction.

Label as you go, and export the labels in a form that can be rejoined to the data (JSONL). A review whose conclusions cannot be traced back to labelled examples is an impression.

## The page itself

Up to three findings. Per finding: **claim → figure → caption → setup → implications → caveats and uncertainty → next steps.** Rate which directions look promising and name the research question each would answer.

This is the page a reviewer opens; it links out to the dataset explainer, the transcript review, and the spec for what comes next.

## Separation of concerns

Labelling comes from experimental design, never from outcomes. Scoring is computed from raw outputs, blind to labels. Analysis joins the two. **Any stage peeking at another's output is a leak**, and if removing a step would change the reported result while that step depends on the result, it is circular.

**The reviewer test**: before any methodological shortcut, ask whether a reviewer seeing it would find it suspect. If maybe, find the principled approach. There is no "it's just a quick analysis" exception.

## Related

How the page is built: `artifacts.md`. Statistical machinery and slicing: the `results-artifact` skill. Judge construction and persistence: the `llm-judge` skill.
