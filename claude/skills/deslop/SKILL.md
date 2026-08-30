---
name: deslop
description: Strip AI-generated slop and overengineering out of code you or an agent just wrote — narrating comments a human would never add, defensive try/except and null guards on already-validated codepaths, `any` casts papering over type errors, needless abstraction layers, and any style the rest of the file does not use. Use before committing agent-written code, when reviewing an uncommitted diff, and on "deslop", "remove the slop", "clean up this diff", "de-AI this code", "it looks LLM-written", "strip the overengineering", "make this look human-written".
---

# Remove AI code slop

## Instructions

Check the diff in the working directory against the current branch, and remove all AI generated slop that's uncommitted.

**Scope:** The current working directory or provided arguments.

**What to remove:**
- Extra comments that a human wouldn't add or is inconsistent with the rest of the file. Although leave them in for unintuitive things.
- Extra defensive checks or try/catch blocks that are abnormal for that area of the codebase (especially if called by trusted / validated codepaths).
- Casts to `any` to get around type issues.
- Any other style that is inconsistent with the file.

**Report:**
At the end, provide only a 1-3 sentence summary of what you changed.

## Reach for a neighbour instead when

- the diff might be **wrong**, not just ugly — correctness, security, research validity: the `code-reviewer` agent
- something is **broken** and you need the root cause: the `diagnosing-bugs` skill, or the `debugger` agent
- the slop is in **prose** rather than code — LLM tics, hedging, filler: `~/.claude/checklists/writing.md` via the `clear-writing` skill
