# Plan: Blog Post — Safety Pre-Training Is Under-Addressed

## Context

The AI safety community has focused overwhelmingly on post-training alignment (RLHF, constitutional AI, model specs, confessions). But a growing body of evidence suggests pre-training data shapes model values, safety, and robustness more deeply than post-training can correct. This post argues that safety pre-training is neglected, potentially high-impact, and deserves more research attention.

**Audience:** AI safety researchers familiar with alignment, RLHF, and constitutional AI.

## File to Create

`src/content/writing/safety-pretraining.md`

### Frontmatter

```yaml
---
title: "Safety Pre-Training Is Under-Addressed"
description: "The case for building safety into models before post-training"
date: 2026-02-09
author: yulong
tldr: "Most safety work focuses on post-training, but emerging evidence shows pre-training data deeply shapes model values and robustness — and these effects persist through fine-tuning. Safety pre-training deserves far more attention."
tags:
  - alignment
  - pre-training
  - safety
  - AI safety
---
```

## Post Structure

### 1. Hook — The consensus (and why it might be wrong)
- The prevailing view: model character is shaped primarily by post-training (RLHF, constitutional AI, model spec, system prompts)
- This has led to a concentration of safety effort on post-training methods
- But what if the foundation matters more than the finish?

### 2. The evidence accumulating for safety pre-training

Walk through the key papers chronologically:

