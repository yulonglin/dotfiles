<!-- Verbatim body from ~/vault/specs/2026-08-09-workflow-specs-interview-round1.md §Q5 "Improving spec". Do not edit between the verbatim markers — the body is sha256-guarded in tests/test_spec_loop_prompts.sh. -->
<!-- verbatim-begin -->
Review the specification and improve it for clarity, concision, coherence, and implementation readiness.

## Evaluate

### 1. Purpose

- Is the aim of the specification clear?
- Is the intended outcome or user value obvious?

### 2. Open questions

- Are there unresolved questions, unsupported assumptions, missing decisions, or areas that require investigation?
- Use subagents to investigate questions that can be answered from the repository, documentation, or other available evidence.
- Do not invent requirements. Clearly flag anything that still requires a human decision.

### 3. Consistency and precision

- Identify ambiguities, contradictions, imprecise language, undefined terms, and requirements that do not make sense together.
- Resolve issues where the intended meaning is well supported.
- Use `/grill-me` for material ambiguities where different answers would meaningfully change the design or implementation.

### 4. Implementation readiness

- Is the specification concrete enough for an implementation agent with limited context to execute reliably?
- Are scope, constraints, dependencies, interfaces, edge cases, and non-goals sufficiently clear?
- Is it clear what should and should not be changed?

### 5. Acceptance criteria

- Are there explicit, testable acceptance criteria?
- Are expected behaviors, failure cases, and important edge cases covered?
- Add or improve acceptance criteria and proposed tests where needed.

### 6. Concision and structure

- Remove repetition, unnecessary detail, and vague prose.
- Improve ordering and signposting.
- Preserve important context, rationale, constraints, and uncertainty.

## Process

First:

- Summarize the purpose of the specification.
- Identify the highest-impact issues.
- Investigate any resolvable open questions.
- /grill-me to understand my requirements.
- List any remaining decisions that require clarification.

Then revise the specification.

## Output

Provide:

1. A concise critique.
2. Questions or decisions that still require clarification.
3. A revised specification.
4. A short summary of substantive changes.
5. Any remaining risks or implementation uncertainties.

/grill-me if helpful!
<!-- verbatim-end -->

<!-- addendum: dotfiles spec-loop v1 — not part of the verbatim §Q5 body above -->

The revised specification MUST use the five-section template: `# Goal`, `# Context`, `# Requirements`, `# Acceptance criteria`, `# Out of scope` (see `~/.claude/rules/spec-conventions.md`). Restructure into these headings if the input uses others. Delete any section with nothing real to say — never fill it with N/A or TBD.
