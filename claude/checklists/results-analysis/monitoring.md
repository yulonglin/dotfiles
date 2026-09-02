# Monitoring Analysis

How to analyse model-monitoring results. Usable verbatim as a standalone analysis prompt; it assumes the general standards in `../results-analysis.md` — evidence, intervals, blinding, provenance, page shape — and adds only what those cannot say about monitors.

Analyse the results as an empirical researcher. The goal is to **surface interesting qualitative behaviours and comparative failure modes**, not just aggregate metrics. Agree first on the data and models to be used, and the metrics to index on.

- **Target-model behaviour**: use LLM judges to identify and categorise interesting behaviours in the target-model rollouts. Prefer a taxonomy that *emerges* from the rollouts over forcing examples into predefined categories — built on a named discovery slice and frozen before anything is counted, per the codebook rule in `../results-analysis.md`.
- **Monitor evidence**: for each example, show the most relevant, highlighted parts of the monitor's input and output, with the full raw input and output in collapsible sections beside them.
- **Monitor errors first**: prioritise examples where a monitor is wrong, and characterise *why* it appears to have failed.
- **Monitor disagreements**: find cases where monitors disagree, especially — Monitor A correct and B wrong; B correct and A wrong; both reaching the same conclusion for apparently different reasons.
- **Comparative advantage**: identify recurring behaviours or example types where one monitor has a meaningful advantage over another, and propose hypotheses for why.
- **Representative examples**: for each important pattern, show several concrete samples rather than relying only on summary statistics.

**Quantify how common each discovered pattern is**, on the episodes that did not form the taxonomy, distinguishing robust recurring findings from interesting anecdotes. The output should make it easy to move from aggregate finding → selected examples → highlighted evidence → full raw transcript.
