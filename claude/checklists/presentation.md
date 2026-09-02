# Presentation

How research is presented — documents, slides, artifact pages and dashboards. The unit is **claim + figure + elaboration**, and the composition test is reading only the headings and first sentences: that alone should carry the findings. Sentence and paragraph mechanics live in `writing.md`; what a results page must *show* — evidence, provenance, review affordances — lives in `results-analysis.md`. This file is about form: efficient information transfer to an audience of busy collaborators, mentors and reviewers with only a few minutes to understand the work.

The file doubles as a review pass: judge each item **Good / Needs improvement / Missing**, and for every problem say why it matters and suggest a concrete improvement — as an experienced empirical researcher seeing the work for the first time, without redesigning the visual style.

## Legibility is research time, not overhead

*Advice, not checklist items — neither can be judged from a draft, and both are why the rest of the file is worth applying.*

Two principles govern everything below. **Confusion is a debugging signal** — if someone unfamiliar with the latest work is confused by a term or a figure, the presentation is what needs fixing, not the audience. And **clear slides improve the research itself**: making results legible exposes missing controls, large error bars, weak baselines and unclear hypotheses. Time spent here is research time.

## Plots carry pages, tables carry papers

On artifact pages, dashboards and slides, escalate by what the reader has to do with the number. **A comparison or a distribution goes in a plot** — escalate it and stop there, because the failure this prevents is a dense chunk of digits inside a sentence, where the reader has to hold every value in their head to compare them. A single headline number is stated once, on the figure or in its caption. **Values a reader looks up exactly stay in a table** — a plot read for exact values is chartjunk. Prose and captions then say qualitatively how to read the chart. Hyperparameters are settings, not results, and go wherever they are easiest to check.

Papers and reports keep their numerical tables: venue norms make the main-results table and the ablation table the thing reviewers cite, so **keep both**, with intervals and sample sizes in the cells, and let the figures carry the comparisons a reader should read as positions on an axis.

The rule governs how **results are presented**. It does not govern the per-example tables a reader uses to **inspect evidence** — one row per sample, sorted and filtered from the headers — which are a `results-analysis.md` affordance. Results go in plots; evidence goes in tables you can sort and filter.

**Where the sources disagree: the two-bar chart.** Tufte's rule 22, as the `tufte-data-viz` skill carries it, holds that a chart of two bars is almost always worse than a sentence; the escalate-and-stop rule above sends any comparison to a plot. Both are stated rather than averaged, because they optimise for different things — Tufte for ink spent per number, this file for a reader comparing conditions across a page full of them. Judge it on what the two values are: the whole finding, quoted once, is a sentence, while one comparison among several a reader will make is a plot, so that every comparison on the page reads the same way.

- **One plot per claim.** A summary claim may open the page with its own summary plot.
- **A paragraph carries at most one measured quantity, and that quantity carries its interval and its n.** An abstract's headline effect is exactly this case, and it keeps its uncertainty. A second measured quantity in the same paragraph is a figure or a table you have not drawn yet.
- Chunks of prose are fine and skimmable, so length is not what is being policed here — the problem is density of digits.
- Conceptual material — system design, UML, experiment design, eval structure — wants a **mermaid diagram**, not a paragraph describing a diagram.

## Headings assert, sections elaborate

Every heading is either a claim, hedged to its evidence, or a question the section answers. Reading only the headings should give the findings. `## Results` becomes `## Token positions from assertion sentences are more useful for monitoring`.

State each research question in one sentence, and list them all at the top of the page.

## Say what you mean by the words you use

Terminology section at the top, FAQ at the bottom. Define every term, acronym and metric on first use — never use undefined jargon — in a callout if it carries weight. Use only vocabulary the AI safety and LLM literature uses, and only as it uses it — the reference set is ICML, ICLR and NeurIPS, the Anthropic Alignment Science blog, METR, OpenAI Alignment blog, Apollo Research, Redwood, GDM Safety (and potentially LessWrong/arXiV), so "common in the literature" is checkable rather than a matter of taste.

Watch the words that sound standard and are not:

- **arm** — what is an arm here, and what are the arms?
- **smoke test** — what does it exercise, and what would it fail to catch?
- **null** — what is the null, and what would the number be under it?
- **gate**, **ceiling**, **floor**, **cap** — of what, measured how?

Placement, for anything the reader has to know to read a number: the name of the statistical test and the definition of the interval sit **adjacent to the number they describe** — in the caption, the cell or the sentence — not in a methods section the reader has to go and find. What the test and the interval must say for themselves is `results-analysis.md`. Reserve **P0/P1/P2** for priorities and nothing else.

