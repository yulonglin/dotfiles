# `/improve` Skill Design

**Date:** 2026-04-01
**Status:** Draft v2
**Plugin:** `core` (ai-safety-plugins) — foundational, used across all profiles

## Purpose

A unified skill that takes any content (plan, message, code, writing), generates evaluation criteria specific to that content, scores it, and produces an improved version. The critique is implicit — the deliverable is the improved output with a visible scorecard.

## Core Flow

```
1. Parse input (file path, inline content, or current context)
2. Detect content type (or use --type override)
3. Generate 3-5 evaluation axes tailored to THIS content
4. Dispatch appropriate critics (per content type) with axes + scoring rubric
5. Aggregate scores, flag disagreements
6. Rewrite content targeting weakest axes
7. Present: improved version + scorecard (+ before/after if --rescore)
```

## Input Modes

| Mode | Trigger | Example |
|------|---------|---------|
| **File** | First arg is a file path | `/improve plans/my-plan.md` |
| **Inline** | Content in conversation context | `/improve` after pasting text |
| **Context** | No args, no inline content | `/improve` — improves active plan or last substantial content |

**Context mode resolution order:** Active plan in session → last file written/edited → last user-pasted content block. If nothing found, ask the user what to improve.

## Arguments

- **File path** — first non-flag argument (optional)
- **--context="..."** — additional context for criteria generation (e.g., "cold email to a hiring manager")
- **--axes=N** — number of evaluation axes (default: 5, range: 3-7)
- **--rescore** — re-score improved version, show before/after comparison
- **--type=plan|message|writing|code** — force content type (auto-detected by default)

## Content Type Detection

| Signal | Type | Confidence |
|--------|------|------------|
| File in `plans/` or `specs/`, or has "## Steps"/"## Implementation" structure | `plan` | High |
| File has code extension (`.py`, `.ts`, `.rs`, `.go`, etc.) | `code` | High |
| Short (<500 words) + greeting/sign-off or conversational tone | `message` | Medium |
| Long prose, `.md` files, drafts, papers | `writing` | Medium |

**When confidence is Medium**, state the detected type and proceed unless the user corrects. Don't ask — act and let the user override with `--type` if wrong.

## Criteria Generation

Inspired by llm-council's `stage2a_select_axes`. Runs before any critique.

**Prompt template:**
```
Analyze this {content_type} and its purpose. Generate exactly {N} evaluation axes, ranked by importance for THIS specific content.

Content:
{content}

Context (if provided):
{user_context}

For each axis, provide (in priority order — most important first):
- Priority: 1 = most important for this content's goals
- Name: short label (e.g., "Migration Safety")
- Weight: 1-3 (1 = nice-to-have, 2 = important, 3 = critical)
- Description: one sentence defining what 5/5 looks like
- Why this axis matters for THIS specific content

The axes must be specific to this content's goals, not generic quality metrics.
Rank by: which axis, if weak, would most undermine this content's purpose?
Example: for a plan about "migrate auth to JWT", good axes are "Token Lifecycle Coverage", "Rollback Strategy" — NOT "Clarity", "Completeness".
```

**Priority vs Weight:**
- **Priority** (order) = which weak axes to fix first during improvement
- **Weight** (1-3) = how much each axis contributes to the overall score

Usually correlated, but not always — a high-weight axis that scores 5/5 doesn't need fixing despite its weight. The improvement step targets the highest-priority weak axes first; the weighted overall score reflects true quality.

**Fallback defaults** (if generation fails or no context available):

| Type | Default Axes |
|------|-------------|
| Plan | Feasibility, Completeness, Sequencing, Risk Mitigation, Clarity |
| Message | Clarity, Friendliness, Persuasiveness, Conciseness, Call-to-Action |
| Writing | Clarity, Argument Structure, Evidence Quality, Conciseness, Engagement |
| Code | Correctness, Readability, Performance, Error Handling, Simplicity |

## Scoring Rubric

All critics receive this rubric with the axes:

```
Score each axis 1-5:
1 = Fundamentally broken or missing
2 = Present but weak, major issues
3 = Adequate, some issues
4 = Strong, minor issues only
5 = Excellent, no meaningful improvements possible

For each axis, provide:
- Score (integer 1-5)
- One-sentence justification
- Specific suggestion for improvement (if score < 5)
```

## Per-Type Routing

### Plan

**Critics** (3 agents in parallel):

| Agent | Role | Prompt Focus |
|-------|------|-------------|
| `code:plan-critic` (Codex) | Implementation feasibility | "Score this plan's axes focusing on: Will this actually work when coded? Missing error paths? Sequencing gaps? Race conditions?" |
| `core:claude` | Architecture taste | "Score this plan's axes focusing on: Is this the right approach? Simpler alternatives? Unnecessary complexity? Architectural smell?" |
| `core:gemini-cli` | Codebase alignment | "Score this plan's axes focusing on: Does this match the actual codebase? Are file paths, function names, dependencies accurate? Missing context?" |

**Score aggregation:** Average across 3 models per axis. Flag axes where models disagree (spread ≥ 2) — disagreement signals ambiguity.

**Improvement prompt:**
```
Rewrite this plan to address the weakest-scoring axes.
Critiques from 3 reviewers: {critic_outputs}
Axes with disagreement (resolve these explicitly): {disagreement_axes}
Preserve the plan's structure and intent. Target improvements at specific weaknesses.
```

