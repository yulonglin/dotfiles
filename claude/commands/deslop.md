# Remove AI code slop

Check the diff in the working directory against the current branch, and remove all AI generated slop that's uncommitted. (Unless otherwise specified that we should compare againt specific commits/branches, or only look at specific files)

This includes:
- Extra comments that a human wouldn't add or is inconsistent with the rest of the file. Although leave them in for unintuitive things
- Extra defensive checks or try/catch blocks that are abnormal for that area of the codebase (especially if called by trusted / validated codepaths)
- Casts to any to get around type issues
- Any other style that is inconsistent with the file

Report at the end with only a 1-3 sentence summary of what you changed.
