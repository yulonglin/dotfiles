# Empirical Research Checklist for Presentations, Plots, Reports and Dashboards

#prompt/meta/presentation
#models/anthropic/fable-5

Review the artifact (slides, PDF, Markdown, HTML) as an experienced empirical researcher seeing it for the first time. Do **not** redesign the visual style. Optimize for clarity, readability, transparency, scientific communication, ease of discussion, and efficient information transfer.

Assume the audience is busy collaborators, mentors, or reviewers with only a few minutes to understand the work.

**For each item, mark:** Good / Needs improvement / Missing
**For every problem:** explain why it matters and suggest a concrete improvement.

**Two guiding principles:**

1. **Confusion is a debugging signal.** If someone unfamiliar with the latest work gets confused by a term or figure, the presentation needs fixing.
2. **Clear slides improve the research itself.** Making results legible exposes missing controls, large error bars, weak baselines, and unclear hypotheses. Time spent here is research time, not overhead.

## Part 1: Presentations

### Summary slide sets the frame

Begin with a summary of the project and this week's progress. Remind the audience of key takeaways from the previous meeting. Clearly state the main experimental outcome. State the discussion points or decisions you want feedback on — in particular, the things you are least certain about, which helps surface particular samples or results for review. Include a simple plot of the main result where possible.

**Why:** Your audience manages many projects. The first slide reminds them where the project stands and what to think about during the presentation. If experiments **worked**, discussion shifts to sanity checks, controls, and extensions. If they **didn't**, discussion shifts to debugging, prompts, data quality, and alternative hypotheses.

### Include an agenda

List major sections in order of priority. Indicate roughly how much time or how many slides per section, when useful.

**Why:** Meetings are short. An agenda lets the audience calibrate whether to drill in or move on, and ensures the highest-priority topics get discussed first.

### Explain experiments before results

Clearly describe the experimental setup. Always include the prompt — shortened in the main deck, full prompt in backup. Explain exactly how each metric is measured. Name the models, datasets, interventions, and evaluation setup.

**Why:** Show the *raw ingredients* that produced the results. People should be able to critique the experiment, not just the conclusions.

### Make figures easy to understand

**Readability.** Make plots as large as reasonably possible. Ensure figures remain readable over screen sharing.

**Simplicity.** Prefer simple bar charts or line plots. Avoid complicated visualizations such as dense heatmaps unless they communicate substantially better. Avoid diagonal axis labels where possible.

**Labels.** Label every axis. Clearly define every metric. Indicate whether higher or lower is better.

**Numbers and uncertainty.** Show important numerical values directly on the plot — numbers on the bars in a bar chart, or points in a line chart, or segments in a pie chart. Report sample sizes. Include error bars or confidence intervals, and make it obvious whether differences could be noise.

**Visual complexity.** Use roughly 3 to 5 colors unless there's a good reason not to. Show only a small number of models or conditions per slide.

**Rule of thumb:** If a figure takes more than a few seconds to understand, simplify it.

### Show the most important results first

Start with the strongest, most interesting, or most decision-relevant result. Don't present chronologically just because that's how experiments were run. Move secondary analyses, failed experiments, and exploratory results to backup slides.

**Why:** You rarely have time to discuss everything. Spend discussion time on the experiments worth discussing.

### Keep slides simple

One main message per slide. Avoid too many words, plots, or ideas per slide. Split overloaded slides.

**Why:** If the audience has to search for the takeaway, the slide is trying to do too much.

### Prepare backup slides

Cover likely questions with backups for: full prompts, with highlighted regions where useful; definitions and methodology; representative examples and example model outputs; baselines and controls; scaling curves; training details, hyperparameters, loss curves; failed experiments and additional plots.

**Why:** Keep the main deck simple while making it easy to answer detailed questions immediately.

### Anticipate common questions

Have examples that show exactly what you're measuring. Be ready to justify prompts and evaluation choices. Be ready to answer "Have you tried more data?" — include scaling plots when relevant. Think about simple baselines that could invalidate your conclusions.

### End with concrete discussion points

Summarize proposed next experiments. List open questions. Clearly state the feedback you want. Mention blockers or resource requests.

### Tell a consistent project story

Maintain one slide deck per project where practical. Make it easy to refer back to previous work. Regularly present the evolving story you expect the eventual paper to tell.

**Why:** Iterating on the story early keeps collaborators aligned and makes the paper substantially easier to write.

## Part 2: Research Reports (HTML, Markdown, PDF)

For reports, focus less on typography and more on making experiments easy to inspect, verify, and debug.

**Core principle: optimize for manual inspection.** A human should be able to reconstruct exactly what happened without reading code — read transcripts, label them, and reconstruct the full input/output for any example.

### Prose style and terminology

Prefer bullet points with clear signposting over long-running paragraphs. Lead each bullet with a bolded takeaway so the report is scannable. Define every term, acronym, and metric on first use — never use undefined jargon. One idea per bullet; split bullets that turn into paragraphs.

**Why:** Reviewers skim. Walls of prose with undefined terms force re-reading and hide the actual findings.

### Evidence over summaries

Link every aggregate metric back to its underlying examples. Every claim should be one click from its evidence: "Judge A disagreed with Judge B in 17 cases" must link to those 17 cases; "failures clustered around hallucinations" must show the actual failures.

**Why:** Aggregate statistics should never become disconnected from the underlying data. This is the single most important UX principle for empirical reports.

### Manual review

Make it easy to inspect individual examples. Surface the most salient examples first — largest errors, disagreements, failures, representative successes — and explain why each was selected. Allow jumping directly to any example. Allow filtering and searching by model, dataset, label, metric, failure mode, split. Make it practical to review at least 10 to 20 examples end to end.

**Why:** Good research comes from inspecting concrete examples, not just aggregate metrics.

### Transcript readability

Visually distinguish, with consistent colors, typography and hierarchy: system messages, developer messages, user messages, assistant CoT, assistant outputs, tool definitions, tool calls, tool responses, environment and observation messages. Show chat-template special tokens where possible. Preserve the exact ordering of messages. Bold or highlight important sentences, disagreements, failures, hallucinations, and interventions.

**Why:** Reviewers should immediately understand the execution flow and where to look.

### Inputs and outputs

Show the **complete** model input and **complete** model output — and the same for monitors and any other models involved. Clearly separate prompt templates from filled-in variables; show the rendered prompt alongside the template when useful.

**Why:** Reviewers should never have to guess what the model actually saw or produced.

### Experimental provenance

For every example, show: model and tokenizer or chat template; dataset and split; prompt version and system prompt; sampling parameters (temperature, top-p, max tokens, seed); relevant training hyperparameters where applicable.

**Why:** Every result should be reproducible and attributable.

### Annotation

Allow reviewers to leave notes and comments by highlighting arbitrary text, images or other content in Artifacts. Allow bookmarking or starring examples. Allow recording labels or hypotheses during review. Because Artifacts are currently stateless, it must be possible to copy all comments to the clipboard, to paste into Claude Code. When the Artifact is updated, force download the comments, or preserve them in local storage. The same applies to labels and notes for each sample.

**Why:** Manual inspection is iterative.

### Navigation and progressive disclosure

Include a table of contents with jump links. Cross-link related analyses and examples. Keep important context visible while scrolling long transcripts. Show the high-level takeaway first; collapse lengthy transcripts, prompts, logs, and JSON by default, expandable on demand.

**Why:** Reports should be explorable, not just readable — full transparency without cognitive overload.
