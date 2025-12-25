---
argument-hint: [message]
description: Commit current work with optional message
---

# Commit current work
Commit current work

$ARGUMENTS

## Important
- Prepend GIT_EDITOR=true to all git commands you run, especially the ones looking at diffs, so you can avoid getting blocked as you execute commands
- If you can't get any information from git diff, just using your working memory to determine what has changed
- You might want to split up the work into separate commits, if it makes sense logically. Read through the changes first to figure out if we should do that

## Instructions
Review each file individually to make sure they're related to the work you just did, then write a brief commit message in the following format:

- Short title description (< 80 characters)
- 2~3 bullet points (< 80 characters) with a quick description

If you're at the start of the session, that means other agents have done the work or are doing the work now. In such a case, your task is to commit the changes that have been made. Use subagents summarise the changes made, in order to logically break down the commits.

## Notes
- You should only commit work when instructed. Do not keep committing subsquent work unless explicitly told so

Optional: ask me if I would like to push the commit, but WARN about this if I'm on main