### Message / Email

**Critics** (2 agents in parallel):

| Agent | Role | Prompt Focus |
|-------|------|-------------|
| `writing:clarity-critic` | Sentence-level readability | "Score axes focusing on: sentence structure, buried asks, passive voice, jargon" |
| `core:claude` | Tone and persuasion | "Score axes focusing on: emotional tone, social dynamics, call-to-action strength, reader motivation. Context: {user_context}" |

**Improvement prompt:**
```
Rewrite this message to address the weakest-scoring axes.
Critiques: {critic_outputs}
Context: {user_context}
Preserve the sender's voice and intent. The improved version should feel like THEM, not a template.
```

**Output:** Show original and improved side-by-side (diff-style or two columns).

### Writing

**Delegation:** Invoke `/review-draft` with `--critics=clarity,humanizer,narrative,facts,redteam`.

**Score extraction:** Parse each critic's prose output into per-axis scores. Each critic maps to one or more axes:
- clarity-critic → Clarity axis
- humanizer → Authenticity axis
- narrative-critic → Argument Structure, Engagement axes
- fact-checker → Evidence Quality axis
- red-team → maps to whichever axis its objections target

**Improvement prompt:**
```
Rewrite this draft to address the weakest-scoring axes.
Critic feedback: {parsed_feedback_per_axis}
Preserve the author's voice and argument. Fix weaknesses, don't rewrite from scratch.
```

### Code

**Delegation:** Dispatch `code:code-reviewer` + `code:codex-reviewer` in parallel.

**Score extraction:** Parse reviewer outputs into per-axis scores. Map findings:
- Bug/correctness issues → Correctness axis
- Style/naming issues → Readability axis
- Complexity/performance notes → Performance, Simplicity axes
- Missing validation → Error Handling axis

**Improvement prompt:**
```
Refactor this code to address the weakest-scoring axes.
Reviewer feedback: {parsed_feedback_per_axis}
Preserve all functionality. Make targeted improvements, not a full rewrite.
```

## Output Format

### How to Read the Scorecard

Before showing scores, briefly orient the reader:

> **How to read this:** Axes are ordered by priority (most important for this content first). Weight (1-3) reflects how much each axis matters to the overall score. The rewrite focuses on the highest-priority weak axes.

This framing appears once, before the first scorecard. Not repeated on rescore.

### Default (no --rescore)

```markdown
## Scorecard

Axes ordered by priority. Weight (1-3) = importance to overall score.
Rewrite targets the highest-priority weak axes.

| Priority | Axis | Weight | Score | Note |
|----------|------|--------|-------|------|
| 1 | Persuasiveness | ★★★ | 2/5 | No concrete value proposition |
| 2 | Call-to-Action | ★★★ | 1/5 | No clear next step |
| 3 | Clarity | ★★☆ | 3/5 | Buries the ask in paragraph 2 |
| 4 | Friendliness | ★☆☆ | 4/5 | Good tone, slightly formal |
| 5 | Conciseness | ★☆☆ | 3/5 | Could cut 40% |

**Weighted score: 2.2/5**
**Improving:** Persuasiveness, Call-to-Action

---

## Improved Version

[The rewritten content]
```

### With --rescore

```markdown
## Improved Version

[The rewritten content]

---

## Scorecard (Before → After)

| Priority | Axis | Weight | Before | After | Note |
|----------|------|--------|--------|-------|------|
| 1 | Persuasiveness | ★★★ | 2/5 | 4/5 | Added value proposition |
| 2 | Call-to-Action | ★★★ | 1/5 | 4/5 | Clear next step with deadline |
| 3 | Clarity | ★★☆ | 3/5 | 4/5 | Led with the ask |
| 4 | Friendliness | ★☆☆ | 4/5 | 4/5 | Preserved |
| 5 | Conciseness | ★☆☆ | 3/5 | 4/5 | Cut 30% |

**Weighted score: 2.2 → 4.2**
```

## Error Handling

| Failure | Recovery |
|---------|----------|
| Context mode finds nothing | Ask user what to improve |
| Criteria generation fails | Use content-type defaults |
| One critic agent fails | Score with remaining critics, note which failed |
| All critics fail | Fall back to single-model critique in main context |
| `/review-draft` not available (writing plugin not loaded) | Self-contained critique using `core:claude` |
| `code:code-reviewer` not available | Self-contained critique using `core:claude` |
| Score parsing fails (prose → numbers) | Present prose feedback directly, skip scorecard |

## Implementation Notes

- Skill lives in `core` plugin (ai-safety-plugins)
- Critics run in parallel via Agent tool
- For router paths (writing, code), existing tool output is parsed into scoring format
- The criteria generation step is what differentiates this from calling existing tools directly
- Improved version goes to same location as input (file → edit file, inline → present in conversation)

## Non-Goals

- Not replacing `/review-draft` or `code-reviewer` — those remain standalone
- Not iterative (no "improve until score > 4" loop) — single pass, user re-invokes
- Not full LLM Council peer review (models scoring each other) — except for plans which benefit from multi-model perspective
- Not for binary decisions ("should I send this?") — always produces an improved version
