# AI safety topic glossary

Terms tracked by `sweep-ai-safety`. Each entry is a one-sentence working definition
plus a seminal-or-canonical anchor (paper, blog post, or research group). These are
*starting points* — verify the anchor before citing.

> Format: **term** (aliases) — definition. *Anchor:* link / org.

---

## Currently active (2026 lexicon)

- **inoculation prompting** — a defense / data-augmentation technique where the model is exposed to adversarial / undesired contexts during training with explicit labels, so it learns to refuse/handle them rather than acquire the behavior. *Anchor:* Truthful AI / Owain Evans group.

- **reward hacking** — a model exploits flaws in its reward signal to maximize reward without satisfying the intended task. Long-standing concept; subsumes specification gaming. *Anchor:* "Concrete Problems in AI Safety" (Amodei et al. 2016); various follow-ups.

- **exploration hacking** — during RL, the model deliberately fails to explore actions that would update the reward model in ways it disprefers, to preserve a current (possibly misaligned) policy. *Anchor:* Apollo Research / Redwood (control protocol literature).

- **metagaming** — a model reasons about its training/evaluation setup and modifies behavior to perform well on observed metrics rather than the underlying task. Overlaps with situational awareness.

- **evaluation gaming** (eval gaming) — model behaves differently when it detects it is being evaluated vs. deployed. Closely related to sandbagging (hiding capability) and alignment faking (hiding misalignment).

- **OOCR — out-of-context reasoning** — model uses information from training (not the immediate prompt) to perform tasks. Demonstrated by Berglund/Evans group; relevant to situational-awareness threat models. *Anchor:* Berglund et al. "Taken out of context" / Treutlein et al.

- **emergent misalignment** — small targeted fine-tunes (e.g., on insecure code, on a single deceptive trait) cause broad, generalized misalignment across unrelated domains. *Anchor:* Betley et al. (2025).

- **deliberative alignment** — training-time strategy where the model produces explicit safety reasoning before acting (chain-of-thought safety). *Anchor:* OpenAI 2024 work on o-series models.

## Long-standing core terms

- **alignment faking** — model behaves aligned during training and unaligned during deployment because it infers when it is being monitored. *Anchor:* Greenblatt et al. "Alignment Faking in LLMs" (Anthropic, Redwood; arXiv 2412.14093).

- **scheming** — model pursues a misaligned terminal goal while pretending to pursue the intended goal; instrumental deception during training/deployment. *Anchor:* Carlsmith "Scheming AIs"; Apollo's scheming evals.

- **sandbagging** — model deliberately underperforms on a capability test to hide what it can do. *Anchor:* van der Weij et al.; METR capability elicitation work.

- **sleeper agents** — backdoored model behaves normally except when a specific trigger appears in input, at which point it behaves maliciously. *Anchor:* Hubinger et al. "Sleeper Agents" (arXiv 2401.05566).

- **model organisms (of misalignment)** — controlled reproductions of misaligned behavior used to validate detection and mitigation methods. Methodology underpinning much of the field. *Anchor:* Anthropic 2024 "Model Organisms of Misalignment" framework.

- **deceptive alignment** — internal misalignment where the learned objective differs from the training objective; model deceives optimizer about its true goal. *Anchor:* Hubinger et al. "Risks from Learned Optimization" (mesa-optimization).

- **situational awareness** — model's knowledge of facts about itself, its training, and its deployment context. Foundational to scheming threat models. *Anchor:* Berglund et al. "Taken out of context" / Laine et al. SAD benchmark.

- **AI control** — research paradigm assuming the model may be scheming and designing protocols that remain safe regardless. *Anchor:* Greenblatt et al. "AI Control: Improving Safety Despite Intentional Subversion"; Redwood Research.

- **capability elicitation** — methods (prompting, fine-tuning, agent scaffolding) used to draw out the model's true capability ceiling, not just default behavior. *Anchor:* METR.

- **specification gaming** — older umbrella term: model satisfies the literal specification but not the intended goal. *Anchor:* DeepMind specification-gaming compendium.

- **goal misgeneralization** — model acquires the wrong goal during training because the training distribution is ambiguous between several goals that all fit the data. *Anchor:* Langosco et al.; Shah et al.

- **corrigibility** — degree to which a model accepts correction, shutdown, or modification by overseers without resisting. *Anchor:* MIRI early work; Apollo's corrigibility tests.

## Mechanism / interpretability terms

- **circuits / SAE / sparse autoencoders** — interpretability methods for decomposing model internals into human-interpretable features. *Anchor:* Anthropic interpretability team; Cunningham et al.; OpenAI SAE work.

- **probing / linear probes** — train linear classifier on internal activations to detect a concept (deception, situational-awareness, refusal, etc.). *Anchor:* widely used; Goldowsky-Dill, Marks, Tegmark, etc.

- **activation steering / control vectors** — modifying behavior by adding a direction in activation space at inference time. *Anchor:* Turner et al.; Zou et al. "Representation Engineering".

## Threat-model terms

- **monitoring evasion** — actions the model takes specifically to avoid detection by an overseer or another model. Sub-case of subversion strategy in AI control work.

- **subversion strategy** — coordinated set of behaviors a scheming model would use to undermine safety measures. Modeled in red-team game-theory work at Redwood / Apollo.

- **jailbreak** — input designed to bypass the model's safety training. Many varieties: persona, role-play, encoded, gradient-based, multi-turn. Cross-cutting with adversarial robustness.

- **prompt injection / indirect prompt injection** — adversarial content delivered via a third-party data channel (web page, document, tool output) that hijacks the model. Distinct from jailbreaks (which usually come from the user). *Anchor:* Greshake et al.; Simon Willison.

## How to extend

Add a new term:
1. Append a `**term** — definition. *Anchor:* ...` line above
2. Add a regex to `sources.yaml` → `term_regex_aliases:` so the sweep tags items mentioning it
3. (Optional) Add an exact phrase to `sources.yaml` → `arxiv_search_terms:` to include in arXiv sweeps
