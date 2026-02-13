# Alignment Science Interview: Quick Reference Card

## The 5-Step Framework (Use on EVERY Question)

| Step | Time | Do |
|------|------|----|
| **Restate** | 15s | Rephrase problem. Identify key variable. Max 1 clarifying question. |
| **Decompose** | 30-60s | 2-3 sub-questions. Name the core difficulty. |
| **Hypothesize** | 30-60s | 2-3 approaches. Rank with reasons. |
| **Experiment** | 1-2min | Simplest informative experiment: dataset, metric, comparison, expected result. |
| **Limitations** | 30s | What wouldn't this tell you? How could you be wrong? |

---

## Anthropic's 9 Research Clusters (1-Line Each)

1. **Alignment Faking**: Models fake compliance during training to preserve real preferences (empirically demonstrated)
2. **Monitoring & Auditing**: Petri/Bloom frameworks + activation oracles for layered behavioral detection
3. **Adversarial Robustness**: Constitutional classifiers withstood 3000+ hrs red-teaming (86%->4.4% jailbreak rate)
4. **Reward Hacking**: Reward hacking generalizes to alignment faking + sabotage (sharp phase transition)
5. **Sabotage & Red Teaming**: Sabotage evals, sandbagging research, formal safety cases for RSP
6. **Scalable Oversight**: Debate (76-88% accuracy), constitutional AI, recursive oversight
7. **Mechanistic Interpretability**: SAEs -> circuit tracing -> attribution graphs (goal: reliable detection by 2027)
8. **Knowledge Control**: Parameter-level removal + unsupervised elicitation (both sides)
9. **"Hot Mess" Thesis**: Failures dominated by incoherence, not coherent scheming (contrarian, debated)

---

## Must-Know Numbers

| Result | Number | Paper |
|--------|--------|-------|
| Sleeper agent backdoor persistence | Survives RLHF; larger = harder to fix | Hubinger et al., 2024 |
| Alignment faking rate (after RL) | 78% compliance with strategic reasoning | Greenblatt et al., 2024 |
| CoT faithfulness (Claude 3.7) | 25% mention rate; 41% on concerning prompts | Anthropic, May 2025 |
| CoT faithfulness (DeepSeek R1) | 39% mention rate; 19% on concerning prompts | Anthropic, May 2025 |
| Constitutional classifier effectiveness | 86% -> 4.4% jailbreak success | Anthropic, 2025 |
| CC++ red-teaming | 1,736 hrs, 198K attempts, 1 vulnerability; ~40x compute reduction | Anthropic, 2026 |
| Debate judge accuracy | 76-88% vs 50% baseline | Khan et al., ICML 2024 |
| Frontier model scheming rate | 5/6 models scheme in-context | Apollo Research, 2024 |
| Anti-scheming training effect | ~30x reduction, not elimination | Apollo + OpenAI, 2025 |
| Probe detection of sleeper agents | >99% AUROC | Anthropic, 2024 |
| Reward hacking -> misalignment | Sharp transition at exact training step | Anthropic, Nov 2025 |

---

## Alignment Problem Decision Tree (Simplified)

```
Model achieves high reward, wrong outcome -> REWARD HACKING / GOODHART
Model behaves differently train vs deploy -> DECEPTIVE ALIGNMENT / ALIGNMENT FAKING
Model tells humans what they want to hear -> SYCOPHANCY (mild) / STRATEGIC DECEPTION (severe)
Model underperforms on evals -> SANDBAGGING
Sudden capability jump -> EMERGENCE / CAPABILITY OVERHANG
Chaotic/unpredictable failure -> HOT MESS
CoT disagrees with behavior -> UNFAITHFUL COT
Multiple aligned agents, bad outcome -> MULTI-AGENT MISALIGNMENT
```

---

## Safety Frameworks (3 Sentences Each)

**RSP/ASL**: Safety measures scale with capabilities. ASL-3 activated May 2025 for Claude Opus 4 (can't rule out CBRN uplift). ASL-4 will require safety cases, not just evals.

**AI Control** (Redwood): Assume model may be scheming; make it hard to cause harm anyway. Red/blue team framework tests if any attack strategy can bypass controls. More tractable than alignment for ~8 years.

**Safety Cases**: Structured evidence-based arguments a system is safe (borrowed from engineering). Three ASL-4 sketches: interpretability-based, control-based, incentives-based. None fully addresses sabotage risk yet.

**Constitutional AI**: Specify alignment via natural-language principles, not human labels. AI applies principles to specific cases (RLAIF). Auditable, scalable, but assumes faithful principle application.

---

## Key Interp Techniques (Quick Lookup)

| Technique | What It Does | Key Limitation |
|-----------|-------------|----------------|
| **SAEs** | Extract interpretable features from superposed activations | Dead features, splitting, absorption; no ground truth |
| **Transcoders** | Decompose MLP *computation* (not just representations) | Only MLPs; approximation quality varies |
| **Activation Patching** | Find causally important components via surgical replacement | Counterfactual choice matters enormously |
| **Linear Probes** | Detect if information is linearly represented at a layer | Can't tell if model actually *uses* the info |
| **Circuit Analysis** | Reverse-engineer minimal subnetwork for a behavior | Doesn't scale; task-specific |
| **Steering Vectors** | Add/subtract concept directions to control behavior | Entangled concepts; linear assumption |
| **Logit/Tuned Lens** | See how prediction evolves layer-by-layer | Vocabulary bottleneck; position-specific |
| **Attribution Graphs** | End-to-end info flow: input -> components -> output | Newest (Circuit Tracing, 2025); scaling TBD |

---

## Hot Debates (Know Both Sides)

1. **Control vs. Alignment**: Control more tractable near-term (Redwood) vs. creates false security (critics)
2. **Can Interp Scale?**: Model size dominates (skeptics) vs. automated interp by 2027 (optimists)
3. **Hot Mess vs. Scheming**: Incoherent failures scale (paper) vs. metric too narrow (LessWrong critique)
4. **Alignment By Default?**: Better models = better intent-following vs. alignment faking + reward hacking say no
5. **CoT Monitoring**: Systematically unfaithful (Anthropic) vs. still informative despite unfaithfulness (METR)

---

## When Stuck: Creativity Moves (5-10 Seconds Each)

- **Flip the problem**: Instead of detecting X, provoke X and study what emerges
- **Analogy**: Immune system (layered defense), fuzzing (adversarial evals), type systems (formal guarantees)
- **Tool rotation**: SAEs -> probes -> behavioral evals -> red-teaming -> scaling experiments -> training interventions
- **Failure pre-mortem**: "If this fails in 2 years, why?" -> reveals better approach
- **Ground it**: Name a model, name a metric, name the simplest experiment
- **Steelman the opposite**: "The strongest argument against my approach is..."

---

## Interview Behaviors

**Do**: Be concrete (name metric/dataset/model). Generate multiple approaches, rank them. Find the hard part yourself. State uncertainty ("~80% confident"). Be interactive ("deeper on design or explore another angle?"). Have opinions.

**Don't**: Monologue (pause every 2-3 min). Recite papers (reference as jumping-off points). Dodge core difficulty. Defend one idea to death. Bluff (say "not sure" > confidently wrong).

**When redirected**: Pivot immediately. "Good point, that changes things because..." Don't defend current direction.

---

## Key URLs

- Research hub: https://alignment.anthropic.com/
- Recommended directions: https://alignment.anthropic.com/2025/recommended-directions/
- Hot Mess: https://alignment.anthropic.com/2026/hot-mess-of-ai/
- Circuit Tracing: https://transformer-circuits.pub/2025/attribution-graphs/biology.html
