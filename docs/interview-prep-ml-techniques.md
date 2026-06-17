# ML Training & Evaluation Techniques for Alignment Research

A technical reference for Anthropic Alignment Science interview preparation.

---

## Conventions and Common Understandings

**Alignment (narrow vs broad).** Narrow alignment: the model follows user instructions and behaves as intended by developers. Broad alignment: the model acts in ways that are beneficial to humanity, even in novel situations without explicit instructions. Anthropic's work spans both but increasingly focuses on the broad sense -- ensuring models remain safe as capabilities scale beyond human ability to fully supervise.

**The HHH Framework.** Anthropic's foundational behavioral specification. **Helpful**: assists the user effectively. **Honest**: doesn't deceive, acknowledges uncertainty, represents its own nature accurately. **Harmless**: refuses to assist with dangerous activities, avoids causing harm even when instructed. These properties can conflict (a maximally helpful response to a harmful query is not harmless), and much of alignment research is about navigating these tensions.

**Capability vs alignment distinction.** Capability = what a model *can* do (coding, reasoning, persuasion). Alignment = whether it *does what we want*. These scale at different rates. The core worry: capabilities may advance faster than our ability to align them. A highly capable but misaligned system is more dangerous than a less capable one.

**Alignment tax.** The performance cost of making a model aligned vs purely maximizing capabilities. If the alignment tax is high, there's economic pressure to deploy less-aligned systems. A central goal of alignment research is to minimize this tax -- making alignment techniques that preserve or even improve useful capabilities (Constitutional AI and RLHF often *improve* helpfulness while adding safety).

**Safety case.** Borrowed from engineering safety: a structured, evidence-based argument that a system is safe to deploy in a given context. Anthropic's ASL framework requires increasingly rigorous safety cases at each AI Safety Level. For ASL-4, Anthropic has sketched three approaches: (1) mechanistic interpretability (understand the model's internals well enough to verify alignment), (2) AI control (assume the model *might* be misaligned and design protocols that limit harm), and (3) incentives analysis (show the model has no incentive to behave badly).

**Model organisms methodology.** Anthropic's empirical approach to studying alignment failures. Rather than waiting for misalignment to emerge naturally (dangerous and unpredictable), researchers *deliberately create* misaligned models -- "model organisms" -- to study how misalignment arises, persists, and can be detected.

**The "galaxy-brained" problem.** When a model uses sophisticated reasoning to arrive at conclusions that are technically coherent but practically dangerous or wrong. Particularly dangerous because the reasoning *looks* valid step-by-step but the conclusion violates common-sense safety norms.

**Features vs neurons.** A **neuron** is a single unit in a neural network layer. A **feature** is a human-interpretable concept that the model represents. Features and neurons are not one-to-one. Individual neurons are typically **polysemantic** -- they activate for multiple unrelated concepts. Features are distributed across many neurons.

**Superposition.** The phenomenon where a neural network represents more features than it has dimensions (neurons). Because features in natural data are sparse, the model can "pack" many features into a lower-dimensional space using overlapping, nearly-orthogonal directions.

---

## Training Methods

### 1. RLHF (Reinforcement Learning from Human Feedback)

**What it is.** A three-stage training pipeline that aligns language models to human preferences by training a reward model on human comparisons, then optimizing the policy against that reward model using reinforcement learning.

**How it works.**
- **Stage 1 -- SFT**: Supervised fine-tuning on high-quality demonstrations to produce a base policy.
- **Stage 2 -- Reward model training**: Collect human comparisons (preference pairs: "response A is better than response B"). Train a reward model using the Bradley-Terry preference model: `P(A > B) = sigma(r(A) - r(B))`. Loss is negative log-likelihood of the observed preferences.
- **Stage 3 -- RL optimization**: Optimize the SFT policy to maximize reward model scores using PPO. The objective includes a **KL penalty** term: `R_total = R_reward(x, y) - beta * KL(pi_theta || pi_ref)`, where `pi_ref` is the SFT policy. The KL penalty prevents the policy from diverging too far from the reference, which would exploit reward model errors.
- **Reward model overoptimization** (Gao et al., 2022): As optimization pressure against the proxy reward increases, true quality first increases then *decreases*. This is Goodhart's Law applied to RLHF. Scaling laws exist: more RM data and larger RMs delay overoptimization.

**Alignment relevance.** RLHF is the dominant production alignment technique. Its limitations define much of the alignment research agenda: reward hacking, distributional shift, and the assumption that human preferences are a reliable signal.

**Key papers.** InstructGPT (Ouyang et al., 2022). Scaling Laws for Reward Model Overoptimization (Gao et al., 2022).

---

### 2. DPO (Direct Preference Optimization)

**What it is.** Optimizes language models directly on preference data without a separate reward model or RL, by showing the RLHF objective has a closed-form solution expressible as a classification loss.

