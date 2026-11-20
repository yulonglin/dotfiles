---
name: sharpen
description: Make a task deeper, not bigger — say what a top practitioner would do that the prompt does not ask for, what raw material and methods they would use, and what outside check would show the result is right — then rewrite the prompt to ask for exactly that, leaving the user's own choices open. User-invoked only, on /sharpen.
disable-model-invocation: true
---

# Sharpen

Adapted from pstack's `sharpen` skill in [pstack-claude](https://github.com/michael-denyer/pstack-claude) (MIT), the Claude Code port of Lauren Tan's pstack.

The user wants a deeper version of the task in front of you, not a bigger one. Do not start the task. First answer four questions, one or two lines each:

1. **What would a top practitioner in this field do here that the prompt does not ask for?** For research, include what a reviewer would find suspect in the obvious approach (`research-core.md`'s reviewer test).
2. **What raw material would they start from** instead of what has already been digested — the transcripts rather than the summary, the logs rather than the dashboard, the paper rather than the blog post, the user's original words rather than an agent's paraphrase?
3. **Which specific methods and tools** would they use? Name them; prefer what this machine already has.
4. **What, other than you or the user, would show the result is right?** A test, a held-out slice, another model family, a known-positive sample, a reproduction, a source of record.

Then rewrite the prompt so it asks for exactly that, as one block the user can paste back or approve. Keep it the same size of task: deeper means better evidence and a stronger check, not more deliverables.

Leave the choices that are the user's open instead of deciding them — scope, budget, which result matters, anything irreversible — and list them under the rewrite as open questions with your lean.
