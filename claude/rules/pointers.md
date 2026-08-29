# Where The Procedure Lives

These rules carry only always-relevant judgment. Activity-scoped procedure is a skill — read the matching one when the activity starts, rather than reconstructing it.

- Building or updating an Artifact — transcripts, collapsible units, annotation layer, `md2review`, republishing → `artifact-writing`
- A results or findings page — review checklist, intervals, nulls, chance correction, slicing → `results-artifact`
- Writing a spec → `spec-artifact`
- Red-teaming a draft for how it could be misread, before sending it → `check-misreads`
- Classifying text by meaning with a model → `llm-judge`
- Jobs, pueue, resource caps, sandbox failure modes → `jobs`
- Second opinion from another model family → `second-opinion`
- Interviewing the user to stress-test a plan → `interview-me`
- Charts and figures → `house-plots` (matplotlib for papers; native SVG via built-in `dataviz` for artifact pages)
- Browser automation and which browser tool to reach for → `agent-browser`
- Bear notes and Bear-flavoured Markdown → `bear`
- Modern CLI replacements (`rg`, `fd`, `eza`, `bat`, `jq`, …) → `core:fast-cli`

`catalog` is the full index of skills and agents.

## Specs, plans and reports are artifacts

There is no `specs/` or `plans/` convention any more. A spec, plan, report or results analysis is published as an Artifact, because it exists to be argued with and a file in a folder cannot be argued with. Each repo keeps one index — an `artifacts.md`, or a section in its README or CLAUDE.md — mapping artifact URLs to topics, each row stating the finding rather than only the title. Write Markdown source only when it must be version-controlled alongside the code, and put it wherever that repo already puts such files. One topic keeps one link: update in place rather than minting a URL per revision.
