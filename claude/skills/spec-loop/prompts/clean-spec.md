<!-- Adapted from the 2026-08-09 workflow-specs interview (§Q5 "Cleaning spec"). Edit freely — tests/test_spec_loop_prompts.sh pins structure, not wording. -->

Clean this spec up for clarity and concision:

- Remove unnecessary detail. Process artifacts — audit trails, change logs, interview transcripts — are included only when the spec genuinely needs them, never by default.
- Prefer signposting and bullet points over walls of text: a reader should find any requirement by scanning headings and bullets, not by re-reading paragraphs.
- Cut repetition and vague prose; keep rationale, constraints, and stated uncertainty.

Keep the five-section template intact while cleaning: `# Goal`, `# Context`, `# Requirements`, `# Acceptance criteria`, `# Out of scope`. A section left with nothing real after cleaning is deleted, never filled with N/A or TBD.
