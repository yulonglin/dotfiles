---
name: spec-artifact
description: Write and publish a spec or plan — the three mandatory sections, what to leave out, per-requirement variables, the editable-commentable publish round-trip, and where plans come from.
---

# Writing A Spec

Every spec is built around exactly three mandatory sections: **Overview** (what and why), **Requirements** (the contract — MUST/SHOULD behaviors, or variables and baselines for research specs), and **Acceptance Criteria** (how someone else verifies "done").

Those three names are structural and exempt from the assert-the-finding standard that governs every other header. A spec is a contract: its top-level shape is fixed so a reader can navigate any spec the same way, and a spec often has no finding yet to assert. Every header *below* them is not exempt — sub-headers inside Requirements and Acceptance Criteria state the claim or the behaviour they govern, not a topic.

Everything else is opt-in. Include a section only when there is a real answer for it, otherwise delete it — never fill it with "N/A" or "TBD". A three-section spec is complete, not unfinished.

No checkbox checklists: never `[ ]` markers, neither inline in prose nor as `- [ ]` sub-bullets. Use plain itemised `-` bullets. Checkbox syntax belongs only in actual working todo lists.

## Each requirement that produces a number names its own variables

Not once at the top — per requirement. State the research question in one sentence phrased so an outcome could contradict it, the independent variable and its levels (including anything varied by accident), the dependent variable with its unit of analysis and how it aggregates, and the null: the value the number would take with no signal at all. The full treatment, including the null taxonomy, is in the `results-artifact` skill. A metric defined once in a shared reference can be cross-linked rather than restated.

## The bar for speccing is low

A spec is these three sections and often fits in a message. Don't escalate a two-arm contrast into a document — see `rules/experiments.md`.

## Plans are mostly generated, and reviewed the same way

Implementation plans come from sessions running the superpowers `writing-plans` skill, which owns their shape (bite-sized tasks, per-task test cycle) and their home (`docs/superpowers/plans/`). Don't restate that shape here — route to it. A plan that needs Yulong's review before execution is published exactly like a spec: through the round-trip below, one plan one URL.

## Publish it: the page takes edits back, not only objections

A spec exists to be argued with, and a file in a folder cannot be argued with — you cannot select a paragraph and say "no, not this". Since layer v2, the published page takes **suggested edits** as well as comments: select text, propose the replacement in place, and the export carries both. So every spec and reviewable plan runs this loop:

1. Write the source under `artifacts/<slug>/`, build with `md2artifact`, **commit source and built HTML together** (`artifacts/README.md` has the layout), publish, record the row per `artifacts-sync`. The closing reply carries the link, not only a path.
2. Yulong reviews on the page — comments and suggested edits — and pastes the Copy-all export back into a session.
3. The session applies the export to the committed source. Exported quotes are **rendered text**, not Markdown: locate each in the source and adapt the markup by judgment, never mechanically — a sed loop over the export corrupts the file.
4. Rebuild, update the committed HTML in the same commit, republish at the **same URL**. One spec keeps one link; warn before republishing over a page with unexported annotations.

Layer mechanics — what edit mode does, its invariants, what the viewer refuses — are in `artifact-writing`.
