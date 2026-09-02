---
name: done
description: Mark the session as done — generate a descriptive session title if it has none, prepend a checkmark, and hand back the /rename line that applies it. Use when wrapping up or closing out a session, and when the user says "done", "finished", "that's it", "ship it", "mark this done", or invokes /done.
---

# Mark Session Done

1. Run the script to generate the session title:

```bash
~/.claude/skills/done/done.sh
```

2. The script outputs the title (e.g., `✅ Build Done Skill`). Tell the user to run:

```
/rename <the title from step 1>
```

**Why /rename is needed:** writing to the transcript JSONL only persists for `/resume`. The live session UI reads from an in-memory cache that only `/rename` updates, and there is no external API to set it programmatically.

If the script outputs "Already done" to stderr, the session is already marked — confirm that to the user. If it reports a missing `ANTHROPIC_API_KEY`, the secrets helper could not resolve one: say so rather than inventing a title.

**The transcript is found by "newest `.jsonl` in the project directory."** In a linked worktree the session's transcripts live under the *main* checkout's project directory, so the script falls back to that — which means with several sessions running against one repo it can title the wrong one. Read the title before passing it on, and if it does not describe this session, write the `/rename` line yourself.

## Reach for a neighbour instead when

- the session is **stalled rather than finished** and needs to be driven to a terminal state — land it, state the blocker, or take one step: the `wrap-up` skill
- the work needs **committing and pushing** before it is done: the `commit` or `commit-push-sync` skill
- the point is to **carry context to another session or colleague**, not to retitle this one: the `externalise-handover` skill
- the point is to **resume this work later yourself**: the `remember` plugin
