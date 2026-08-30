# Results Analysis

Turning a finished run into something a reader can check and inspect — the standard for evidence, review and annotation. The core principle: **optimise for manual inspection.** A human should be able to reconstruct exactly what happened without reading code — read transcripts, label them, and rebuild the full input and output of any example. Domain subskills live in `results-analysis/`: `monitoring.md` today, `jlens.md` and `sandbagging.md` beside it.

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

**Transcripts read at a glance.** Distinguish system, developer, user, assistant reasoning, assistant output, tool definitions, tool calls, tool responses and environment messages by consistent colour, typography and hierarchy *and* label — never colour alone. Preserve exact message order, show chat-template special tokens where possible, and bold or highlight the sentences the analysis is about: disagreements, failures, hallucinations, interventions. A reviewer should immediately see the execution flow and where to look.

## Transcript review is sampled, labelled, and rejoinable

Sample deliberately and say how. Look for scorer misconfiguration, eval awareness, refusals, tool errors and format parsing failures — the things aggregate metrics hide by construction.

Label as you go, and export the labels in a form that can be rejoined to the data (JSONL). A review whose conclusions cannot be traced back to labelled examples is an impression.

## Provenance travels with every example

Model and tokenizer or chat template; dataset and split; prompt version and system prompt; sampling parameters (temperature, top-p, max tokens, seed); and the training hyperparameters where they apply. Every result should be reproducible and attributable without reading the code.

**Include all samples** unless that causes a severe performance hit.

**Outputs are scripts, an Artifact, and figures** — the plotting, report and analysis code alongside the page it produced, not scratch that is thrown away.

## Annotation: commenting is the point of publishing

Manual inspection is iterative, so reviewers must be able to leave notes by highlighting arbitrary text, images or other content. Select text, a comment box appears, type, press Enter, saved. Nothing implicit ever writes a comment.

- **Copy all** — comments must be exportable to the clipboard to paste into Claude Code — and **Delete all** globally; **edit** and **delete** on each comment.
- Comments survive refresh and republish, and never flicker or vanish when text is selected. Artifacts are stateless, so preserve them in local storage; the viewer never grants a page download permission, so copy-all plus local storage is the mechanism, not a download button.
- Bookmark or star examples, and record labels and hypotheses while reviewing — then export those the same way as comments, so a review can be rejoined to the data.
- Destructive controls arm in the page — `confirm`, `alert` and `prompt` are inert in the Artifact viewer, so a button guarded by them silently does nothing.

## The results page has a fixed shape

Up to **three findings**. For each: a title that states the claim, a figure supporting it, and explanatory text. Then caveats and next steps, with a note on which look promising and what research question each would answer.

Per finding: **claim → figure → caption → setup → implications → caveats and uncertainty → next steps.**

This is the page a reviewer opens. It links out to the others: the dataset explainer (tasks, affordances, sampling), the transcript review and labelling page, and the spec proposing what comes next.

## Separation of concerns

Labelling comes from experimental design, never from outcomes. Scoring is computed from raw outputs, blind to labels. Analysis joins the two. **Any stage peeking at another's output is a leak**, and if removing a step would change the reported result while that step depends on the result, it is circular.

**The reviewer test**: before any methodological shortcut, ask whether a reviewer seeing it would find it suspect. If maybe, find the principled approach. There is no "it's just a quick analysis" exception.

## Related

How the page communicates — plots, headings, attention, slides: `presentation.md`. Statistical machinery, nulls and slicing: the `results-artifact` skill. Judge construction and persistence: the `llm-judge` skill. Annotation mechanics and `md2review`: the `artifact-writing` skill. Always-on integrity rules: `claude/rules/research-core.md`.
