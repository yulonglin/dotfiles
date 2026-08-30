---
name: spec-interview
description: Interview Yulong into a specification before a large feature is built — implementation approach, UX, edge cases, failure modes, tradeoffs and what is deliberately out of scope. Use when starting a substantial feature, tool or piece of product work, when a design needs its assumptions challenged before any code is written, or on "spec this out", "help me design this feature", "interview me about this".
---

# Spec Interview

Build a complete specification by interviewing before implementing. This file says how to run the interview and where the answers go; the question bank and the spec shape live in the references and in `spec-artifact`.

For an **experiment** rather than a feature — hypotheses, variables, confounds, baselines — use `spec-interview-research` instead.

## Run it in rounds, and challenge rather than transcribe

Read any existing context first: a file the user points at, a description they gave, the code the feature lands in.

Then ask **2-4 questions per round**, and probe deeper whenever an answer is vague. Ask the **non-obvious** ones — not "what should it do?" but "what happens when X fails halfway through Y?". Challenge as you go: "why not do X instead?", "what breaks if this doubles in scale?", "who is hurt when this is wrong?". A transcribed interview produces a spec that agrees with whatever the user already believed. Continue until every major area is covered.

`references/interview-guide.md` holds the question categories, the example questions and the completion checklist. Work from it.

## The spec is an Artifact, not a file

There is no `specs/` folder convention here — a spec exists to be argued with, and a file in a folder cannot be argued with. Publish the finished spec as an Artifact and hand back the link.

`references/spec-template.md` gives the section-by-section shape — overview, context, functional and non-functional requirements, design, edge cases, acceptance criteria, out of scope, open questions. It maps onto the three mandatory spec sections: Overview, Requirements, Acceptance Criteria. The format and what to leave out are in the `spec-artifact` skill; the publishing mechanics are in `artifact-writing`; record the URL and what it establishes per `artifacts-sync`.

One feature keeps one link: update it in place rather than minting a new URL per revision.

## When complete

Hand back the Artifact link, list the open questions the interview did not close, and suggest a fresh session to execute — a spec is worth more when the context that wrote it is not also the context that implements it.

## Reach for a neighbour instead when

- the subject is an **experiment**, not a feature: the `spec-interview-research` skill
- the plan is **already written** and the job is to stress-test it: the `interview-me` skill
- you need the **spec shape** rather than the interview: `spec-artifact`
- the spec is written and the risk is being **misread**: the `reduce-ambiguity` skill
