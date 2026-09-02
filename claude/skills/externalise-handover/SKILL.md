---
name: externalise-handover
description: Externalise the important parts of this conversation into a handover document for another person or agent — next tasks, what was accomplished with exact commands and output paths, bugs hit, open uncertainties, and the user's own instructions cleaned up. Use on "hand this over", "write a handover", "handoff brief", "brief another agent on this", "externalise this conversation", or /externalise-handover.
---

# Externalise / Handover

Write out the parts of this conversation a fresh reader needs, so the work can continue without you.

**Cover:**

- Tasks to do next.
- What has been accomplished — exact commands run, inputs and arguments, outputs including absolute file paths.
- Bugs encountered.
- Key areas of uncertainty.
- The user's instructions and clarifications, touched up to be clearer.

Use any additional context given in the arguments.

**Where it lands is a choice, not a default.** A brief a person will read and argue with is an Artifact; a brief a subagent will consume, or one that must be version-controlled beside the code, is an `.md` file. Pick from the reader, then say which you chose.

## Reach for a neighbour instead when

- the handover is **an Artifact** — titles, structure, publishing, republishing: the `artifact-writing` skill
- the brief must survive being **misread by someone with no context**: the `reduce-ambiguity` skill, before you send it
- the reader is **future you in a new session**, not another person: the `remember` plugin
- the session is **stalled and needs a terminal state**, not a document: the `wrap-up` skill
- you only need the session **retitled as finished**: the `done` skill
- the prose itself needs to hold up: `~/.claude/checklists/writing.md`
