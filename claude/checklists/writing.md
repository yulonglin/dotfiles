# Writing

Clarity is not politeness or plain style. It is the reader finishing your sentence holding the idea you meant them to hold, and it fails in specific, checkable ways. This file collects the rules that survive contact with a real draft, ordered by how much a violation costs the reader.

## Use PEEL as the unit of writing, and together the points across these units form the argument

Every paragraph is **Point, Evidence or Explanation, Link back to the point.** State the claim; give what supports it; close by connecting back, so the reader leaves holding the idea they entered with. A paragraph that ends on its evidence leaves the reader to infer the claim, and they will infer a different one.

The paragraphs then have to add up. A narrative is a sequence of PEEL units — A, B, C — arranged so the sequence itself argues something. **Read only the first sentence of each paragraph, and that should form the argument of the passage.**

This catches the failure that is invisible one paragraph at a time: a run of well-formed paragraphs whose points do not compose reads as competent and says nothing. Every unit passes; the whole fails.

## In the opening, incite instability and say what it costs the reader
<!--FIXME: I'm somewhat skeptical of this section-->

Open by making something the reader cares about visibly unstable, then name what that instability costs *them*. McEnerney: *"you have to generate a sense of instability. Words like, but, however, inconsistent, although, anomaly, show the situation to be unstable"* — and then *"show them that the instability imposes a cost on them. Not on you. On them."*

Locate the problem in the reader's world, never in your own curiosity. *"You open with: What I show you on page 8 is a problem. Whose problem? Readers. Not... your problem."* Value *"lies in readers, not in the thing"*. An opening that explains why you found something interesting has not started yet. [Craft of Writing Effectively](https://singjupost.com/the-craft-of-writing-effectively-larry-mcenerney-transcript/)

## Sentence position carries more meaning than word choice

These are the highest-yield mechanics, all from Gopen & Swan's reader-expectation principles [The Science of Scientific Writing](https://www.gatsby.ucl.ac.uk/~pel/misc/gopen_swan.pdf):

**Start with what the reader already holds; end with what you want stressed.** Old information in the topic position links backward; the **stress position** before the full stop is where the reader expects the new idea worth emphasising. Then check that what actually lands there is what you meant to stress — trailing qualifiers, citations and hedges steal that slot.

**Follow a grammatical subject as soon as possible with its verb.** Anything long wedged between them *"is read as an interruption"*, and the reader *"resists recognizing anything in the interrupting material as being of primary importance"*.

