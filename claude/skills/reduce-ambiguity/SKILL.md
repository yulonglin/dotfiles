---
name: reduce-ambiguity
description: Reduce ambiguity in a draft before it is sent or acted on — specs, briefs, results pages, prompts. Use on "is this clear", "will this be misread", "red-team this doc".
---

# Check Misreads

The cost of a misread scales with what happens next. A misread chat reply costs one clarifying message; a misread handoff brief burns the hours or days of unattended work that follow it. Run this pass before sending a draft to someone, or before acting on one yourself, whenever being read the wrong way is expensive:

- **A handoff brief and the answers it rests on**, before committing to a long unattended run — the highest-value target on this list, because nobody is watching to catch the divergence. It counts even though you wrote it and are the one executing it
- **Results and findings pages**, where a construal error becomes a wrong conclusion someone acts on
- **Specs and plans**, which exist to be executed by someone who cannot ask you what you meant
- **Rules, prompts and instruction files**, read by a model that will follow them literally

The exemption is cost, not category. Chat replies, status and failure reports are cheap to correct and skip the pass — but a long findings page does not become exempt by being labelled a status update.

## Two readers, not one

A cooperative reader resolves ambiguity silently: it picks the likeliest reading, lands on your intent by luck, and never mentions the branch it walked past. So ask both questions.

**Cooperative pass** — "what did you understand this to claim, and what would you still need to ask before you could act on it?" A misread in its summary is an ambiguity in the draft. A question it has to ask is a hole in the draft — unless it is asking about a choice you deliberately left to whoever executes, which is latitude rather than a gap. Filling those in over-constrains the run.

**Adversarial pass** — "for each load-bearing sentence, give up to three plausible readings, and say what you would do differently under each." Load-bearing means the sentences a downstream action depends on; let the reader pick them, since which sentences carry weight for a stranger is part of what you are testing. A sentence with only one honest reading is dropped, never padded out to a second — manufacturing alternatives reintroduces exactly the noise the next section exists to kill.

Never ask "is this clear?". It returns "yes, quite clear" from any reader, because agreeing is the cheapest way to answer it.

## Only behaviour-changing findings count

This is the rule that keeps the pass from becoming a nitpick generator. Language always underdetermines, so a reader asked for ambiguity will always find some. Require every finding to name **the action that changes** between the two readings. No behaviour delta, no finding.

Rank what survives by the cost of acting on the wrong reading and fix from the top, stopping once that cost falls below the cost of the rewrite. A finding that would only have cost one clarifying message is not worth a paragraph.

## Running it

You run this on your own draft: you dispatch the readers, they report, you make the fixes. No reader is asked to edit anything. The payload is the draft as its audience will meet it — for a handoff brief, that means the brief together with the answers it rests on, as one document.

Prefer a **different model family**, which does not share the priors that made your phrasing feel obvious — `openrouter-cli ask <alias>`, or `council` to pick the channel. A same-family subagent ranks below it rather than beside it, but it is the sanctioned fallback (`~/.claude/rules/delegation.md`) and not a token one: unlike factual verification, generating alternative readings does not depend on different priors the way catching your own error does. When no key resolves, use fresh subagents rather than skipping the pass, and say which reader you used.

The reader gets **the draft and the pass question, and nothing else** — no conversation, no statement of intent, no explanation of what you were going for. The moment you tell it what you meant, it can no longer tell you what you wrote. A reader that cannot follow the draft without the context you withheld has produced the strongest finding available and should say so rather than ask for the context.

Dispatch the two passes as **two agents in one message**, never as one agent given both prompts: a single reader's cooperative summary anchors its own adversarial list. Cap each at ten one-line findings, applied after the behaviour-delta filter, so what comes back is a reviewable list rather than an essay.
