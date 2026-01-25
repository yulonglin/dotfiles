---
name: commit
description: Commit current work with optional message. Handles git status/diff checking and message formatting.
---

# Commit current work

## Instructions

1. **Check Status**: Run the following commands to understand the current state:
   - `git status --short`
   - `git diff --stat`
   - `git log --oneline -3`

2. **Analyze Changes**:
   - Review the output to understand what has changed.
   - If `git diff` doesn't provide enough info (e.g., new files), read the files or use your working memory.
   - Determine if the work should be split into multiple logical commits.

3. **Commit**:
   - For each logical change, write a commit message in the following format:
     - Short title description (< 80 characters)
     - 2~3 bullet points (< 80 characters) with a quick description
   - Use `git commit -m "..."` to commit the changes.

## Important Notes
- Prepend `GIT_EDITOR=true` to all git commands you run, especially the ones looking at diffs, to avoid blocking.
- If you're at the start of the session, use subagents to summarize changes made by others if needed.
- Only commit work when instructed or when a task is complete.

Optional: Ask me if I would like to push the commit.
