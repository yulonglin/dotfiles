# Where The Procedure Lives

These rules carry only always-relevant judgment. Activity-scoped procedure is a skill — read the matching one when the activity starts, rather than reconstructing it.

- Building or updating an Artifact — transcripts, collapsible units, annotation layer, `md2review`, republishing → `artifact-writing`
- A results or findings page — review checklist, intervals, nulls, chance correction, slicing → `results-artifact`
- Writing a spec → `spec-artifact`
- Recording a published artifact, or reconciling the index after an org switch → `artifacts-sync`
- Classifying text by meaning with a model → `llm-judge`
- Jobs, pueue, resource caps, sandbox failure modes → `jobs`
- Second opinion from another model family → `second-opinion`
- Interviewing the user to stress-test a plan → `interview-me`
- Figures, plots, diagrams, styled pages → `house-plots`
- Browser automation and which browser tool to reach for → `agent-browser`
- Bear notes and Bear-flavoured Markdown → `bear`
- Modern CLI replacements (`rg`, `fd`, `eza`, `bat`, `jq`, …) → `core:fast-cli`

`catalog` is the full index of skills and agents.

## Specs, plans and reports are artifacts

There is no `specs/` or `plans/` convention any more. A spec, plan, report or results analysis is published as an Artifact, because it exists to be argued with and a file in a folder cannot be argued with. Each repo keeps one index at `ARTIFACTS.md` in its root, mapping artifact URLs to what they established, each row stating the finding rather than only the title, and recording the publishing org — which the gallery does not carry and which cannot be recovered later. Schema and the reconcile pass: `artifacts-sync`. Write Markdown source only when it must be version-controlled alongside the code, and put it wherever that repo already puts such files. One topic keeps one link: update in place rather than minting a URL per revision.
