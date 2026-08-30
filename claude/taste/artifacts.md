# Artifacts

What makes a page reviewable. Applies to artifacts, reports, slides, papers and Markdown alike — the medium changes the mechanics, not the standard.

## Numbers go in plots. Not prose, not tables, not captions

If a number can sit in prose it can sit in a table; if it can sit in a table it can be a plot. **Escalate to the plot and stop there.** Anything measured belongs in a chart; prose and captions say qualitatively how to read it. Hyperparameters are the exception — they are settings, not results.

- **One plot per claim.** A summary claim may open the page with its own summary plot.
- **A paragraph carries at most one number, and never a confidence interval.** An interval in prose is a figure you have not drawn yet.
- Chunks of numbers are unreadable. Chunks of prose are fine and skimmable — the problem is density of digits, not length of text.
- Conceptual material — system design, UML, experiment design, eval structure — wants a **mermaid diagram**, not a paragraph describing a diagram.

## Headings assert, sections elaborate

Every heading is either a claim, hedged to its evidence, or a question the section answers. Reading only the headings should give the findings. `## Results` becomes `## Assertion Sentences Survive Long Traces`.

State each research question in one sentence, and list them all at the top of the page.

## Say what you mean by the words you use

Terminology section at the top, FAQ at the bottom. Define every term, acronym and metric on first use, in a callout if it carries weight. Use only vocabulary the AI safety and LLM literature uses, and only as it uses it.

Watch the words that sound standard and are not:

- **arm** — what is an arm here, and what are the arms?
- **smoke test** — what does it exercise, and what would it fail to catch?
- **null** — what is the null, and what would the number be under it?
- **gate**, **ceiling**, **floor** — of what, measured how?

Explain any statistical test by name and by what its significance means: Fisher, McNemar, and the rest. Say whether an interval is a 95% CI or a SEM, and how it was obtained. Reserve **P0/P1/P2** for priorities and nothing else.

Avoid buzzwords, corporate jargon and fluffy transitions. Avoid coining terms; when something genuinely is new, explain it the first time.

## Show the ingredients, not just the conclusions

For every set of experiments, the page states:

- the research question it answers
- the models, datasets and hyperparameters — **what is held constant and what is varied**
- full prompts and prompt templates, not summaries of them
- a complete example task or transcript, ideally one positive and one negative
- agent and monitor affordances
- the environment's components and how its state changes
- sample size, and whether anything was resampled
- for a model organism: its setup, training, scaffolding and scoring

**Every aggregate is one click from its evidence.** "Judge A disagreed with Judge B in 17 cases" links to those 17 cases. An aggregate disconnected from its underlying data is the single worst failure of a results page.

Show the **complete** model input and output — for monitors and judges too, not only the target model — with prompt templates separated from filled-in variables.

## Manage attention deliberately

Callouts, bolding and colour draw the eye to what matters; syntax highlighting on code. Collapse transcripts, prompts, logs and JSON by default and lead with the takeaway. Progressive disclosure is the default: high-level first, full detail one click away.

Long or repeated units — samples, episodes, runs — each collapse independently, and the **collapsed row carries its outcome** so the page is skimmable closed.

## Make manual review practical

Surface the most salient examples first — largest errors, disagreements, failures, representative successes — and say why each was chosen. Allow jumping to any example, and filtering by model, dataset, label, metric, failure mode or split. Reviewing 10–20 examples end to end should be comfortable.

**Tables sort and filter from their headers.** Click the label to sort; a caret opens the value menu with counts. Numeric columns band rather than listing every distinct value.

Transcripts distinguish system, developer, user, assistant reasoning, assistant output, tool definitions, tool calls, tool responses and environment messages by consistent colour *and* label — never colour alone. Preserve message order, show chat-template special tokens where possible, and highlight the sentences the analysis is about.

## Slides: the first slide sets what the meeting is about

Two guiding principles behind everything below. **Confusion is a debugging signal** — if someone unfamiliar with the work is confused by a term or a figure, the presentation is what needs fixing. And **clear slides improve the research itself**: making results legible exposes missing controls, wide error bars, weak baselines and unclear hypotheses. That time is research time, not overhead.

