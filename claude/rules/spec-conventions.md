# Spec Conventions

Every spec uses the five-section template, in this order: **Goal** (what and why, the intended outcome), **Context** (current state, constraints, prior decisions the spec builds on), **Requirements** (the contract — MUST/SHOULD behaviors, or variables and baselines for research specs), **Acceptance criteria** (how someone else verifies "done"), **Out of scope** (what this spec deliberately does not cover, so divergence is detectable).

A section with nothing real to say is deleted, never filled with "N/A" / "TBD" — a spec that ships with only Goal/Requirements/Acceptance criteria is complete, not unfinished. Cross-reference standard engineering patterns to `docs/research-methodology.md` and `docs/async-and-performance.md` rather than re-deriving them per spec.

Specs live in the vault (`~/vault`), reached from a repo via its `specs/` symlink — `warn_spec_outside_vault.sh` warns when a new spec lands elsewhere. The `/spec-loop` skill drives a spec through plan → implement → test → simplify → run → analyze with a cross-model review after each phase; its refinement prompts (`claude/skills/spec-loop/prompts/`) carry this template.

## Interview conventions

How spec interviews (`/spec-interview`, `/spec-interview-research`, `/grill-me`, and the spec-loop plan phase) collect decisions from Yulong.

**Channel by question count.** Four questions or fewer → one batched `AskUserQuestion` call (the tool caps a call at four questions). More → either a run of successive batched `AskUserQuestion` calls — 10-20 questions delivered that way is fine — or a single markdown answer file via `SendUserFile`; never a drip of one-question prompts. Prefer the answer file when questions need long what-I-found preambles or asynchronous answering. `/grilling` is the deliberate exception: one question per call, walking decision dependencies one at a time.

**Answer-file format.** Each question carries a short what-I-found preamble, checkbox options with the recommended default listed FIRST and marked "(recommended)", and a `Comments:` line. A question left blank means the recommended default is accepted. (Checkboxes are permitted here as an exception to `markdown-style.md` — an answer file is a working form, not a doc.)

**Bounded rounds.** At most two rounds per interview. Round two contains only questions that round one's answers newly raised or left genuinely unresolved — a question answered in any earlier round is never re-asked, and its answer is restated as a settled decision rather than reopened.
