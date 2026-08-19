# Low-Bar Experiments

When something looks off, or an idea shows up mid-conversation, the default is **run a small experiment**, not write a paragraph about it. Prose about an empirical question is the expensive option: it costs a round-trip, it does not settle anything, and it invites agreeing-sounding speculation. A 20-minute run under $100 settles it.

This is a bias, not a licence to burn budget. The spend gate in `workflow-defaults.md` still applies (under $100 → run now and report the estimate with the result; $100+ → propose and wait), and `fail-fast-pilots.md` still gates scale-up on a 1-2 sample end-to-end pilot.

## The trigger

Any of these, noticed by either of us, is enough:

- A number that does not fit the story, or a story with no number under it.
- "That seems bad" / "is X or Y better?" / "would that even work?" — a question whose answer is an arm, not an opinion.
- A design smell in our own code that might have already contaminated a result.
- A mechanism claim that has been asserted twice without being tested once.

The bar for **speccing** is likewise low: a spec here is the three mandatory sections of `spec-conventions.md` and often fits in a message. Don't escalate a two-arm contrast into a document.

## The loop

1. **Say the prediction before the run.** One sentence, written down where the run can be checked against it (a manifest field, not just chat). A result that could not have come out the other way was not an experiment.
2. **Check the design with 2-3 uncorrelated models** before spending — `second-opinions.md` for the channels. Brief them identically, blind to each other and to the result you expect. Cheap relative to a wrong arm; catches confounded treatments, missing nulls, and leaking parameters. Their agreement is not evidence, but their objections are a checklist.
3. **Measure feasibility offline first.** Almost every "can we even test this?" has a free answer in data already on disk — pool sizes, label counts, overlap. Do that before proposing a spend.
4. **Run it, small.** One contrast, matched everything else, a pre-stated null, and an arm that can lose.
5. **Report the estimate beside the result**, and report it whichever way it came out.

## What makes a follow-up cheap enough to just run

Reuse the frozen instrument: same prompt sha, same k, same draws, same episodes, same aggregation. A follow-up that changes one thing is a contrast; a follow-up that rebuilds the harness is a project and gets a real spec. If a new arm needs a new renderer, a new note, or a different k, say so out loud — those are the parameters that have historically moved results more than the treatment did.

## Exploratory versus confirmatory, stated in the artifact

Sweeping many variants to see what wins is fine and often the point. Say which it was. A variant picked because it won on this data is a hypothesis, and it needs a held-out or fresh-episode confirmation before it is quoted as a result. Never let a sweep's winner enter the write-up wearing a p-value from the sweep that selected it.
