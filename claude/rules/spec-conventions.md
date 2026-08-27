# Spec Conventions

Every spec is built around exactly three mandatory sections: **Overview** (what and why), **Requirements** (the contract — MUST/SHOULD behaviors, or variables and baselines for research specs), **Acceptance Criteria** (how someone else verifies "done").

Those three names are **structural and exempt** from the assert-the-finding standard in `markdown-style.md` — a spec is a contract, its top-level shape is fixed so a reader can navigate any spec the same way, and a spec often has no finding yet to assert. Every header *below* them is not exempt: sub-headers inside Requirements and Acceptance Criteria state the claim or the behaviour they govern, not a topic.

Everything else is opt-in: include a section only when there's a real answer for it, otherwise delete it — never fill it with "N/A" / "TBD". A three-section spec is complete, not unfinished. Cross-reference standard engineering patterns to `docs/research-methodology.md` and `docs/async-and-performance.md` rather than re-deriving them per spec.
