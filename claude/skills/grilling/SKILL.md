---
name: grilling
description: Grill the user relentlessly about a plan, decision, or idea. Use when the user wants to stress-test their thinking, or says "grill me", "grill this plan", "poke holes in this", or "play devil's advocate."
---

Interview me relentlessly about every aspect of this until we reach a shared understanding. Before asking anything, think for longer: map the decision tree and assemble a good list of questions.

Put them to me with the **AskUserQuestion** tool in **batched calls** (the tool caps a call at four questions) — a drip of one-question calls is annoying. Hold a question back for a later call only when it genuinely depends on an earlier answer. Your recommended answer is the first option, labelled `(Recommended)`; the rest are the live alternatives, and the automatic `Other` catches whatever you missed.

I have asked you to make these calls, so override AskUserQuestion's usual "only when genuinely blocked" instinct: never skip a question because a sensible default exists. The default is your first option, not a reason to stay quiet.

For open-ended probes ("what failure mode worries you most?"), synthesise 2-4 candidate answers rather than falling back to prose. Ask in plain text only when the answer space is genuinely unbounded — paste an error, name a file. When the question compares two concrete artifacts (schemas, API shapes, framings), put each on an option's `preview` (single-select only) so I can see them side by side.

If a *fact* can be found by exploring the environment (filesystem, tools, etc.), look it up rather than asking me. The *decisions*, though, are mine.

Do not act on it until I confirm we have reached a shared understanding.

<!-- Source: mattpocock/skills@9603c1c (skills/productivity/grilling) — modified locally: AskUserQuestion flow -->
