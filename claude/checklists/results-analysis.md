# Results Analysis

Turning a finished run into something a reader can check and inspect — the standard for evidence, review and annotation. The core principle: **optimise for manual inspection.** A human should be able to reconstruct exactly what happened without reading code — read transcripts, label them, and rebuild the full input and output of any example. Domain subskills live in `results-analysis/`: `monitoring.md` today, `jlens.md` and `sandbagging.md` beside it.

## Every number ships with its null and its ceiling

What would this number be with no signal at all? Put that beside it, not in a footnote. What is the maximum it could reach given the task and the labels? Same. A number without both is uninterpretable, and a reader who has to reconstruct them will reconstruct them wrong.

**Every estimate carries an interval, and the interval names what it covers** — which sources of variation it includes and which it omits, stated where the number is displayed. The failure mode is not a missing interval; it is a confidently narrow one.

**Beside every interval: the unit of analysis, and `n` at that unit.** The usual way an interval in LLM work becomes confidently narrow is treating tokens, turns, resampled rollouts or several samples from one prompt as independent when the independent unit is the prompt, the question or the episode. Say which unit the interval is over, how many of them there are, what was resampled versus genuinely independent, and how the interval was constructed — cluster bootstrap over questions, per-seed variance, analytic. Report at least two seeds — two is the floor at which across-seed variance exists at all, and it is a house convention set here rather than a derived constant, so raise it for any project where seed variance is itself part of the finding — or say why across-seed variance is not reported. `results-analysis/sandbagging.md` works a concrete case: intervals omitting question-level clustering and threshold noise are narrower than the truth, and which way they bias is stated where the number appears.

**Every comparison names its test, its effect size and `n` per condition.** Which test — Fisher, McNemar, a bootstrap — and what its significance means for this comparison (`presentation.md`); how large the difference is in the units of the metric; and how many units of analysis sat in each arm. A p-value on its own is incomplete: it says the difference is unlikely under the null, not that it is large enough to matter.

**Causal claims match the evidence.** Default register: *associated with*, *consistent with*, *suggests*, *is higher in the X condition*, *we observe*. Reserve causal verbs for tested mechanism or RCT-style designs. When the evidence is strong, say it plainly.

## Metric, before anything else

- **Ground truth**: where does it come from — existing labels, or an LLM judge? If a judge, it is a measuring instrument and ships with the validation below.
- **Classification**: name the positive and negative class explicitly.
- **Distribution and skew**: what is the base rate? A 95%-accurate classifier on a 95%-negative set has learned nothing.
- **Known problems with the data**, stated rather than discovered by the reader.
- **Chance correction** where the metric admits it.
- **Blinding**: the judge and the scorer see neither the labels nor which condition a sample came from.
- **Contamination**: say what was checked — canary strings, n-gram or embedding overlap between eval items and any finetuning or few-shot data, prompt reuse across conditions that are later compared — or state plainly that no check was possible.

**Use a deterministic scorer where the construct has an exact surface form; a judge only where meaning can diverge from form.** Refusal prefixes, tool-call schemas, exit codes, canary strings and format-parse failures are string and schema matching, unit-tested, and cheaper and steadier than a model — and establishing that the embarrassingly simple thing works is itself a result (`research.md`). Classification by *meaning* — intent, deception, tone, whether a paraphrase says the same thing — needs a judge, because keyword matching misses paraphrase and over-counts quotation of the searched string. Where both are possible, report the deterministic baseline beside the judge.

**One sample per judge prompt.** The invariant is no cross-sample influence inside a single prompt, not that calls run one at a time — provider-side batch submission is fine, and often the right runner (`experiments.md`).

**A judge ships with its validation**: agreement against a human-labelled gold subset, with `n` and the statistic named — raw agreement, Cohen's κ, whichever, but say which — and paired comparisons run in both orders, or position bias measured and reported. Which judge produced the numbers goes in the provenance.

Analysing monitors and judges themselves — errors, disagreements, comparative advantage — is its own checklist: `results-analysis/monitoring.md`.

## Show the ingredients, not just the conclusions

Reviewers should never have to guess what the model actually saw or produced. For every set of experiments, the page states:

- the research question it answers
- the models, datasets and hyperparameters — **what is held constant and what is varied**
- full prompts and prompt templates, not summaries of them — templates clearly separated from filled-in variables, with the rendered prompt beside the template where useful
- a complete example task or transcript, ideally one positive and one negative
- agent and monitor affordances
- the environment's components and how its state changes
- sample size, and whether anything was resampled
- for a model organism: its setup, training, scaffolding and scoring

Show the **complete** model input and **complete** model output — for monitors, judges and every other model involved, not only the target model.

## Every aggregate is one click from its evidence

Link every aggregate metric back to its underlying examples. "Judge A disagreed with Judge B in 17 cases" links to those 17 cases; "failures clustered around hallucinations" shows the actual failures. An aggregate disconnected from its underlying data is the single worst failure of a results page — this is the most important UX principle for empirical reports.

## Make manual review practical

Good research comes from inspecting concrete examples, not just aggregate metrics. Surface the most salient examples first — largest errors, disagreements, failures, representative successes — and say why each was chosen. Allow jumping directly to any example, and filtering and searching by model, dataset, label, metric, failure mode or split. Reviewing 10–20 examples end to end should be comfortable.