**Put the action in the verb, not in a noun made from a verb.** *"Articulate the action of every clause or sentence in its verb."* Williams names the failure — nominalisations — and the fix: turn them back into verbs, so the subjects name the characters and the verbs name what those characters do. [Williams, *Style*, via [summary](https://www.antoinebuteau.com/lessons-from-joseph-m-williams-joseph-bizup/) — secondary source]

**One unit, one job.** *"Any unit of discourse, no matter what its size, is expected to serve a single function, to make a single point."* This is the same rule as PEEL, applied to sentences and sections as well as paragraphs.

**Give context before anything new.** *"Provide context for your reader before asking that reader to consider anything new."*

**A sentence is too long when it holds more ideas worth stressing than it has stress positions.** That is a test you can apply; word count is not.

Gopen & Swan disown mechanical application of their own principles, and the caveat belongs here: *"None of these reader-expectation principles should be considered 'rules.' Slavish adherence to them will succeed no better than has slavish adherence to avoiding split infinitives... any reader expectation can be violated to good effect."*

## Hedge to the evidence class, and never blur whose result it is

Commit to one to three concrete claims, and make every section earn its place against them — for each section you should be able to say how it contributes and why removing it would hurt. *"One important claim, with sufficiently strong evidence, can be enough for a great paper."*

Match the strength of each claim to the evidence class behind it: an **existence proof** needs at least one example; a **systematic** claim needs wide-context evidence; a **narrow** claim must state its precise conditions. *"Resist the temptation to overclaim for clicks."* [Nanda, Highly Opinionated Advice on How to Write ML Papers](https://www.lesswrong.com/posts/eJGptPbbFPZGLpjsp/highly-opinionated-advice-on-how-to-write-ml-papers)

**Never let a sentence leave ambiguous whether a result is yours or prior work's.** Misrepresenting prior work *"poisons the field, annoys your colleagues"*. Use one term per concept and never a synonym for work-specific terminology; treat every adjective as a suspected unsupported claim; expand each acronym before using it. [Foerster, How To ML Paper](https://www.jakobfoerster.com/how-to-ml-paper)

**Describe a figure at the level of its marks, not its conclusions** — talk about the lines and the points, rather than only what you take them to show, and check that what you said about them is actually true. [Farquhar, How to Write ML Papers](https://sebastianfarquhar.com/on-research/2024/11/04/how_to_write_ml_papers/)

## The abstract, intro and figures carry the reading

Most readers stop early: many read the abstract, some read the intro or skim the figures, few read the whole thing — so those three earn as much editing effort as everything else combined, which is most of the words. Effort spread evenly across the document is effort spent mostly where nobody is looking [Nanda, above]. What that effort has to buy is checkable in the draft: **the abstract states the claim, its evidence class and one limitation**; the introduction ends with the claim in a single sentence; and each figure's caption says what to see in the figure without the body text.

Foerster's rule of thumb is that a draft carries about a third fluff, cut on the final pass [Foerster, above]. Check what is left rather than what was deleted: **no sentence only restates its neighbour, no paragraph opens by announcing what it is about to do, and the conclusion says something the introduction did not.**

## You cannot imagine a naive reader, so reread cold instead

The curse of knowledge is *"a difficulty in imagining what it is like for someone else not to know something that you know"*, and the remedy is mechanical rather than imaginative: *"Show a draft to yourself, ideally after enough time has passed that the text is no longer familiar."* That last is a working habit, not something a reader can check — but what the cold reread looks for is: **every abstraction on the page is either defined there or replaced by something a reader could see**, because classic style *"minimizes abstractions, which cannot be seen with the naked eye"*. [Pinker, *The Sense of Style*, via [summary](https://sive.rs/book/SenseOfStyle) — secondary source]

**Where McEnerney and Pinker disagree, and how to resolve it.** McEnerney says do not explain — *"you explain stuff under the model of demonstrating to somebody that you understand it"*. Pinker says the curse of knowledge is fixed precisely by explaining: spell out the logic, supply the detail. They are addressing different readers. McEnerney is talking to experts writing for their own field, where explanation reads as a competence display; Pinker is talking to writers whose readers genuinely lack the background. For a mixed AI-safety readership: **Pinker governs mechanisms, McEnerney governs motivation.** Explain how the thing works; do not explain why you find it interesting.

## Cut the LLM tics, because they cost clarity — not because they sound artificial

The goal is not to sound human. It is that each of these actively obscures the point:

- **Hedging openers** — "It's worth noting that", "Interestingly", "It is important to consider" — occupy the topic position with nothing, delaying the sentence's real subject.
- **False enthusiasm** — "Great question", "This is a fascinating area" — spends the reader's attention on your reaction rather than the claim.
- **Padding** — restating the question, excessive context-setting, a conclusion that repeats the introduction.
- **Uniformity** — every paragraph the same length and shape, so nothing signals which one matters.
- **Refusing to take a position** — presenting "both sides" where the evidence favours one. If you have a lean, state it and mark its confidence.
- **Bullet points for narrative or argument.** Chains of "because A, therefore B" belong in prose, where the connectives carry the logic. Save bullets and tables for comparable data and parallel independent items.
- **Dramatic framing** — "confesses", "blabbers", "clear win", "earns its keep" — trades precision for story; state what happened in the register the evidence supports.
- **Narrative self-reference** — "this half of the report", "five findings carry the report", "the most useful single view of our data" — the document talking about itself instead of the subject.
- **Lecturing the self-evident** — explaining standard practice the venue's readers already know (why results compare to chance). If every reader knows it, cut it.
- **Provoking and deferring** — a claim that raises "why?" or "which ones?" and answers somewhere else. Carry the answer in the same sentence or the next.
- **Aphoristic headings and openers** — a metaphor standing in for the thing named ("the hardest corner", "sabotage lives past the end of them"), a referent the reader must read on to decode ("the one we care about", "the most direct fix" — the heading-and-opener form of provoking and deferring), a second clause whose meaning arrives only after the paragraph, or an abstract noun as subject where the actor belongs ("Detection difficulty tracks..." rather than which method missed which sandbaggers). Two clauses are not the fault: "No Single Method Dominates; the Two Are Complementary" states both halves plainly and needs no body. What fails is withholding the point until the body — and the setup a punchline needs is why these run 10 to 13 words while plain two-clause headings stay at six to eight. The test, applied before the body is read: the line is understandable on its own, it names the concrete actor and the finding, and it could not headline three different paragraphs. "Detection difficulty tracks the threat model, and the hardest corner is the one we care about" plainly is **"C³ misses trained and emergent sandbaggers — 19% recall on the threat models that matter most."**

## Reference drafts worth calibrating against

ML papers where the first paragraph frames the problem without waste, threat models are stated upfront, figures earn their space, and limitations are stated matter-of-factly rather than apologetically. Technical blogs with voice and depth — Ferenc Huszár ([inference.vc](https://www.inference.vc/)) among them. What to notice in each: the first sentence of every section does real work, concrete examples arrive before abstractions, and claims are direct — *"We find X"*, not *"our results suggest that X may potentially"*.

## Related

Page, slide and report form, where numbers go, and terminology: `presentation.md`. Results pages: `results-analysis.md`. `reduce-ambiguity` red-teams a finished draft for how it could be misread. `clarity-critic`, `narrative-critic`, `red-team` and `fact-checker` are the critic agents `review-draft` dispatches.

<!--TODO: The best pieces of writing I know are:
http://www.incompleteideas.net/IncIdeas/BitterLesson.html
https://arxiv.org/pdf/2312.06942
https://arxiv.org/html/2402.06782
Kaiming He's papers
-->
