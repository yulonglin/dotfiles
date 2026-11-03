---
name: catch-me-up
description: Catch the user up in chat on what happened since their last message — outcomes in plain words, the live state of each PR, job or agent this session touched — then put every decision still waiting on them, from anywhere in the session, as one ranked bundle of questions. Use only when the user explicitly asks for a catch-up or status — /catch-me-up, "catch me up", "what did I miss", "where are we", "what needs me" — never when a returning user's message asks for new work, since this turn is read-only. Lighter than `debrief` (no page, no review round) and fuller than the built-in `/recap` (which caps at 400 characters and lists no decisions).
---

# Catch me up

Adapted from pstack's `ketchup` skill in [pstack-claude](https://github.com/michael-denyer/pstack-claude) (MIT) and the `ahoy` skill in Kun Chen's (kunchenguid) [firstmate](https://github.com/kunchenguid/firstmate) (MIT), fitted to this setup: decisions are bundled rather than walked one at a time, and output follows `communication.md`.

Assume the user remembers their last message and nothing after it. Task notifications, hook output, subagent reports and system reminders are not user messages and do not set the boundary.

## Gather, read-only

This turn changes nothing: no edits, no new jobs, no posts.

1. **Boundary.** Find the user's last real message before this invocation. If compaction hid it, say the exact boundary is unavailable and summarise only what is visible.
2. **What happened since.** Your own work, subagent and workflow results, and anything another session sent.
3. **Live state.** For each PR, CI run, background job, workflow or agent this session touched, check its current state now (`gh pr view`, `gh pr checks`, the job's output directory, the agent's completion notice). The transcript says what was true then; the user needs what is true now. Re-check every number against its source.
4. **Open decisions, whole session.** Scan the entire visible session, not only the interval, for every call that only the user can make — a choice, an approval, an irreversible step, access you lack — that no later message resolved. A later unrelated message does not close an earlier question. Work you can still do yourself is not a decision. Never invent one to fill the list.

## Reply

1. **First line:** what is waiting on the user, or "Nothing needs you."
2. **What happened**, under 100 words: one bullet per thing the user asked for, saying what came of it and whether it is done, running, failed or unchecked. Name any bug found and fixed on the way. Leave out work that changed nothing for the user. Paths are absolute and artifacts are links, but only those the user needs to act.
3. **Still running or left to do** that you can finish yourself, in one line.
4. **Decisions**, ranked by impact, each with the call, your pick, what it changes, the evidence for the pick, and the risk (even when low). Then ask them all at once with `AskUserQuestion` — up to four per call, several calls in one message — recommended option first. In a background job, follow with `needs input:` on its own line.

If nothing happened and nothing waits on the user, say so in one sentence and stop.

Use a diagram only when it carries something prose cannot (a PR stack with each PR's state, a before-and-after); never draw a status list. For a long unattended stretch that deserves a reviewable record, offer `debrief` in one line instead of growing this reply.