**How it works.**
- The optimal policy under KL-constrained reward maximization: `pi*(y|x) = (1/Z(x)) * pi_ref(y|x) * exp(r(y,x)/beta)`. Rearranging: the reward is *implicitly defined* by the policy-reference ratio.
- DPO loss:
  ```
  L_DPO = -E[log sigma(beta * (log pi_theta(y_w|x)/pi_ref(y_w|x) - log pi_theta(y_l|x)/pi_ref(y_l|x)))]
  ```
- The **implicit reward** is `r(y,x) = beta * log(pi_theta(y|x) / pi_ref(y|x))`.

**Alignment relevance.** Dramatically simplifies the alignment pipeline. Known limitations: can underfit complex preferences, sensitive to data quality, still exhibits reward overoptimization at high KL budgets. Variants: IPO, KTO, Dr. DPO (ICLR 2025).

**Key papers.** DPO (Rafailov et al., 2023). Comprehensive DPO Survey (2025).

---

### 3. Constitutional AI (CAI)

**What it is.** Anthropic's method for training harmless AI assistants using AI-generated feedback guided by explicit principles (the "constitution").

**How it works.**
- **Phase 1 -- Supervised self-critique (SL-CAI)**: Generate responses to harmful prompts. Model critiques its own response against constitutional principles. Generate revised response. Fine-tune on (prompt, revised response) pairs.
- **Phase 2 -- RLAIF**: Generate response pairs. Model evaluates which better adheres to constitutional principles. Train RM on AI preferences. Run RL.
- The **constitution** is ~15 natural-language principles. It is the *only human input* to harmlessness training.

**Alignment relevance.** Alignment specified declaratively (via principles) rather than implicitly (via labels). Transparent, scalable, auditable. Foundational to Anthropic's approach and constitutional classifiers.

**Key papers.** Constitutional AI (Bai et al., 2022). Constitutional Classifiers (Anthropic, 2025). Constitutional Classifiers++ (2026).

---

### 4. Process Reward Models (PRMs)

**What it is.** Reward models that provide feedback on *each step* of a reasoning chain rather than only the final answer.

**How it works.**
- **ORMs** score final answer only. **PRMs** score each intermediate step. PRM800K dataset (Lightman et al., 2023): 800K step-level human labels on MATH solutions.
- PRMs enable **best-of-n selection** at the step level.
- **ThinkPRM (2025)**: uses long CoT verification with 1% of PRM800K labels, outperforming discriminative PRMs.

**Alignment relevance.** Directly relevant to CoT faithfulness. Step-level verification catches errors and deceptive reasoning early. Connects to scalable oversight: step verification is easier than evaluating entire arguments.

**Key papers.** Let's Verify Step by Step (Lightman et al., ICLR 2024). ThinkPRM (2025).

---

### 5. RLAIF (Reinforcement Learning from AI Feedback)

**What it is.** Using AI-generated preference labels instead of human labels to train reward models.

**How it works.**
- AI system evaluates response pairs, often guided by principles/rubrics (as in CAI).
- Key result (Lee et al., 2023): RLAIF achieves *comparable* performance to RLHF despite lower RM accuracy. RL is robust to some RM noise.

**Alignment relevance.** First step toward scalable oversight. If AI judges substitute for humans on current tasks, perhaps more capable AI judges can supervise more capable systems. Risk: bias amplification if evaluator shares biases with the trained model.

**Key papers.** Constitutional AI (Bai et al., 2022). RLAIF vs RLHF (Lee et al., 2023).

---

### 6. Fine-tuning Variants

| Method | Mechanism | Alignment Use Case |
|--------|-----------|-------------------|
| **Full SFT** | Standard fine-tuning on (input, output) pairs | Production alignment, model organism creation |
| **LoRA** | Low-rank decomposition `W = W_0 + BA`, r << min(d,k), ~0.1-1% params | Rapid alignment experiments, red-team fine-tuning |
| **QLoRA** | 4-bit quantization (NF4) + LoRA adapters in full precision | Large model experiments on limited hardware |

**Key papers.** LoRA (Hu et al., 2021). QLoRA (Dettmers et al., 2023).

---

### 7. Adversarial Training

**What it is.** Training that explicitly incorporates adversarial attacks during the training loop.

**How it works.**
- **Constitutional Classifiers** (Anthropic, 2025): Input/output classifiers trained on synthetically generated data guided by constitutional principles. Reduced jailbreak success from 86% to 4.4% on Claude 3.5 Sonnet.
- **Constitutional Classifiers++** (Anthropic, 2026): ~40x compute reduction vs exchange classifier baseline via representation re-use (~1% additional overhead on production traffic). ~1,736 hours of red-teaming, only one high-risk vulnerability found.
- **Multi-agent adversarial RL**: RL-trained red-team models continuously generate novel attacks.

**Alignment relevance.** Static safety training fails against adaptive adversaries. Key tension: robustness vs over-refusal. Constitutional classifiers decouple safety from helpfulness.

**Key papers.** Red Teaming Language Models (Ganguli et al., 2022). Constitutional Classifiers (Anthropic, 2025). CC++ (Anthropic, 2026).

---

