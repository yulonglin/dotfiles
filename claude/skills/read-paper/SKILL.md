---
name: read-paper
description: Read a research paper or technical post with critical rigor — what the authors actually claim, which methodological choices drive the result, how strong the evidence is, and where the paper sits against related work. Use when reading a PDF or arXiv link, doing a literature review, evaluating a method or a claim, comparing approaches across papers, when the user shares a paper URL or file, or when explaining a concept that requires reading the source ("explain GRPO", "what is constitutional AI", "how does deliberative alignment work").
---

# Reading A Paper

Analysis is grounded in the text or it is not analysis. The three rules below are the whole job; the frameworks are references you load when you need the phrasing.

**Never fabricate.** If something is not explicitly in the paper, say so — "the paper doesn't specify", "this isn't mentioned". A plausible-sounding detail you supplied yourself is the failure mode this skill exists to prevent.

**Source everything.** Cite the section, figure or quote: "According to Section 3.2…", "the authors state in the abstract that…". A claim without a locator cannot be checked, and an uncheckable summary is worth less than the abstract.

**Say how sure you are, and why.** "I'm ~80% confident the authors meant…", "the paper is unclear here; possible readings are…". Hedge to the evidence class rather than uniformly — the standard for that is in `~/.claude/checklists/writing.md`.

## Analyse four things, in this order

1. **Methodological decisions** — what did they choose, and what did the choice buy them?
2. **Result sensitivity** — what moves the numbers, and what survives?
3. **Evidence strength** — do the experiments support the claim actually made, or a weaker one?
4. **Positioning** — what does this add over the work it cites?

`~/.claude/skills/read-paper/references/analysis-framework.md` has worked examples and example phrasings for each. `~/.claude/skills/read-paper/references/response-template.md` has the response structure and the quality safeguards.

## Close with what the reader can act on

The main points; the key uncertainties; the interesting facts or opinions; and the good questions to put to the authors. Present mathematics in LaTeX.

## Reach for a neighbour instead when

- the citations themselves are the worry — fabricated or misattributed references: the `check-bib-references` skill
- you are **reviewing a draft** rather than reading a published paper: the `review-paper` skill
- the job is a **sweep of what is new** across labs rather than one paper: the `sweep-ai-safety` skill
- you are **writing** the paper: `~/.claude/checklists/writing.md` for the prose, `~/.claude/checklists/presentation.md` for the shape
- the paper suggests an experiment you want to run: `~/.claude/checklists/research.md`
