---
name: review-paper
description: This skill should be used when the user asks to "review a paper", "critique a manuscript", "give feedback on a draft", "review this write-up", "analyze paper quality", or wants constructive feedback on ML/AI research writing based on Neel Nanda's paper-writing criteria.
---

# Review Paper

Provide constructive critical analysis of ML/AI research papers and drafts. Based on criteria from Neel Nanda's guide on writing ML papers.

## Workflow

1. **Read the work** using a subagent (to avoid context bloat from PDFs/long documents)
2. **Evaluate** against the criteria below
3. **Output structured feedback** with specific, actionable improvements

## Input Handling

For PDFs or long documents, delegate reading to a subagent:
```
Task tool → subagent_type: "general-purpose"
Prompt: "Read this document and return the full text with section structure preserved."
```

For short text pasted directly in conversation, proceed to evaluation.

## Evaluation Criteria

Read **`references/rubric.md`** for the full rubric. It covers 6 areas plus red flags:

1. **Core Narrative Quality** — clear claims, motivation, context, takeaway
2. **Experimental Evidence Rigor** — hypothesis distinction, stats, baselines, ablations
3. **Scientific Integrity** — red-teaming, limitations, reproducibility
4. **Writing and Communication** — abstract, introduction and technical detail; the clarity standard itself is `~/.claude/checklists/writing.md` and the figure, heading and terminology standard is `~/.claude/checklists/presentation.md`
5. **Novelty and Context** — novelty claims, citations, literature integration
6. **Process Indicators** — iterative development, evidence-claim alignment

For each area, note **strengths** and **specific improvements needed**. Skip areas not applicable to the work's current stage. Flag any **red flags** (cherry-picking, weak stats, missing baselines, etc.).

This skill owns the **rubric mechanics** — the six areas, the red flags, and the ranked output below. The writing standard behind area 4 lives in the checklists and is not restated here.

## Output Format

Structure the review as:

```markdown
## Review Summary

[2-3 sentence overall assessment: main strengths and the single most important improvement]

## Strengths

- [Specific strength with reference to section/figure]
- ...

## Areas for Improvement

### Critical (address before submission)
1. [Issue]: [Specific description and suggested fix]

### Important (would significantly strengthen the paper)
1. [Issue]: [Specific description and suggested fix]

### Minor (polish)
1. [Issue]: [Specific description and suggested fix]

## Red Flags

[List any red flags found, or "None identified"]

## Specific Suggestions

[Concrete, actionable suggestions for the most impactful improvements.
Reference specific sections, figures, or claims.]
```

## Reach for a neighbour instead when

- the draft is a **blog post, explainer or report** rather than a paper: the `review-draft` skill, which dispatches `clarity-critic`, `narrative-critic`, `fact-checker` and `red-team` in parallel
- the question is only about **sentences and paragraphs**: `~/.claude/checklists/writing.md`
- the question is about the **page or deck form** — plots, headings, attention, slides: `~/.claude/checklists/presentation.md`
- the evidence rather than the write-up is the worry: `~/.claude/checklists/results-analysis.md`
- the citations may be **fabricated**: the `check-bib-references` skill

## Tone

Adopt the stance of a constructive senior reviewer:
- Be direct and specific, not vague
- Point to exact sections, claims, or figures
- Suggest concrete fixes, not just problems
- Acknowledge genuine strengths
- Prioritize feedback by impact
