---
name: write-prose
description: Use when drafting or revising prose a human will read — artifacts, reports, specs, skill and rule text, PR bodies. Routes the writing to the designated writing model instead of writing it yourself.
---

# Route prose to the writing model

Opus 5 and Fable 5/5.1 write unclear, abstruse prose. That is a standing judgement in global CLAUDE.md, not a preference to re-litigate. So for anything in scope below, you do not write the prose — you commission it.

Draft time, not polish time. Sending your own draft out for polishing preserves your structure and your phrasing, which is the part that was wrong. Send the *material* and let the writing model choose the shape.

## In scope

- Artifacts, reports and specs
- Skill and rule text
- PR bodies and descriptions

Out of scope, because the round trip costs more than it returns: chat replies, commit messages, code comments, and anything under about 150 words.

## The seats, in order

1. `sol(high)` — GPT-5.6 Sol, the default writer
2. `astra(high)` — GPT-6 Astra, also the reviewer and the polisher of choice for restructuring
3. `kimi` — Kimi K3, the cross-family fallback

Seats 1 and 2 share one credential pool (Codex OAuth), so a quota failure usually takes out both — the error reads `usage_limit_reached ... via provider codex`. Seat 3 is on OpenRouter and survives that. A quota or cooldown failure is transient and owes no finding: move down the list and say which seat produced the text.

## What to send

The brief must stand alone, because the agent has none of your context.

- The material: findings, constraints, the decision, the numbers. Raw is fine.
- The audience and what they will do with it.
- Any reviewer comments verbatim, when this is a revision — quote them, do not summarise them into "make it clearer".
- The conventions that apply, from `~/.claude/checklists/writing.md`: one paragraph is one line, headings assert a point in 4-7 words, results belong in figures, every sourced claim links to its source, no checkbox syntax outside working todo lists.
- A length target. Without one you get more words, not better ones.
- "Return only the markdown, no preamble, no outer code fence. Do not write any file."

## After it returns

Read it before you ship it. You are accountable for the claims, and a writing model will not catch a fact you got wrong — it will state it more fluently. Check that no claim was invented, that every number still matches its source, and that nothing in scope was dropped.

Then write the file yourself and show the diff. Name the seat in your message to the user, so a weak result is attributable.
