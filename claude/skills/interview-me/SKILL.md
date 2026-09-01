---
name: interview-me
description: Interview the user relentlessly about a plan, decision, or idea to stress-test it. Use on "interview me", "grill me", "grill this plan", "poke holes in this", or "play devil's advocate."
---

Interview me relentlessly about every aspect of this until we reach a shared understanding. Walk down each branch of the decision tree, resolving dependencies between decisions one-by-one.

## Ask In Bundles, Never A Drip Of Single Questions

Decision-asking lands in **1-2 rounds totalling roughly 10-20 questions**. A drip of one question at a time is the failure mode: it stretches a ten-minute interview across an hour and forces me to reload the context on every reply.

The **AskUserQuestion** tool caps at **4 questions per call**, so a round is built out of back-to-back calls of 4 with nothing interleaved between them — no commentary, no tool calls, no thinking out loud between the batches. When the batch is larger than a couple of rounds, or the answers need comments rather than a pick, collect the decisions through an Artifact instead: every question on one page, answerable from the keyboard (move between questions, pick an option, type a comment), and a copy-all control that yields every answer and comment as one block I can paste straight back. `md2artifact` already builds that shape — write the questions as Markdown and publish the result (`artifact-writing`).

Order the bundle so independent decisions come first and dependent ones follow, and put a decision in round 2 rather than round 1 when my round-1 answer could make it moot.

## Shape Of Each Question

Your recommended answer is the first option, labelled `(Recommended)`; the rest are the live alternatives, and the automatic `Other` catches whatever you missed.

I have asked you to make these calls, so override AskUserQuestion's usual "only when genuinely blocked" instinct: never skip a question because a sensible default exists. The default is your first option, not a reason to stay quiet.

For open-ended probes ("what failure mode worries you most?"), synthesise 2-4 candidate answers rather than falling back to prose. Ask in plain text only when the answer space is genuinely unbounded — paste an error, name a file. When the question compares two concrete artifacts (schemas, API shapes, framings), put each on an option's `preview` (single-select only) so I can see them side by side.

## Look Facts Up, Ask Only For Decisions

If a *fact* can be found by exploring the environment (filesystem, tools, etc.), look it up rather than asking me. The *decisions*, though, are mine.

Do not act on it until I confirm we have reached a shared understanding.

<!-- Source: mattpocock/skills@9603c1c (skills/productivity/grilling) — modified locally: AskUserQuestion flow, bundled-questions protocol; renamed grilling → interview-me -->
