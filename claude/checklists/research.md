# Research

Brainstorming and experiment design. AI safety differs from capabilities work in that the problems are less clearly defined and there is rarely a single number to make go up — so most of the work is in choosing what to measure at all, and in designing the experiment before anything runs.

## An idea is ready when it could come out the other way

**Design for two-sided surprise.** A good experiment is one where *either* result updates someone. If only one outcome is interesting, redesign it. Say the prediction before the run, in the manifest rather than in chat — a result that could not have come out differently was not an experiment. The checkable form is the manifest: it names the prediction and the planned `n` before the first scored call.

**If you cannot define the measurement, the idea is not ready.** "How would I score this?" is the question that kills most candidates, and it should kill them early rather than three days in. Metrics or evals are gold.

**Sort by time-to-first-signal, not by ambition.** Carlini explicitly picks problems where he can get a signal in a day; prefer those.

## Three ways to generate

**Operationalise a fuzzy concept as a dumb behavioural experiment** (Owain Evans). Take something from cognitive science or philosophy — introspection, self-knowledge, situational awareness, honesty under pressure — and ask for the simplest prompt-or-finetune experiment separating "models have this" from "they don't"; the reversal-curse and emergent-misalignment papers are basically this template. The train-on-A, test-for-implied-but-never-stated-B pattern is unusually generative: finetune on a narrow behaviour, then probe for out-of-context generalisation. What the template becomes in a specific research area belongs in the `results-analysis/` subskills — `sandbagging.md` carries the sandbagging instance. A small narrow finetune does not make the causal story clean — it is exactly where dataset cues, response length and formatting confounds dominate, and emergent misalignment is itself the demonstration that narrow finetunes generalise in directions nobody intended. So name the causal factor you mean to vary and the cheapest competing explanations for the same result — dataset cues, length, format, verbalised eval awareness — and run at least one confound-matched or scrambled-label control beside the headline arm.

**Delete until it breaks** (Kaiming He). Take an existing complex method — a CoT monitor, a probing pipeline, an elicitation technique — and remove components one at a time. **Whatever survives deletion is the next hypothesis** — deletion is sequential, so interactions, order effects and compensating mechanisms all hide in the remainder; confirm it with a one-factor contrast on held-out episodes before quoting it. MAE is "what if we just mask 75% and do nothing clever". Before proposing anything, name the embarrassingly simple baseline — a linear probe on the residual stream, or just asking the model — since establishing that the simple thing works is itself a result. When a method fails, ask what trivial case it should at least express (the ResNet identity-mapping insight): if a method for hidden reasoning cannot recover reasoning the model states openly, fix that before chasing anything hidden. One variable per experiment is the default, and his ablation tables are the model — every row differs from the default by exactly one thing.

**Be the adversary, and write the threat model first** (Carlini). Spend an hour genuinely trying to break any defence, monitor or eval — including your own — with the *simplest* adaptive attack (a timebox, so advice rather than a checkable item); most published defences die to this, and "we broke X" is a faster, more informative paper than "we built Y". Optimising against your own monitor is not a robustness check bolted on at the end; it is the experiment. Write the threat model in one paragraph before designing anything, and half the ideas will die or sharpen immediately ("wait, who controls the prompt here?"). That one is checkable: a threat-model paragraph exists, and it names who controls the prompt.

## Filling the queue

**Matrix crossing.** Rows are methods you have (linear probes, finetuning, paraphrasing, NLA-style latents); columns are failure modes (sandbagging, eval-gaming, obfuscated CoT, sycophancy). Every cell is a candidate. Most are bad; a few are not.

**Inversion.** Take a result you believe and flip one assumption. "Probes detect sandbagging" — does that survive training the model against the probe? Does it transfer across model families? Each flip is an ablation.

**Falsification mining.** Read a claim in a paper or an Alignment Forum post and ask what experiment would falsify it. Cheap, and the resulting projects are well motivated by construction.

**Babble and prune.** Thirty minutes, thirty ideas, no quality filter — a timebox, so advice rather than a checkable item. Then prune on three tests: time-to-signal, two-sided surprise, and whether the measurement exists yet.

**The loop:** babble thirty, prune to three with the day-test, and run the survivor through deletion before building anything.

## Brainstorming

1. Highlight assumptions
2. Iterate over related methods in AI safety
3. Iterate over related ideas from other fields
4. Work backwards from future models
5. Break the problem down into subtasks
6. What are our key areas of uncertainty? Maybe we can probe more there!
7. The SCAMPER Technique: Apply seven lenses to an existing theory or problem—Substitute, Combine, Adapt, Modify, Put to another use, Eliminate, and Reverse—to spark fresh angles or unconventional hypotheses

## The design is not done until the alternatives are named

State the research question in one sentence, phrased so that it's falsifiable, and an outcome could contradict it — otherwise call the work exploratory and say so. Name the independent variable and its levels, **including anything varied by accident**: a changed prompt, renderer or model version is an independent variable whether or not you meant it to be. Name the dependent variable, its unit of analysis and how it aggregates. Name the null.

**Every causal contrast declares which factors it changed and what its matched control is.** One factor at a time is the default and it is usually right, but it cannot see an interaction: model, prompt, scaffold and monitor move together often enough that a one-factor sweep can hand the whole effect to whichever factor happened to move first. Where an interaction is plausible, run a randomised factorial small enough to afford and report main effects and interactions separately, rather than reading a stack of one-factor rows as if they added up.

**Ask what alternative explanations exist, and design the ablation that separates them** — an alternative explanation you cannot ablate away is a caveat the result will carry forever. Plan the ablations with the experiment, not after the headline number.

## Related

Running the thing: `experiments.md`. Analysing what came back: `results-analysis.md`. Presenting it: `presentation.md`. Research-integrity rules that apply always: `~/.claude/rules/research-core.md`.
