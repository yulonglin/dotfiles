---
name: skill-invocation-modes
description: The invocation-mode tradeoff when authoring a skill — model-invoked vs user-invoked, and the two loads you pay for the choice.
disable-model-invocation: true
---

# Skill Invocation Modes

For skill authoring generally — structure, TDD mapping, discovery optimisation, testing with subagents — use `superpowers:writing-skills`, which is far more thorough than anything kept here.

This file covers the one thing that skill does **not**: the invocation-mode decision. Vocabulary adapted from [mattpocock/skills](https://github.com/mattpocock/skills)@9603c1c.

## The Choice Is Which Load You Pay, Not Which Is Cheaper

Every skill is reached one of two ways, and each way spends a different budget.

- A **model-invoked** skill keeps its `description`, so the agent can fire it autonomously *and* other skills can reach it — you can still type its name too, so model-invocation always *includes* user reach. It pays a permanent **context load**: the description sits in the window every turn, spending tokens and attention.
- A **user-invoked** skill sets `disable-model-invocation: true`, stripping the description from the agent's reach. Only the human, typing its name, can invoke it — and no other skill can. Zero context load, but it spends **cognitive load**: *you* become the index that must remember it exists.

Pick model-invocation only when the agent must reach the skill on its own, or another skill must. If it only ever fires by hand, make it user-invoked and pay no context load.

**Cognitive load is not a cost to minimise.** It is the price of human agency, and the reason some skills stay user-invoked deliberately. Spend it where human judgement matters; remove it where it does not.

## A Router Skill Cures Piled-Up Cognitive Load

When user-invoked skills multiply past what you can remember, the cure is one user-invoked **router skill** that names the others and says when to reach for each — so you remember one skill instead of many.

A router can only hint, never fire: user-invoked skills have no description, so nothing but the human can reach them. In this repo `catalog` plays that role, indexing which skill owns each activity.

## The Description Is A Context Pointer, So Its Wording Decides Reliability

A `description` is a reference held in context that names out-of-context material and encodes the condition for reaching it. Its **wording, not its target**, decides when the agent reaches and how reliably.

A must-have target behind a weakly worded pointer is a variance bug. Sharpen the wording first; inline the material only if sharpening fails.

For a model-invoked description, two rules do most of the work:

- **Front-load the leading word** — the trigger term you actually type in your prompts. That is where the description does its invocation work.
- **One trigger per branch.** Synonyms renaming a single branch are duplication — "build features using TDD … asks for test-first development" is one branch written twice. Collapse them.

## Granularity Is Chosen By Which Load You Can Afford

Finer division always spends one of the two loads: more model-invoked skills crowd the context window with competing descriptions; more user-invoked skills give the human more to remember.

Two cuts guide the division:

- **By invocation** — split off a model-invoked skill where you have a distinct leading word to trigger it.
- **By sequence** — split a run of steps where a step's post-completion steps need hiding, since isolating it in its own context clears what follows. Beware the reverse: merging sequences exposes each step's post-completion steps to what follows, inviting premature completion.
