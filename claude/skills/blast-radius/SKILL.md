---
name: blast-radius
description: Find what a change could break outside its own diff before it ships, and prove the one fact its safety rests on by running real code rather than writing an argument. Use on "blast radius of X", "what could this break", "is this safe to merge", when reviewing a small diff you do not trust, or when a brief asserts something about existing code ("make X public", "X already handles Y") before you design against that assertion.
---

# Blast radius

Adapted from [pstack-claude](https://github.com/michael-denyer/pstack-claude) (MIT), the Claude Code port of Lauren Tan's pstack; references to pstack's `how`, `why`, `arena` and `unslop` skills are replaced by their local equivalents.

The job is the breakage a symbol search will not show. Listing callers takes a second with `rg`; that is not the job. Run this before design as well as before merge when a brief asserts something about existing code: the assertion is a hypothesis, and the census of real consumers decides the design.

## A convincing writeup proves nothing

A blast-radius writeup reads as convincing whether or not it is true. So do not hand back the argument. Find the one or two facts the change's safety depends on and prove them by running code.

For each such fact, push it as far down this ladder as is cheap, and say where it stopped:

1. Asserted. Worthless alone.
2. Pointed at: a real `file:line`, or the library's own source at the pinned version.
3. Walked: the failure path traced step by step, and it does not reach.
4. Ran: a script or test that calls the real code and fails loudly if the fact is wrong.
5. Reproduced in the running system.

Rung 4 is usually one small script that imports the library the app ships and calls the exact function in question.

## Steps

1. **Read the change.** The diff, the symbols it adds, changes and deletes, and what now behaves differently, including what the diff does not spell out. Pull the PR and commit messages with `gh pr view` and `git log` for intent.
2. **Find the one fact it is safe because of.** Most risky-looking changes are safe because of a single fact ("this call only drops cache entries that are already dead"). If that fact holds, most risks clear at once. Spend the time here, not on a long list of maybes.
3. **Look where grep stops.** Read the source of the library being called at its pinned version, including any local patch. Work out ordering: async scheduling, teardown, retries, signal handlers. Follow what a symbol search misses: a JSON shape an API returns, a DB column, a JSONL or `.eval` field another script reads, a config key, an env var, a feature flag, a hook matcher, another language reading the same bytes, code three hops downstream. In this dotfiles repo that includes everything `deploy.sh` symlinks into a running environment.
4. **Be honest about each risk.** Give it a real likelihood and a real cost. Keep confirmed risks; list the checked-and-cleared ones separately. Cite real `file:line`; a search that finds nothing is still an answer, stated as the command and its empty result. Never invent a caller or an API.
5. **Prove the one fact.** Write the script or test, run it, and paste its output.
6. **For a large or wide change, get another family's read.** Use `council` with the diff and the safety fact, briefed fresh — a same-family agent echoes rather than catches.

## What to hand back

- **What it does**, including the non-obvious part.
- **The one fact it is safe because of**: stated, the rung it reached, and the proof. If unproven, say "unproven".
- **Risks**: how each breaks, `file:line`, likelihood and cost, how to check. Paste the proof for the ones that matter.
- **Cleared**: what was checked and why it is fine.
- **Before merge**: the cheapest test or repro that catches the real bug, including the script written in step 5 with its absolute path.

Write it to `clear-writing`'s standard, and strip anything private before it goes anywhere public.
