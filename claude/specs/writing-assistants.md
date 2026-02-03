# Specification: Writing Assistance Agents

## Overview
**Created**: 2026-01-17
**Status**: Draft

A suite of specialized agents and skills to assist with writing technical content for accessible audiences (LessWrong-style posts, research explainers, ML blog posts). Agents provide critique and suggestions; user applies changes.

## Context & Motivation

Writing for technical-but-accessible audiences (e.g., accompanying NeurIPS papers with LessWrong explanations) requires balancing depth with clarity. Current workflow lacks systematic feedback mechanisms for:
- Identifying unclear passages before publication
- Stress-testing arguments against counterexamples
- Verifying factual claims and finding supporting citations
- Ensuring narrative flow serves the argument

Writing influences are: Paul Graham (conversational clarity), Distill/Lilian Weng (technical accessibility), Joseph Williams' *Style* principles (character-action, cohesion, emphasis).

## Requirements

### Functional Requirements

#### Core Agents
- **[REQ-001]** The system MUST provide a `clarity-critic` agent that identifies readability issues
- **[REQ-002]** The system MUST provide a `narrative-critic` agent that evaluates structure and argument flow
- **[REQ-003]** The system MUST provide a `fact-checker` agent that validates claims and finds citations
- **[REQ-004]** The system MUST provide a `red-team` agent that finds counterexamples and edge cases
- **[REQ-005]** Each agent MUST output to `feedback/{draft-name}_{agent}.md`

#### Feedback Format
- **[REQ-006]** Feedback MUST be separate documents with line references, not inline edits
- **[REQ-007]** Feedback MUST include both problem identification AND proposed fixes
- **[REQ-008]** Feedback MUST be ordered sequentially through the document
- **[REQ-009]** Feedback MUST highlight most impactful issues prominently
- **[REQ-010]** Feedback MUST include a meta-review of overall narrative/structure/style

#### Orchestration
- **[REQ-011]** The system MUST provide `/review-draft` skill that runs all relevant agents
- **[REQ-012]** The system MUST provide individual invocation skills (`/clarity-critique`, `/fact-check`, `/narrative-critique`, `/red-team`)
- **[REQ-013]** Agents MUST ask for target audience when invoked (not inferred)
- **[REQ-014]** Agents SHOULD support `--sensitivity=conservative|aggressive` flag (default: balanced)

#### Specific Critique Capabilities

**Clarity Critic MUST check for:**
- Vague pronouns (especially "this" without clear antecedent)
- Excessive hedging / qualifier stacking
- Run-on sentences that tax comprehension
- Jargon without explanation (audience-dependent)
- Passive voice overuse
- Buried ledes (key points hidden in paragraphs)
- Nominalizations that obscure actors/actions (per Williams)
- Topic string breaks (per Williams: maintain consistent subjects)

**Narrative Critic MUST check for:**
- Argument structure and logical flow
- Evidence threading (claims connected to support)
- Coherence between sections
- Opening hook effectiveness
- Conclusion impact and landing
- Information sequencing (old → new per Williams)

**Fact-Checker MUST:**
- Verify claims against cited sources
- Flag unsupported assertions that need citations
- Detect internal contradictions
- Find new relevant sources (papers, articles) with URLs
- Check for mischaracterizations of cited work

**Red-Team Agent MUST:**
- Find counterexamples to main claims
- Identify unstated assumptions
- Stress-test edge cases in arguments
- Find strongest objections a critic might raise
- Suggest how to preemptively address weaknesses

#### Additional Capabilities
- **[REQ-015]** System SHOULD help generate compelling titles/hooks (part of narrative critic or separate)
- **[REQ-016]** System SHOULD help strengthen conclusions

### Non-Functional Requirements
- **Context efficiency**: Each agent returns <600 tokens feedback (enables parallel runs)
- **Sources**: Fact-checker uses Context7 (technical docs), WebSearch/WebFetch (general claims), red-team uses Context7 for technical verification; others use Read only
- **Output**: All feedback written to `feedback/` directory in same repo as draft

## Design

### High-Level Architecture

```
User invokes /review-draft [draft.md]
         ↓
    Ask: "Who is your target audience?"
         ↓
    Dispatch agents in parallel:
    ├─ clarity-critic → feedback/draft_clarity.md
    ├─ narrative-critic → feedback/draft_narrative.md
    ├─ fact-checker → feedback/draft_facts.md
    └─ red-team → feedback/draft_redteam.md
         ↓
    Return: "Feedback written to feedback/. Start with {most impactful issue}."
```

Individual skills (`/clarity-critique draft.md`) run single agent with same audience prompt.

### Agent Definitions

Each agent defined in `~/.claude/agents/`:

| Agent | File | Tools | Scope |
|-------|------|-------|-------|
| clarity-critic | `writing-clarity.md` | Read | Sentence-level clarity |
| narrative-critic | `writing-narrative.md` | Read | Structure and flow |
| fact-checker | `writing-facts.md` | Read, WebSearch, WebFetch, Context7 | Claim verification |
| red-team | `writing-redteam.md` | Read, WebSearch, Context7 | Argument stress-testing |

### Skill Definitions

Skills in `~/.claude/skills/`:

