<!-- Verbatim body from ~/vault/specs/2026-08-09-workflow-specs-interview-round1.md §Q5 "Writing spec". Do not edit between the verbatim markers — the body is sha256-guarded in tests/test_spec_loop_prompts.sh. -->
<!-- verbatim-begin -->
Start by planning only, with a specification as your output. Do not modify code yet.

Inspect the relevant code and documentation. Identify:
- the existing architecture and patterns we should follow
- the files and components likely to change
- important implementation decisions and trade-offs
- how we will test and verify the result

Keep the scope limited to what was requested. Do not include adjacent improvements.

Return a concrete implementation specification.

/grill-me to understand the requirements first.
<!-- verbatim-end -->

<!-- addendum: dotfiles spec-loop v1 — not part of the verbatim §Q5 body above -->

Write the specification in the five-section template: `# Goal`, `# Context`, `# Requirements`, `# Acceptance criteria`, `# Out of scope` (see `~/.claude/rules/spec-conventions.md`). Delete any section with nothing real to say — never fill it with N/A or TBD. Specs live in the vault (`~/vault`, via the repo's `specs/` symlink where one exists).
