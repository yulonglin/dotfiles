---
argument-hint: [files/branches to check]
description: Remove AI generated code slop
---

# Remove AI code slop

Check the diff in the working directory against the current branch, and remove all AI generated slop that's uncommitted.

Scope: $ARGUMENTS

This includes:
- Extra comments that a human wouldn't add or is inconsistent with the rest of the file. Although leave them in for unintuitive things
- Extra defensive checks or try/catch blocks that are abnormal for that area of the codebase (especially if called by trusted / validated codepaths)
- Casts to any to get around type issues
- Any other style that is inconsistent with the file

Report at the end with only a 1-3 sentence summary of what you changed.
