# paper-writer agent, retired 2026-09-08

`paper-writer.md` was a `model: inherit` agent, so it drafted paper sections as whatever Claude model ran the session — Fable or Opus 5 in practice. Yulong banned Opus 4.8, Opus 5 and Fable from writing artifacts and paper prose on 2026-09-08 because their writing is impenetrable to him; paper sections now go through the `delegate-writing` skill, which dispatches the prose to `sol(high)` from a session-built skeleton.

Before retiring it, the agent was compared against `claude/checklists/writing.md`. Almost everything it said was already there in a stronger form (claim calibration, fair positioning, honest limitations, the abstract and intro carrying the reading). Four things were not, and were folded into the checklist rather than lost:

- a paper never mentions coding agents or AI assistance in producing the draft;
- fix the venue before drafting;
- the introduction's shape (problem, approach with results previewed, contributions, one-sentence claim) and limitations ordered by importance and marked fundamental versus implementation, with future work naming a specific test;
- the pointer to `claude/docs/paper-writing-style-guide.md` (title patterns, five-part abstract, section skeletons from the Khan and Greenblatt ICML 2024 papers), which the checklist's reference-drafts section now links.

The agent's two other references, `docs/reproducibility-checklist.md` and `docs/ci-standards.md`, were not moved: the first does not exist under `claude/docs/`, and the second is covered by the interval rules in `results-analysis.md` and the `results-artifact` skill.
