# Spec Conventions

Rules for writing specs (feature specs, research specs, ad-hoc specs) — whether produced via `/spec-interview`, `/spec-interview-research`, or written directly. Keeps every spec Claude writes lean by default instead of accumulating boilerplate sections nobody reads.

## Three Mandatory Sections

Every spec is built around exactly three load-bearing sections:

- **Overview** — what we're building/studying and why, in 1-2 sentences
- **Requirements** — the actual contract: MUST/SHOULD behaviors, or independent/dependent variables and baselines for research specs
- **Acceptance Criteria** — how someone else verifies "done" without asking you

If these three aren't solid, the spec isn't ready to hand off — everything else is secondary.

## Everything Else Is Opt-In

Design, Open Questions, Edge Cases, Non-Functional Requirements, Data Model, Out of Scope, Performance, Security, Caching/Concurrency, Reproducibility Plan, Validation Checklists, and similar sections exist in some specs and not others. Include a section only when the interview or the work surfaced a real, non-obvious answer for it — never as a pro-forma placeholder.

**Never fill an unused section with "N/A" / "None" / "TBD".** Delete the section entirely instead. A spec with three tight sections and nothing else is complete, not unfinished.

## Cross-Reference Instead of Re-Deriving

For research specs, standard engineering patterns (caching, concurrency limits, retry/error handling) belong in `docs/research-methodology.md` and `docs/async-and-performance.md`, not re-explained per spec. Link to them; only write a spec-local section when this particular study needs something nonstandard.

## Why

Specs accumulate sections because each one felt reasonable to add in isolation — but a 15-section template with a 9-item pre-run checklist stops getting read closely, and boilerplate sections dilute the ones that actually carry the design. Optimize for the three sections a reader needs to execute or review the work; add more only when a section earns its place.