| Skill | Invocation | Delegates To |
|-------|------------|--------------|
| `/review-draft` | `/review-draft [file]` | All 4 agents in parallel |
| `/clarity-critique` | `/clarity-critique [file]` | clarity-critic |
| `/fact-check` | `/fact-check [file]` | fact-checker |
| `/narrative-critique` | `/narrative-critique [file]` | narrative-critic |
| `/red-team` | `/red-team [file]` | red-team |

### Feedback Document Structure

```markdown
# {Agent} Review: {Draft Title}

**Audience**: {specified audience}
**Sensitivity**: {conservative|balanced|aggressive}
**Date**: {timestamp}

## Meta-Review
{2-3 paragraphs on overall assessment: what's working, main structural issues, tone consistency}

## High-Impact Issues
{Top 3-5 issues that most affect quality, with line references}

## Sequential Feedback

### Line 15-18
**Issue**: {description}
**Proposed fix**: {specific rewrite}

### Line 42
**Issue**: {description}
**Proposed fix**: {specific rewrite}

[...]
```

### Technical Decisions

| Decision | Options Considered | Choice | Rationale |
|----------|-------------------|--------|-----------|
| Agent count | 1 omnibus, 3 specialized, 5+ fine-grained | 4 specialized | Balance between focus and overhead; matches distinct feedback types |
| Feedback location | Same dir, `feedback/`, inline | `feedback/` subdir | Keeps draft clean; easy to gitignore or review separately |
| Audience specification | Front-matter, CLI arg, prompt | Prompt each time | Audience varies; forcing user to think about it improves feedback quality |
| Style models | Hard-coded, configurable, none | Hard-coded references | Paul Graham + Distill + Williams principles are stable targets |

## Edge Cases & Error Handling

| Scenario | Handling |
|----------|----------|
| Draft file doesn't exist | Error with clear message; suggest checking path |
| Draft is empty | Skip review; return "Nothing to review" |
| Very long draft (>5000 words) | Agent proceeds but warns about potential truncation; suggest sectional review |
| `feedback/` doesn't exist | Create it automatically |
| Fact-checker can't find sources | Flag as "unable to verify" rather than fabricating |
| Conflicting feedback between agents | Each agent's feedback stands alone; user reconciles |
| Context7 unavailable | Fact-checker/red-team fall back to WebSearch or gh CLI |
| WebSearch rate limited | Fact-checker flags as "verification incomplete due to rate limiting" |

## Acceptance Criteria

- [ ] **AC-1**: Given a markdown draft, when `/review-draft draft.md` is invoked, then user is prompted for audience and 4 feedback files are created in `feedback/`
- [ ] **AC-2**: Given a draft with vague "this" pronouns, when clarity-critic runs, then each instance is flagged with line number and proposed fix
- [ ] **AC-3**: Given a draft with uncited claims, when fact-checker runs, then claims are flagged and relevant source URLs provided where findable
- [ ] **AC-4**: Given `/clarity-critique draft.md --sensitivity=aggressive`, then agent flags borderline issues it would skip in conservative mode
- [ ] **AC-5**: Given a draft with buried lede in paragraph 3, when clarity-critic runs, then it's flagged as high-impact with specific relocation suggestion
- [ ] **AC-6**: Feedback documents follow the specified structure with meta-review, high-impact section, and sequential feedback

## Out of Scope

- **Direct editing**: Agents critique, they don't rewrite drafts
- **Grammar/spelling**: Use existing tools (LanguageTool, etc.); agents focus on higher-order issues
- **Research assistance**: Agents don't help generate content, only critique existing
- **Version control**: No automatic tracking of feedback application
- **Non-markdown formats**: Google Docs, Word, etc. require copy-paste
- **Translation/localization**: English only
- **Plagiarism detection**: Out of scope for v1

## Open Questions

- [ ] Should meta-review appear at start or end of feedback document?
- [ ] How should agents handle code blocks within technical writing?
- [ ] Should there be a "quick" mode that just returns top 5 issues without full document?
- [ ] Should fact-checker prioritize verifying existing citations vs finding new ones?
- [ ] Is title/hook generation part of narrative-critic or a separate `/generate-hook` skill?

## Implementation Notes

### Style Principles to Encode

From gathered resources, agents should internalize:

**LessWrong Advice:**
- Beware "this" - vague pronouns create ambiguity
- Hedging as tic - excessive qualifiers undermine credibility
- Break run-on sentences - clarity over stylistic emulation
- Use links, images, examples liberally

**Paul Graham:**
- Conversational over formal prose
- Simple Germanic vocabulary
- Read aloud test catches awkwardness
- Writing generates ideas (encourage revision)

**Williams' Style:**
- Characters as subjects, actions as verbs (avoid nominalizations)
- Topic strings for cohesion (consistent subjects across sentences)
- Old → new information sequencing
- Concision without substance loss

**AI Writing Assistance (from GreaterWrong):**
- Push back on AI agreement - request genuine critique
- Fix structure before polishing sentences
- Don't outsource thinking - user maintains editorial judgment

### Reference Links
- [LessWrong Editing Advice](https://www.lesswrong.com/posts/5e49dHLDJoDpeXGnh/editing-advice-for-lesswrong-users)
- [Better Writing Through Claude](https://www.greaterwrong.com/posts/YNCprZAmXnZNozzWh/better-writing-through-claude)
- [Paul Graham on Writing](https://paulgraham.com/writing44.html)
- [Style: Lessons in Clarity and Grace](https://www.goodreads.com/book/show/900697.Style)