**a) CMU/CAIS/GraySwan — "Safety Pretraining" (Maini et al., Apr 2025)**
- [arxiv 2504.16980](https://arxiv.org/abs/2504.16980)
- Four-component approach: filtering unsafe data, rephrasing unsafe content pedagogically, native refusal datasets, harmfulness-tagging with special tokens
- ASR dropped from 38.8% → 8.4% with no capability degradation
- Companion paper: "When Should We Introduce Safety Interventions During Pretraining?" (Sam et al., Jan 2026, [arxiv 2601.07087](https://arxiv.org/abs/2601.07087)) — earlier interventions → more robust models, effects amplified after downstream finetuning

**b) Anthropic — "Enhancing Model Safety through Pretraining Data Filtering" (Chen et al., Aug 2025)**
- [alignment.anthropic.com](https://alignment.anthropic.com/2025/pretraining-data-filtering/)
- CBRN-focused filtering using classifiers, pretrained from scratch on filtered vs. unfiltered data
- 33% reduction in harmful-capabilities eval performance, <1% capability loss on MMLU/Code/Prose
- Simpler approach than CMU but still effective

**c) EleutherAI — "Deep Ignorance" (O'Brien, Biderman et al., Aug 2025)**
- [blog.eleuther.ai/deep-ignorance](https://blog.eleuther.ai/deep-ignorance/)
- Multi-stage filtering (blocklist + ML classifier) for biorisk data
- WMDP-Bio regressed to near-random chance, minimal general capability loss
- **Key finding: tamper-resistant.** Unlike circuit-breaking, filtered models stayed safe even after fine-tuning on biorisk papers

**d) Brian Christian et al. — "Reward Models Inherit Value Biases from Pretraining" (Jan 2026)**
- [arxiv 2601.20838](https://arxiv.org/abs/2601.20838)
- RMs carry value preferences from their base models despite identical fine-tuning
- Llama RMs favor "agency," Gemma RMs favor "communion" — persists across training conditions
- Implication: pre-training determines values; post-training merely modulates them

**e) Geodesic Research — "Alignment Pretraining" (Tice, Africa et al., Jan 2026)**
- [arxiv 2601.10160](https://arxiv.org/abs/2601.10160)
- Pretrained 6.9B LLMs with varying AI discourse content
- Upsampling aligned AI discourse reduced misalignment from 45% → 9%
- Effects dampened but **persist through post-training**
- Self-fulfilling prophecy: what the training data says about AI behavior becomes the model's behavior

### 3. Why pre-training might be fundamentally different
- **Data volume:** Pre-training ingests orders of magnitude more data than post-training
- **Learning rates:** Higher learning rates during pre-training may embed traits more deeply into weights
- **Tamper resistance:** Deep Ignorance shows filtered models resist fine-tuning attacks (circuit-breaking doesn't)
- **The subliminal learning problem:** Anthropic's "Subliminal Learning" paper (Cloud et al., Jul 2025, [arxiv 2507.14805](https://arxiv.org/abs/2507.14805)) — models transmit behavioral traits through semantically unrelated data (number sequences!). If traits propagate this subtly, post-training may never fully override pre-training biases

### 4. What the community is doing about character more broadly
- **OpenAI:** Deliberative alignment ([arxiv 2412.16339](https://arxiv.org/abs/2412.16339)) — teaching models to reason over rule-based specs (Kantian-flavored)
- **OpenAI:** Confessions method — separate honesty-trained output channel
- **Anthropic:** Virtue-ethics-flavored constitutional AI, persona vectors ([arxiv 2507.21509](https://arxiv.org/abs/2507.21509)), inoculation prompting
- **Open-source:** Sharan Maiya's Open Character Training ([arxiv 2511.01689](https://arxiv.org/abs/2511.01689)) from MATS 7.0 — first open implementation of character training via constitutional AI
- **Nathan Lambert's InterConnects** coverage of character training pipeline
- BUT: almost all of this is post-training. The pre-training stage remains largely untouched in character/values work

### 5. Research directions — low-hanging fruit
- Identify target traits/values from constitutions and model specs; measure them in base models vs. fine-tuned models
- Test trait persistence across training stages on small models (cheap experiments)
- Constitutional AI or "dilutive alignment" at pre-training stage (acknowledging base models lack chatbot coherence)
- Connect persona/steering vector research to pre-training data composition
- Extend subliminal learning findings to safety-relevant traits

### 6. Objections and limitations (red-team section)
- Address in the post or in a dedicated subsection
- Gemini subagents will deep-read papers and flag weaknesses, surprising findings, and things that undermine the narrative

## Implementation Steps

### Phase A — Parallel Research (run concurrently)

**A1. Deep-read papers with Gemini subagents** (background)
- Send 5 core papers to Gemini for detailed analysis
- For each paper: key claims, methodology quality, limitations, anything that undermines the safety-pretraining thesis
- Flag surprising/suspicious findings

**A2. Research ideation — brainstorm unexpected directions** (background, multiple agents)
- Launch 3+ agents in parallel (Gemini, Codex, Claude) with different prompts:
  - **Agent 1 (Gemini):** "Given these 5 papers on safety pre-training, what are the most *surprising* or *non-obvious* research directions? Think beyond the obvious next steps. Consider: adversarial data poisoning as a safety tool, pre-training curriculum scheduling, cross-lingual value transfer, interaction between data mixture and emergent capabilities, pre-training on synthetic alignment data at scale."
  - **Agent 2 (Codex):** "Design 10 concrete, small-scale experiments (<$500 compute) that could test safety pre-training hypotheses. Each should have clear hypothesis, methodology, expected result, and what a surprising result would mean."
  - **Agent 3 (Claude):** "Red-team the safety pre-training thesis. What are the strongest counterarguments? Under what conditions would pre-training safety be *worse* than post-training safety? What failure modes does it introduce that post-training doesn't?"
- Each agent produces a ranked list of ideas

**A3. Cross-rank ideation results**
- After A2 completes, feed all ideas to a single agent for peer-ranking
- Rank by: (1) feasibility/testability, (2) expected impact, (3) unexpectedness/novelty
- Top 5-8 ideas go into Section 5 of the post

### Phase B — Writing

1. **Draft the post** — Write `src/content/writing/safety-pretraining.md` incorporating A1 findings and A3 ranked ideas (can start in parallel with A2/A3 for sections 1-4)
2. **Red-team the draft** — Use `writing-toolkit:red-team` agent to find counterexamples, unstated assumptions, strongest objections
3. **Review for LLM-isms** — Use `writing-toolkit:humanizer` to flag and fix cliches
4. **Clarity review** — Use `writing-toolkit:clarity-critic` for final polish
5. **Build and verify** — `bun run build` to confirm the post renders correctly

## Verification

- `bun dev` — check post renders at `/writing/safety-pretraining`
- Verify frontmatter renders correctly (title, tldr, tags, date)
- Confirm links to papers work
- Read through for coherence, voice match (first-person, conversational, concrete)
