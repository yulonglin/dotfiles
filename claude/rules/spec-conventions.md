# Spec Conventions

Every spec uses the five-section template, in this order: **Goal** (what and why, the intended outcome), **Context** (current state, constraints, prior decisions the spec builds on), **Requirements** (the contract — MUST/SHOULD behaviors, or variables and baselines for research specs), **Acceptance criteria** (how someone else verifies "done"), **Out of scope** (what this spec deliberately does not cover, so divergence is detectable).

A section with nothing real to say is deleted, never filled with "N/A" / "TBD" — a spec that ships with only Goal/Requirements/Acceptance criteria is complete, not unfinished. Cross-reference standard engineering patterns to `docs/research-methodology.md` and `docs/async-and-performance.md` rather than re-deriving them per spec.

Specs live in the vault (`~/vault`), reached from a repo via its `specs/` symlink — `warn_spec_outside_vault.sh` warns when a new spec lands elsewhere. The `/spec-loop` skill drives a spec through plan → implement → test → run → analyze with a cross-model review after each phase; its refinement prompts (`claude/skills/spec-loop/prompts/`) carry this template.
