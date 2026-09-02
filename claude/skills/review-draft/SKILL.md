---
name: review-draft
description: Run the critic panel over a draft and merge what comes back — clarity, narrative, facts, red-team, in parallel, each writing a feedback file. Use on "review my draft", "critique this post", "give me feedback on this write-up", "run the critics", "tear this apart", or before publishing a blog post, LessWrong post, explainer, report or announcement. Also use when only one lens is wanted (just clarity, just fact-checking), since this skill dispatches the individual critics too.
---

# Review Draft

This skill owns the **dispatch and the merge**: which critics run, what each is told, where the feedback lands, and how the findings come back as one ranked list. It does not carry the writing standard.

## The standard the critics judge against

Sentence and paragraph clarity is **`~/.claude/checklists/writing.md`**; the form of a page, deck or report — plots, headings, terminology, attention — is **`~/.claude/checklists/presentation.md`**. Name the relevant one in the clarity and narrative prompts so both judge against the same standard rather than their own priors, and read it yourself before ranking the merged findings. The fact-checker and red-team judge against sources and counterexamples instead, so they do not get the checklist.

**LLM cliches are not a separate critic.** There is no humanizer — cliche detection is the *Cut the LLM tics* section of `~/.claude/checklists/writing.md`, and the clarity critic covers it because it already reads that file. Name the section in the clarity prompt when a draft was LLM-drafted and the tics are the main worry.

## Arguments

Parse from provided arguments:
- **File path**: First non-flag argument (required)
- **--critics=**: Comma-separated list of critics to run (default: all four) — `clarity`, `narrative`, `facts`, `redteam`
- **--sensitivity=**: `conservative|balanced|aggressive` (default: balanced)

## Workflow

1. **Parse arguments** from above
2. **Validate file exists** — error if not found
3. **Ask for target audience** using AskUserQuestion (required for all critics; never inferred)
4. **Create feedback directory** — ensure `feedback/` exists in the draft's directory
5. **Dispatch the selected critics in parallel** using the Task tool
6. **Merge and report** — one ranked list, not four summaries

## Agent Dispatch

Launch agents **in parallel** in a single message. These are local agents, so `subagent_type` is the bare name with no plugin prefix.

| Critic | subagent_type | Output File |
|--------|---------------|-------------|
| clarity | `clarity-critic` | `feedback/{name}_clarity.md` |
| narrative | `narrative-critic` | `feedback/{name}_narrative.md` |
| facts | `fact-checker` | `feedback/{name}_facts.md` |
| redteam | `red-team` | `feedback/{name}_redteam.md` |

Where `{name}` is the draft filename without extension.

**Agent prompt template**:
```
Review the draft at {file_path} for {audience}.
Sensitivity: {sensitivity}
[clarity and narrative critics only] The standard is ~/.claude/checklists/writing.md, plus
~/.claude/checklists/presentation.md if the draft is a page, deck or report. Read it before
you start and judge against it.
Write feedback to feedback/{name}_{type}.md
```

## Merge And Report

Read the feedback files rather than relaying each agent's return message, then collapse them into one list. Critics overlap by design — a buried lede shows up as clarity and as narrative — so **merge duplicates into a single entry naming both critics** instead of reporting it twice, and rank by what it costs the reader, not by which critic spoke loudest. Disagreements between critics are kept and attributed, never averaged.

```
## Review Complete

Feedback written to `feedback/`:
{list files created}

**Start with**: {highest-cost issue across all critics, with the file:line it sits at}

{3-5 further issues, ranked, each tagged with the critic(s) that raised it}
```

## Error Handling

| Scenario | Response |
|----------|----------|
| File not found | Error with clear message |
| Empty file | "Nothing to review" |
| >5000 words | Proceed with truncation warning |
| `feedback/` missing | Create it |
| Agent fails | Report the failure, continue with the others |

## Examples

```
/review-draft paper.md                              # All 4 critics
/review-draft paper.md --critics=clarity            # Just clarity
/review-draft paper.md --critics=clarity,facts      # Clarity + facts
/review-draft paper.md --sensitivity=aggressive     # Stricter review
```

## Reach for a neighbour instead when

- you are **writing** rather than reviewing: the `clear-writing` skill, which routes to the same clarity standard
- the draft is an **ML paper or manuscript** and you want the Nanda rubric rather than a critic panel: the `review-paper` skill
- the risk is the draft being **misread** rather than being weak: the `reduce-ambiguity` skill
- the draft is a **results page** and the question is whether the evidence holds: `~/.claude/checklists/results-analysis.md`
- the citations are the worry: `check-bib-references` for BibTeX, `check-prose-claims` for stats and quotes in prose

## Why this file is thin

Five checklists hold the content; skills route to them. Restating a standard in every skill that touches it is how five skills came to say overlapping things about clarity, with edits landing in one copy and not the others. See `~/.claude/checklists/README.md`.