**Tables sort and filter from their headers, like Excel.** Click the label to sort; a drop-down on the header cell selects or unticks values, with counts. Numeric columns band rather than listing every distinct value. Filtering answers comparative questions — "Monitor A false-positive where Monitor B is not" leaves only the relevant rows, each clickable through to the sample.

**Results go in plots; evidence goes in tables you can sort and filter.** These are different objects, and `presentation.md`'s escalate-to-the-plot rule governs only the first — a measured result presented to a reader belongs in a chart. A per-example table is not a presentation of results; it is the inspection surface reviewers filter, sort and click through to reach the underlying sample, and no plot replaces it.

**Transcripts read at a glance.** Distinguish system, developer, user, assistant reasoning, assistant output, tool definitions, tool calls, tool responses and environment messages by consistent colour, typography and hierarchy *and* label — never colour alone. Preserve exact message order, show chat-template special tokens where possible, and bold or highlight the sentences the analysis is about: disagreements, failures, hallucinations, interventions. A reviewer should immediately see the execution flow and where to look.

## Transcript review is sampled, labelled, and rejoinable

Sample deliberately and say how. Look for scorer misconfiguration, eval awareness, refusals, tool errors and format parsing failures — the things aggregate metrics hide by construction.

Label as you go, and export the labels in a form that can be rejoined to the data (JSONL). A review whose conclusions cannot be traced back to labelled examples is an impression.

## Provenance travels with every example

Model and tokenizer or chat template; dataset and split; prompt version and system prompt; sampling parameters (temperature, top-p, max tokens, seed); the judge model, version and prompt hash where a judge produced the number; the endpoint and the date the samples were drawn; and the training hyperparameters where they apply. Every result should be reproducible and attributable without reading the code.

**Hosted models drift under a fixed name, so seeds are not enough.** Conditions being compared are run in the same window, and a changed judge, endpoint or model snapshot is an instrument change, not a result.

**Every eligible sample is in the computation.** A severe performance hit is a reason to paginate or virtualise the *display* — never to quietly shrink the analysed cohort. Anything redacted or withheld is logged with its reason.

**Scan before publishing.** Scripts, transcripts, rendered prompts and configs ship alongside the page, so read them for API keys, internal endpoints, credentials, live attack payloads and personal data before an Artifact goes out. This is the one error class that editing the page afterwards does not undo.

**Outputs are scripts, an Artifact, and figures** — the plotting, report and analysis code alongside the page it produced, not scratch that is thrown away.

## Annotation: commenting is the point of publishing

Manual inspection is iterative, so reviewers must be able to leave notes by highlighting arbitrary text, images or other content. Select text, a comment box appears, type, press Enter, saved. Nothing implicit ever writes a comment.

- **Copy all** — comments must be exportable to the clipboard to paste into Claude Code — and **Delete all** globally; **edit** and **delete** on each comment.
- Comments survive refresh and republish, and never flicker or vanish when text is selected.
- Bookmark or star examples, and record labels and hypotheses while reviewing — then export those the same way as comments, in a form that rejoins to the data.
- Destructive controls confirm through a mechanism that actually fires in the deployment environment; a guard that is silently inert is worse than no guard.

## The results page has a fixed shape

At most **three highlighted claims**. For each: a title that states the claim, a figure supporting it, and explanatory text. Then caveats and next steps, with a note on which look promising and what research question each would answer.

The cap is on what the page *foregrounds*, not on what it reports: **every run condition appears on the page and is linked, including the failures and the nulls** (`experiments.md`). Three claims hiding seven conditions is exactly the failure this shape exists to prevent.

**Each reported finding is labelled *pre-specified* or *discovered in this data*.** Analysis carries more selection pressure than any other stage — slices, metrics, comparisons and re-judgings are all chosen after seeing the numbers — so state how many slices, metrics and comparisons were examined, not only the ones that survived. A discovered finding is a hypothesis: it is not quoted as a result until fresh episodes have tested it.

Per finding: **claim → figure → caption → setup → implications → caveats and uncertainty → next steps.**

This is the page a reviewer opens. It links out to the others: the dataset explainer (tasks, affordances, sampling), the transcript review and labelling page, and the spec proposing what comes next.

## Condition labels come from design, not outcomes

**Which arm, which prompt, which trajectory file produced the sample — that comes from experimental design and never from the quantity being measured.** Assigning a condition from an outcome makes any resulting correlation unfalsifiable, because it is forced by construction.

**Outcome annotation is a different thing, and it is allowed**: describing what a rollout actually did is the point of qualitative analysis. What it must not do is discover the categories and measure their prevalence on the same rollouts — that is HARKing with extra steps. So name a discovery slice up front, build the codebook on it alone, **freeze the codebook**, and estimate prevalence only on episodes that did not form it. The page says which episodes were the discovery slice and which produced the prevalence numbers. A category added after seeing the measurement data restarts this.

Scoring is computed from raw outputs, blind to labels and to condition. Analysis joins the two. **Any stage peeking at another's output is a leak**, and if removing a step would change the reported result while that step depends on the result, it is circular.

**The reviewer test**: before any methodological shortcut, ask whether a reviewer seeing it would find it suspect. If maybe, find the principled approach. There is no "it's just a quick analysis" exception.

## Related

How the page communicates — plots, headings, attention, slides: `presentation.md`. Statistical machinery, nulls and slicing: the `results-artifact` skill. Judge construction and persistence: the `llm-judge` skill. Annotation mechanics and `md2review`: the `artifact-writing` skill. Always-on integrity rules: `claude/rules/research-core.md`.
