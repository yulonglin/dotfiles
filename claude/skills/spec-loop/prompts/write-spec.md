<!-- Adapted from the 2026-08-09 workflow-specs interview (§Q5 "Writing spec"). Edit freely — tests/test_spec_loop_prompts.sh pins structure, not wording. -->

Start by planning only, with a specification as your output. Do not modify code yet.

Inspect the relevant code and documentation. Identify:

- the existing architecture and patterns we should follow
- the files and components likely to change
- important implementation decisions and trade-offs
- how we will test and verify the result

Keep the scope limited to what was requested. Do not include adjacent improvements.

Return a concrete implementation specification.

/grill-me to understand the requirements first.

Write the specification in the five-section template: `# Goal`, `# Context`, `# Requirements`, `# Acceptance criteria`, `# Out of scope` (see `~/.claude/rules/spec-conventions.md`). Delete any section with nothing real to say — never fill it with N/A or TBD. Specs live in the vault (`~/vault`, via the repo's `specs/` symlink where one exists).
