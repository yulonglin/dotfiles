---
name: research-presentation
description: The standard for how research is presented — structuring a research presentation, slide deck, research update, mentor or team meeting, a report or an artifact page. Covers the summary slide that opens the meeting, the agenda, explicit success/failure framing, explaining experiments before results, backup slides for likely questions, headings that assert rather than label, numbers belonging in plots rather than prose or tables, terminology defined on first use, attention managed with callouts and progressive disclosure, and figures that read in seconds. Use when building, structuring or critiquing slides, a research update, a findings page, or a figure destined for a deck.
---

# Research Presentation

The standard lives in **`~/.claude/checklists/presentation.md`**. Read it now; it is the content, and this file only routes to it.

It covers the unit of claim + figure + elaboration and the composition test of reading only headings and first sentences; numbers escalating to a plot and stopping there; headings that assert; terminology, undefined jargon and the words that sound standard and are not; bolded bullet takeaways for skimming reviewers, and where that pulls against `writing.md`; attention management, progressive disclosure and collapsed rows that carry their outcome; the slide sequence — summary slide, agenda, experiments before results, most important results first, one message per slide, backup slides, concrete discussion points, one consistent project story; and what makes a figure readable in seconds. The file doubles as a review pass: judge each item Good / Needs improvement / Missing, and for every problem say why it matters and propose a concrete improvement.

Critique and improve proactively whenever slides, a research update or a plot come past — do not wait to be asked.

## Local references the checklist does not carry

- **`references/paper-figures.md`** — publication figures for ICML/NeurIPS/ICLR: single- and double-column sizes in inches, font sizes that survive 50% scaling, `text.usetex` integration, PDF export and the pre-submission checklist (vector, embedded fonts, grayscale-distinguishable). Load this only for a paper figure, never for slides. It carries no colours of its own — every hex comes from `house-plots` and `lib/plotting/palette.py`.
- **`references/templates.md`** — the research-update email skeleton (outcome → tried → result against baseline → decision needed → next steps) and the matching slide skeleton.

`GUIDE.md`, `references/common-mistakes.md` and `references/visualization-guide.md` predate the checklist and now restate it; prefer `~/.claude/checklists/presentation.md` over all three.

## An exported deck can eat the whole context window

Never read an exported PDF or a long deck in main context. Delegate it: a subagent reads the PDF and reports the issues, and the `slidev` skill delegates its own PDF analysis the same way. Creating slides directly in main context is fine; reviewing the export is not.

## Reach for a neighbour instead when

- the question is **Slidev tooling** — building the deck, export, overflow, or a single slide that is cut off or blank: the `slidev` skill
- the question is **whether the evidence holds** rather than how it looks — intervals, nulls, chance correction, slicing, provenance: `~/.claude/checklists/results-analysis.md`
- the question is about **sentences and paragraphs** rather than the page or deck: `~/.claude/checklists/writing.md`
- you are **drawing the chart**: `house-plots` for matplotlib in papers and decks, the built-in `dataviz` for native SVG on an artifact page
- you are building the **page** — transcripts, collapsible units, the annotation layer, `md2review`: the `artifact-writing` skill
- the draft is finished and the risk is being **misread**: the `reduce-ambiguity` skill

## Why this file is thin

Five checklists hold the content; skills route to them. Restating a standard in every skill that touches it is how five skills came to say overlapping things about clarity, with edits landing in one copy and not the others. See `~/.claude/checklists/README.md`.
