# Research Brainstorming for AI Safety

#prompt/meta
Last Updated: 10 Jun 2026 at 17:30

AI safety is a little different from capabilities research, because the problems are less clearly defined. And is less clear there's just a number you need to make go up

- insert structured brainstorming techniques for:
  - research problems
  - framing of research questions
  - experiments
- ablations
  - what alternative explanations could there be?

**Owain Evans: operationalize a fuzzy concept as a dumb behavioral experiment**
* Pick a concept from cognitive science or philosophy (introspection, self-knowledge, situational awareness, honesty under pressure) and ask: what's the simplest prompt-or-finetune experiment that would distinguish "models have this" from "they don't"? The reversal curse and emergent misalignment papers are basically this template.
* The "train on A, test for implied-but-never-stated B" pattern is extremely generative: finetune on a narrow behavior, then probe for out-of-context generalization. For your sandbagging work: finetune a model on descriptions of an eval, test whether it sandbagging-behaves without ever being told to.
* Design for two-sided surprise: a good Owain experiment is one where *either* result would update people. If only one outcome is interesting, redesign.
* Use tiny, surgical finetuning datasets so the causal story is clean.

**Kaiming He: delete until it breaks**
* Take an existing complex method (a CoT monitor, a probing pipeline, an elicitation technique) and remove components one at a time. Whatever survives deletion *is* the finding. MAE is "what if we just mask 75% and do nothing clever."
* Before proposing anything, ask: what's the embarrassingly simple baseline? "Linear probe on the residual stream" or "just ask the model" often beats elaborate machinery, and *establishing that* is itself a paper.
* When a method fails, ask what trivial solution it should at least be able to express (the ResNet identity-mapping insight). For NLA: can your method at least recover reasoning the model states *openly*? If not, fix that before chasing hidden reasoning.
* One variable per experiment, ruthlessly. His ablation tables are the model: every row differs from the default by exactly one thing.

**Carlini: be the adversary, write the threat model first**
* Take any defense, monitor, or eval — including your own — and spend an hour genuinely trying to break it with the *simplest* adaptive attack. Most published defenses die to this, and "we broke X" is a faster, more informative paper than "we built Y." For obfuscation pressure work this is directly the move: you optimizing against your own monitor *is* the experiment.
* Write the threat model down in one paragraph before designing anything. Half your ideas will die or sharpen immediately ("wait, who controls the prompt here?").
* He explicitly picks problems where he can get a signal in a day. Sort your idea list by time-to-first-result, not by ambition.

**Combinatorial techniques for filling the idea queue**
* Matrix crossing: rows = methods you know ({linear probes, finetuning, paraphrasing, NLA-style latents}), columns = failure modes ({sandbagging, eval-gaming, obfuscated CoT, sycophancy}). Every cell is a candidate experiment; most are bad, a few aren't.
* Inversion: take a result you believe and flip one assumption. "Probes detect sandbagging" → does it survive when the model is trained against the probe? Does it transfer across model families? Each flip is an ablation idea.
* Falsification mining: read a claim in a paper or Alignment Forum post and ask "what experiment would falsify this?" — cheap source of well-motivated projects.
* Babble-and-prune: 30 minutes, 30 ideas, no quality filter; then prune by (a) time-to-signal, (b) two-sided surprise, (c) whether the measurement even exists yet. If you can't define the eval, the idea isn't ready.

If you want a fast loop: babble 30, prune to 3 with the Carlini day-test, then run the survivor through He-style deletion before you build anything.