Avoid buzzwords, corporate jargon and fluffy transitions. Avoid coining terms; when something genuinely is new, explain it the first time.

## Reports lead each bullet with a bolded takeaway

In reports, prefer bullet points with clear signposting over long-running paragraphs: lead each bullet with a **bolded takeaway** so the report is scannable, one idea per bullet, and split any bullet that turns into a paragraph. Reviewers skim — walls of prose with undefined terms force re-reading and hide the findings.

This deliberately pulls against `writing.md`, which says chains of "because A, therefore B" belong in prose because the connectives carry the logic. Both hold, for different genres: **reports for skimming reviewers lead with bolded bullet takeaways; papers and argumentative prose carry the logic in sentences.** The dividing question is whether the reader is evaluating findings or following an argument.

## Manage attention deliberately

Callouts, bolding and colour draw the eye to what matters; syntax highlighting on code. Show the high-level takeaway first; collapse transcripts, prompts, logs and JSON by default, expandable on demand. Progressive disclosure is the default — full transparency without cognitive overload.

Long or repeated units — samples, episodes, runs — each collapse independently, and the **collapsed row carries its outcome** so the page is skimmable closed.

Pages are explorable, not just readable: a table of contents with jump links, cross-links between related analyses and examples, and important context kept visible while scrolling long transcripts.

## Slides: the first slide sets what the meeting is about

**Open with a summary slide.** Where the project stands and this week's progress, the key takeaways from the previous meeting, and the main experimental outcome stated plainly, with a simple plot of the headline result where possible. Then the discussion points or decisions you want feedback on — especially **the things you are least certain about**, which is what surfaces the right samples and results for review. The audience manages many projects; the first slide reminds them where this one stands and what to think about while you talk.

The outcome framing decides the meeting: if the experiments **worked**, discussion goes to sanity checks, controls and extensions; if they **didn't**, it goes to debugging, prompts, data quality and alternative hypotheses. Say which, so nobody has to infer it.

**Include an agenda.** Major sections in priority order, with rough time or slide counts where useful. Meetings are short — an agenda lets the audience calibrate whether to drill in or move on, and puts the highest-priority topics first.

**Explain experiments before results.** Describe the setup clearly: always include the prompt — shortened in the main deck, full in backup — say exactly how each metric is measured, and name the models, datasets, interventions and evaluation setup. Show the *raw ingredients* so people can critique the experiment, not just the conclusions.

**Show the most important results first** — the strongest, most interesting or most decision-relevant, not chronological order just because that is how the experiments were run. Secondary analyses, failed experiments and exploratory results go to backup. You rarely have time to discuss everything; spend discussion time on the experiments worth discussing.

**Keep slides simple: one main message per slide.** Avoid too many words, plots or ideas per slide; split overloaded slides. If the audience has to search for the takeaway, the slide is trying to do too much.

**Prepare backup slides** for likely questions: full prompts with the relevant regions highlighted; definitions and methodology; representative examples and model outputs; baselines and controls; scaling curves; training details, hyperparameters and loss curves; failed experiments and additional plots. The main deck stays simple while detailed questions get answered immediately.

**Anticipate common questions.** Have examples showing exactly what is measured, be ready to justify prompts and evaluation choices, have a scaling plot ready for "have you tried more data?", and know which simple baselines could invalidate the conclusions.

**End with concrete discussion points**: proposed next experiments, open questions, the feedback you want stated clearly, and any blockers or resource requests.

**Tell a consistent project story.** One slide deck per project where practical, so previous work is easy to refer back to and the evolving story the eventual paper will tell is presented regularly. Iterating on the story early keeps collaborators aligned and makes the paper substantially easier to write.

## Figures are read in seconds or not at all

If a figure takes more than a few seconds to understand, simplify it.

- **Readability**: as large as reasonably possible, and still readable over screen sharing.
- **Simplicity**: prefer simple bar charts and line plots; avoid complicated visualizations such as dense heatmaps unless they communicate substantially better; avoid diagonal axis labels.
- **Labels**: label every axis, define every metric, and say whether **higher or lower is better**.
- **Numbers and uncertainty**: put important values directly on the marks — numbers on bars, points, segments. Report sample sizes, and include error bars or confidence intervals so it is obvious whether a difference could be noise.
- **Visual complexity**: roughly three to five colours unless there is a good reason not to, and few models or conditions per slide.

## Related

Sentence and paragraph mechanics: `writing.md`. What a results page must show, and the shape of a finding: `results-analysis.md`. Chart style: `house-plots` for papers, the built-in `dataviz` for artifact pages. Slide tooling: the `slidev` skill. Page mechanics, the annotation layer and `md2artifact`: the `artifact-writing` skill.