**Open with a summary slide.** Where the project stands, what changed this week, the key takeaways from last meeting, and the main experimental outcome stated plainly. Include a simple plot of the headline result. Then say what you want feedback on — especially **the things you are least certain about**, which is what surfaces the right samples for review.

The outcome framing decides the meeting: if the experiments **worked**, discussion goes to sanity checks, controls and extensions; if they **didn't**, it goes to debugging, prompts, data quality and alternative hypotheses. Say which, so nobody has to infer it.

**Agenda next**, sections in priority order, with rough time or slide counts. Meetings are short and the audience needs to know whether to drill in.

**Setup before results.** The prompt (shortened in the deck, full in backup), how each metric is measured, and the models, datasets, interventions and evaluation setup. Show the raw ingredients so people can critique the experiment rather than only the conclusion.

**Most important result first** — not chronological order. Secondary analyses, failed experiments and exploratory work go to backup.

**One message per slide.** If the audience has to hunt for the takeaway, the slide is doing too much; split it.

**Backup slides** for full prompts with the relevant regions highlighted, definitions and methodology, representative examples and model outputs, baselines and controls, scaling curves, training details and loss curves, and failed experiments.

**Anticipate the standard questions**: have an example showing exactly what is measured, be able to justify the prompt and evaluation choices, have a scaling plot ready for "have you tried more data?", and know which simple baseline could invalidate the conclusion.

**End on discussion points**: proposed next experiments, open questions, the feedback you want, and any blockers or resource requests.

**One deck per project** where practical, so previous work is easy to refer back to and the story the paper will eventually tell is rehearsed early.

## Figures are read in seconds or not at all

If a figure takes more than a few seconds to understand, simplify it.

- As large as reasonably possible, and still readable over screen sharing.
- Prefer bar and line charts. Avoid dense heatmaps unless they genuinely communicate better. Avoid diagonal axis labels.
- Label every axis, define every metric, and say whether **higher or lower is better**.
- Put the important values directly on the marks — numbers on bars, on points, on segments.
- Report sample sizes, and show error bars or intervals so it is obvious whether a difference could be noise.
- Roughly three to five colours, and few conditions per slide.

## Provenance travels with every example

Model and tokenizer or chat template; dataset and split; prompt version and system prompt; sampling parameters (temperature, top-p, max tokens, seed); and the training hyperparameters where they apply. Every result should be reproducible and attributable without reading the code.

**Include all samples** unless that causes a severe performance hit.

**Outputs are scripts, an Artifact, and figures** — the plotting, report and analysis code alongside the page it produced, not scratch that is thrown away.

## Commenting is the point of publishing

Select text, a comment box appears, type, press Enter, saved. Nothing implicit ever writes a comment.

- **Copy all** and **Delete all** globally; **edit** and **delete** on each comment.
- Comments survive refresh and republish, and never flicker or vanish when text is selected.
- Destructive controls arm in the page — `confirm`, `alert` and `prompt` are inert in the Artifact viewer, so a button guarded by them silently does nothing.
- No download button: the viewer never grants a page download permission.
- Bookmark or star examples, and record labels and hypotheses while reviewing — then export those the same way as comments, so a review can be rejoined to the data.

## The results page has a fixed shape

Up to **three findings**. For each: a title that states the claim, a figure supporting it, and explanatory text. Then caveats and next steps, with a note on which look promising and what question each would answer.

Per finding: **claim → figure → caption → setup → implications → caveats and uncertainty → next steps.**

This is the page a reviewer opens. It links out to the others: the dataset explainer (tasks, affordances, sampling), the transcript review and labelling page, and the spec proposing what comes next.

## Related

Sentence-level clarity: `writing.md`. Statistical machinery, nulls and chance correction: the `results-artifact` skill. Chart style: `house-plots` for papers, the built-in `dataviz` for artifact pages. Page mechanics, the annotation layer and `md2review`: the `artifact-writing` skill.