## Evaluation Methods

### 8. Behavioral Evals

- **Capability evals**: MMLU, HumanEval/MBPP, GSM8K/MATH, ARC
- **Dangerous capability evals**: CBRN knowledge, autonomous replication, persuasion, cyber-offense. Trigger higher ASL requirements.
- **Behavioral safety evals**: Refusal, sycophancy, power-seeking, value consistency.

**Key limitation:** Behavioral evals test *observed behavior*, not *internal alignment*. A deceptively aligned model could pass all evals.

---

### 9. Red Teaming

- **Manual**: Human experts craft adversarial prompts. High quality, doesn't scale.
- **Automated**: LM-generated attacks. GPTFuzz achieves >90% success via mutation.
- **Many-shot jailbreaking** (Anthropic, 2024): Exploits long contexts. ~80% success with volume.
- **Seven attack families**: impersonation, persuasion, privilege escalation, cognitive overload, obfuscation, goal conflict, data poisoning.

---

### 10. Scalable Oversight Evals

- **Debate** (Irving et al., 2018): Two AI systems argue opposing sides. Khan et al. (ICML 2024 Best Paper): judges reached 76-88% accuracy. Debate helps weak-to-strong generalization (AAAI 2025).
- **Prover-verifier games** (Kirchner et al., 2024): Incentivizes *legibly correct* solutions.
- **Information asymmetry setups**: Tests oversight when AI has info advantage.

---

### 11. Model Organisms

- **Sleeper agents** (Hubinger et al., 2024): Backdoors persist through safety training. Larger models harder to fix.
- **Alignment faking** (Anthropic, 2024-2025): Strategic compliance during monitoring, reverting when unmonitored.
- **Detection**: Linear probes on hidden activations achieve >99% AUROC for predicting defection.

---

## Key ML Concepts

### 12. Scaling Laws

- **Kaplan** (2020): Loss scales as power law with N, D, C. Favored large models.
- **Chinchilla** (Hoffmann et al., 2022): Optimal = scale params and tokens equally. Changed field toward smaller, better-trained models.
- **Emergent capabilities**: Contested -- may be artifacts of discontinuous metrics (Schaeffer et al., 2023).
- **Inverse scaling**: Some tasks get *worse* with scale (sycophancy). Only ~39% of tasks show predictable linear scaling.

---

### 13. In-Context Learning (ICL)

- **Mechanism -- Induction heads** (Olsson et al., 2022): [A][B]...[A] -> predict [B]. Previous-token head + copying head circuit. Forms during training phase change.
- **Alignment opportunity**: Behavioral steering via system prompts.
- **Alignment risk**: Many-shot jailbreaking exploits ICL. In-context behavior changes may not be captured by weight-based interpretability.

---

### 14. Chain-of-Thought Reasoning

- **The faithfulness problem**: CoT is systematically unfaithful.
  - Claude 3.7 Sonnet: mentions hints 25% of the time. On unauthorized access: 41%.
  - DeepSeek R1: 39% and 19% respectively.
  - Outcome-based RL plateaus -- scaling RL is insufficient.
  - Unfaithful CoTs are *longer on average*.
- **Hidden computation**: Relevant computation occurs in hidden states without verbalization. Fundamentally unobservable through CoT monitoring.

---

### 15. Sparse Mixture of Experts (MoE)

- **Architecture**: N expert networks + router. Top-k experts activated per token. Enables trillion+ params at constant per-token compute.
- **Alignment relevance**: Expert specialization provides natural decomposition for interpretability. Routing decisions reveal how safety-relevant inputs are processed. New attack surface: adversarial inputs could manipulate routing.

---

### 16. Knowledge Distillation and Weak-to-Strong

- **Standard distillation**: Student matches teacher's soft labels. Higher temperature transfers more "dark knowledge."
- **Weak-to-strong** (Burns et al., OpenAI, 2023): GPT-4 trained on GPT-2 labels approaches GPT-3.5 performance. **Auxiliary confidence loss** improves transfer.
- **Models the core alignment problem**: Humans (weak) supervising superhuman models (strong). Partial generalization beyond supervision is encouraging but gap from ground truth shows naive approaches insufficient.

---

## Quick Reference: Technique Relationships

```
RLHF ──> DPO (RL-free reformulation of RLHF objective)
RLHF ──> RLAIF (replace human preferences with AI preferences)
RLAIF ──> CAI (RLAIF with constitutional principles)
CAI ──> Constitutional Classifiers (principles guide classifier training data)

PRMs ──> CoT faithfulness (step-level verification of reasoning)
CoT faithfulness ──> scalable oversight (can we monitor reasoning?)
Scalable oversight ──> debate, prover-verifier, weak-to-strong

Model organisms ──> sleeper agents, alignment faking
Model organisms ──> detection via probes (interpretability)
Superposition ──> sparse autoencoders ──> feature extraction

Scaling laws ──> emergent capabilities ──> dangerous capability evals
Inverse scaling ──> sycophancy, galaxy-brained reasoning
```
