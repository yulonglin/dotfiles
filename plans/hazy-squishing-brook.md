# Add Learning Extraction Step to finishing-a-development-branch

## Context

From Boris Cherny's Claude Code tips thread, the user identified **learning/documentation generation** as their main pain point. They tend to "mostly move on" after finishing work rather than extracting learnings. The existing `finishing-a-development-branch` skill has a natural boundary (work is complete) where learning extraction should happen — before presenting merge/PR options.

**Goal:** Add a lightweight "Extract Learnings" step to the skill that prompts for knowledge capture at the moment work is freshest.

## File to modify

`/home/yulong/code/dotfiles/claude/skills/finishing-a-development-branch/SKILL.md`

## Changes

### Add Step 1.5: Extract Learnings (between current Step 1 "Verify Tests" and Step 2 "Determine Base Branch")

After tests pass, before presenting options, add a learnings extraction step:

1. Auto-generate a learnings summary by reviewing:
   - `git log --oneline <base>..HEAD` — what was done
   - `git diff --stat <base>..HEAD` — what files changed
   - Any TODOs or FIXMEs added during the branch

2. Present a brief summary:
   ```
   Learnings from this branch:
   - <auto-detected patterns, decisions, gotchas>

   Options:
   1. Add to project CLAUDE.md Learnings section
   2. Create/update a skill (if pattern is reusable)
   3. Skip (no learnings worth capturing)
   ```

3. If option 1: Use `/revise-claude-md` pattern — draft additions, show diff, apply with approval
4. If option 2: Ask what the skill should capture, then create/update
5. If option 3: Continue to merge options

### Key design decisions

- **Lightweight, not blocking** — option 3 (skip) is always available and prominent
- **Auto-detect, don't interrogate** — use git history to suggest learnings rather than asking open-ended questions
- **Respect existing flow** — this inserts cleanly between "tests pass" and "present merge options"
- **No new files** — just editing the existing SKILL.md

## Verification

1. Read the modified skill to confirm it reads well
2. Invoke `/finishing-a-development-branch` on a test branch to confirm the new step appears
3. Verify skip option works without friction
