---
name: clear-writing
description: The clarity standard for papers, reports, artifacts, specs and updates — paragraph structure, sentence mechanics, claim calibration, and the LLM tics to cut. Use when drafting or revising anything a reader must follow.
---

# Clear Writing

The standard lives in **`~/.claude/checklists/writing.md`**. Read it now; it is the content, and this file only routes to it.

It covers PEEL as the paragraph unit and the test that the first sentences alone must carry the argument; Gopen & Swan's topic and stress positions, subject-verb proximity and action-in-the-verb; McEnerney on what an opening must destabilise and whose problem it is; Nanda on hedging to the evidence class and where editing time is worth spending; Foerster on attribution and cutting a third; Pinker on the curse of knowledge and rereading cold. Sources are cited, secondary ones are marked, and the two places the sources contradict each other are stated rather than averaged.

## Reach for a neighbour instead when

- the question is about a **page or deck** rather than its sentences — plots, headings, attention, slides: `~/.claude/checklists/presentation.md`
- a draft is finished and the risk is being **misread**: the `reduce-ambiguity` skill
- you want critics run over a draft: the `review-draft` skill, which dispatches `clarity-critic`, `narrative-critic`, `red-team` and `fact-checker`
- the writing is a **results** page: `~/.claude/checklists/results-analysis.md` for its shape and evidence standards
- numbers are involved: they belong in plots, not prose or tables — `house-plots` for papers, the built-in `dataviz` for artifact pages

## Why this file is thin

Five checklists hold the content; skills route to them. Restating a standard in every skill that touches it is how five skills came to say overlapping things about clarity, with edits landing in one copy and not the others. See `~/.claude/checklists/README.md`.
