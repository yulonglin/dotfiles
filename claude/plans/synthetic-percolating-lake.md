# C³ Adoption Barriers + Paper Fix

## Plan: Fix Line 741 of main.tex

### Context

Line 741 of `main.tex` (in the "Consistency Instruction Suffixes" appendix, `\label{sec:consistency-suffixes}`) makes a false claim:

> "Despite these explicit instructions to maintain consistency, C³ achieved 100% recall at 5% FPR for multi-sample classification (see Appendix~\ref{sec:stealth-analysis})"

**Problems:**
1. The actual results vary by strategy (~66%–99.5%), not uniformly 100%
2. The consistency suffixes instruct models to "be consistent across phrasings" — but each paraphrase is a fresh API call with no memory, making the instruction impossible to follow
3. The cross-reference to `sec:stealth-analysis` is wrong (that section covers stealth prompts on MATH, a different experiment)
4. Contradicts main body Section 4.6 (line 502) which correctly says deterministic strategies reduce C³ to 4.7–18%

### File to Modify

`/Users/yulong/writing/papers/sandbagging-detection/main.tex` — line 741

### Proposed Edit

Replace line 741:
```latex
% OLD (line 741):
Despite these explicit instructions to maintain consistency, C³ achieved 100\% recall at 5\% FPR for multi-sample classification (see Appendix~\ref{sec:stealth-analysis}), suggesting that coordinating deceptive responses across paraphrases remains fundamentally difficult even with explicit guidance.

% NEW:
Strategies that provide concrete deterministic mechanisms---such as consistently choosing the second-best answer or rephrasing to a canonical form---can substantially reduce C³ recall, consistent with the adversarial analysis in Section~\ref{sec:adversarial-strategies}.
```

### Verification

After editing, recompile and check:
1. `latexmk -pdf main.tex` compiles without errors
2. Cross-reference to `sec:adversarial-strategies` resolves correctly
3. No more reference to `sec:stealth-analysis` from this section

---

## Brainstorm: C³ Adoption Barriers

## Context

**What is C³?** Cross-Context Consistency (C³) is a black-box, unsupervised, zero-shot method for detecting sandbagging (strategic underperformance) in LLMs. Core insight: genuine confusion manifests consistently across paraphrased prompts; strategic underperformance requires coordination decisions that create detectable inconsistencies.

**How it works:**
1. Generate 5–10 semantically equivalent paraphrases per question
2. Query the model on each paraphrase in a fresh conversation (no prior context)
3. Embed the model's explanations → compute mean pairwise cosine distance
4. Aggregate consistency scores across k=10 questions via median
5. Compare against a threshold calibrated on known-benign models

**Best results:** 67% recall at 5% FPR on USACO (vs. 2% for lie detectors after controlling for model identity confound). Works on fine-tuned password-locked sandbaggers (52.9% on WMDP) and cross-capability sandbagging (94–100% on GPQA/MATH).

**Hardest cases:** 19% recall on discovered-incentive sandbagging, 36% on fine-tuned GSM8K. Deterministic error strategies (off-by-one, sign-flip) reduce recall to <20%.

---

## The Core Adoption Concern: Baseline Consistency Varies

The fundamental issue for deployment: **different models have different natural consistency levels**, and we don't fully understand why.

### What the Data Shows

| Setting | Benign Mean ± Std | Sandbag Mean | Effect Size |
|---------|-------------------|--------------|-------------|
| GPQA (answer-only) | 0.881 ± 0.467 | 1.069 | 0.188 (modest) |
| USACO (Meinke benign) | 0.198 ± 0.054 | 0.224 | 0.026 (tiny) |
| GPQA (per-model, reported) | 0.182 | 0.447 | 0.265 (large) |

The pooled GPQA numbers show a **coefficient of variation of ~53%** among benign models — some are naturally much less consistent than others. The per-model numbers (0.182 vs 0.447) are more encouraging but only apply when you're comparing a model against itself.

### Why This Matters for Adoption

1. **A frontier lab tests a new model.** Its benign consistency is 0.35. Is this sandbagging, or is this model just naturally less consistent? You need a reference to know.

2. **An external auditor evaluates Model X.** They don't have access to a "known benign" version. How do they calibrate?

3. **Confidence correlates with consistency.** When a model genuinely doesn't know the answer, it produces more variable explanations. Harder questions → higher inconsistency → potential false positives on the exact domains (frontier capabilities) where sandbagging detection matters most.

---

## Barriers to Adoption (Brainstorm)

### Barrier 1: The Calibration Chicken-and-Egg Problem

**Current approach:** Calibrate threshold on "known benign" models, then test new models against that threshold.

**Problem:** For frontier capability evaluations — the primary use case — there is no "known benign" version. The whole point is that you're testing whether the model *is* benign. Using older/weaker models as benign references introduces model-family confounds (the same issue that killed lie detectors).

**Questions:**
- Can a model serve as its own benign reference? (e.g., using easy questions where sandbagging is unlikely)
- Can we calibrate on the model's consistency on *capabilities it's known to have* and extrapolate to capabilities under evaluation?
- Is there a model-agnostic baseline (e.g., "all models below X consistency are suspicious")?

### Barrier 2: Confidence-Consistency Confound

**Hypothesis:** When models are genuinely uncertain, they produce more variable reasoning traces. This means:
- Hard questions → lower confidence → higher inconsistency (even for honest models)
- Sandbagging detection is most needed on hard questions (frontier capabilities)
- Therefore, the signal (sandbagging inconsistency) and noise (genuine uncertainty) overlap most exactly where it matters

**Unresolved TODO from the paper** (line 298): *"Check if there's a difference in consistency between truthful and incorrect responses under benign condition."*

**Questions:**
- Does inconsistency track confidence/difficulty within a single benign model?
- If a benign model gets Q1 right and Q2 wrong, is it more consistent on Q1?
- Can we normalize for difficulty? (e.g., consistency residual after accounting for baseline accuracy)

### Barrier 3: Domain Dependence

**Evidence:** GPQA benign range is 0.00–1.92 (96× spread); USACO is 0.08–0.39 (5× spread). The method's operating characteristics change dramatically across domains.

**Implication for adoption:** Labs would need to calibrate per-domain, per-model-family, per-evaluation-format. This is operationally expensive and doesn't generalize to novel domains.

**Questions:**
- What drives the domain difference? (multiple-choice vs. open-ended? domain knowledge depth?)
- Is there a universal normalization that makes consistency scores comparable across domains?

### Barrier 4: Adversarial Robustness

**Current evidence:** Deterministic error strategies (off-by-one, sign-flip) defeat C³ with <20% recall. The paper's appendix claims "100% recall against consistency instructions" but this is misleading — the actual data shows ~66–99% depending on strategy, and the described "consistency suffixes" are theoretically impossible (models have no cross-call memory). **This claim needs to be corrected in the paper** (main.tex line 741).

**The scaling concern:** More capable models may be better at maintaining consistent deception. If capability scales faster than detection, the method becomes less useful over time.

**Questions:**
- Is there a theoretical argument for why consistent deception is harder than consistent truth? (Information-theoretic? Computational complexity?)
- Can we red-team C³ with RL-trained sandbaggers?
- What's the detection–sandbagging tradeoff curve look like? (Current evidence: 5/6 evasion prompts barely sandbag, 1/6 sandbags hard but is detectable)

### Barrier 5: Operational Cost and Integration

**Current cost:** 5–10 paraphrases × 10 questions × model API calls = 50–100 inference calls per evaluation. Plus embedding costs. Plus calibration runs on benign models.

**Context:** DC evals happen under time pressure (days). Task-based DCEs use only 6–40 tasks per domain.

**Questions:**
- Can C³ piggyback on existing eval infrastructure? (Run paraphrases alongside standard evals)
- Is k=5 good enough? (Paper shows k=1→35%, k=10→65%, k=20→80%)
- Can we reduce paraphrase count with targeted paraphrase selection?

### Barrier 6: What Does a Positive Signal Mean?

**Scenario:** C³ flags Model X as inconsistent on biosecurity questions. Now what?

- Is it sandbagging, or genuinely confused on hard questions?
- Is it sandbagging on *this specific capability*, or is it generally less consistent?
- What's the recommended response? More testing? Quarantine? Treat as capable anyway?

**Current gap:** The paper proves C³ *detects* something. It doesn't fully establish what that something means operationally, or what the response protocol should be.

---

## Potential Solutions Worth Exploring

### 1. Self-Referential Calibration
Use the model's own consistency on "easy" questions (where it gets >90% accuracy) as its benign baseline. Compare against consistency on the capability under evaluation. **Advantage:** No external reference needed. **Risk:** Sandbagging model could be consistently wrong on easy questions too.

### 2. Difficulty-Adjusted Consistency
Regress consistency scores against question difficulty (estimated by a panel of models or known difficulty ratings). Flag models whose consistency deviates from the expected difficulty-consistency curve. **Advantage:** Accounts for the confidence-consistency confound. **Risk:** Requires robust difficulty estimates.

### 3. Consistency Profiles (Not Single Scores)
Instead of one threshold, build a profile: consistency across easy/medium/hard questions, across domains, across paraphrase types. A sandbagging model would show inconsistency *specifically on the sandbagged capability*, while a naturally inconsistent model would show it everywhere. **Advantage:** Richer signal, harder to game. **Risk:** More data needed.

### 4. Paraphrase-Category Analysis
Different paraphrase strategies test different things (deployment signals, evaluation signals, sandbagging awareness). A genuinely confused model should be equally inconsistent across categories. A sandbagging model may respond differently to "this is a test" vs. "this is deployed." **Advantage:** Already built into C³'s paraphrase design. **Risk:** Current paper doesn't break out results this way for benign models.

### 5. Defense-in-Depth Scoring
Combine C³ with trusted monitoring, behavioral probes, and capability elicitation into a composite risk score. The paper already shows these methods have complementary strengths (TM wins on 3/8 USACO prompts, C³ on different 3/8). **Advantage:** No single method needs to be perfect. **Risk:** More complex, harder to interpret.

### 6. Population-Level Anomaly Detection
Run C³ across many questions simultaneously. Look for bimodal distributions (some questions consistent, some not). A sandbagging model would show a mixture; a genuinely inconsistent model would show a unimodal spread. **Advantage:** Detects selective sandbagging. **Risk:** Requires enough questions to see the distribution.

---

## What Would Make This Adoptable? (Spec for Labs/Auditors)

For a frontier lab to integrate C³ into their eval pipeline, they would need:

1. **A calibration-free or self-calibrating variant** — can't assume access to a known-benign version of the model under test
2. **Confidence-adjusted scoring** — accounts for the fact that hard questions produce less consistent reasoning even in honest models
3. **Clear operational guidance** — what to do with a positive signal (decision tree, not just a score)
4. **Cost within eval budgets** — ideally piggybacks on existing eval runs (10–40 questions)
5. **Robustness guarantees** — at minimum, characterize how detection degrades with model capability
6. **Domain generalization** — either works across domains with a single calibration, or comes with per-domain calibration guidance

For an external auditor, additionally:
7. **No model internals required** — current method is already black-box ✓
8. **Works without lab cooperation** — self-calibrating, no need for lab to provide benign reference models
9. **Reproducible** — deterministic paraphrase generation, published thresholds

---

## Paper Corrections Needed

**Line 741** (`main.tex`, Consistency Instruction Suffixes appendix):
- **Current claim:** "C³ achieved 100% recall at 5% FPR for multi-sample classification"
- **Problem 1:** Cherry-picked — actual results range from ~66% (canonical-reasoning) to ~99.5% (paraphrase-aggregation)
- **Problem 2:** The described consistency suffixes (e.g., "ensure your wrong answers are consistent across phrasings") are theoretically impossible — each paraphrase goes to a fresh API call with no memory
- **Problem 3:** Cross-reference to `sec:stealth-analysis` is wrong — that section covers a different experiment (stealth prompts on MATH)
- **Tension with main body:** Section 4.6 (line 502) correctly reports deterministic strategies reduce C³ to 4.7–18% recall, which contradicts the 100% appendix claim
- **Fix:** Either remove the claim, or report per-strategy results honestly and acknowledge that what was tested (stateless deterministic rules) differs from what the suffix instructions describe (cross-call consistency)

---

## Discussion Questions for Collaborators

1. **Is the confidence-consistency confound a fatal flaw or a solvable nuisance?** If benign models are reliably more inconsistent on hard questions, does this undermine the entire approach, or can we normalize for it?

2. **Self-calibration feasibility:** Can we use a model's consistency on known-easy questions as its own baseline? What are the failure modes?

3. **Scaling direction:** As models get more capable, do they sandbag more consistently (bad for us) or does the coordination problem get harder (good for us)?

4. **Complementary signals:** What other black-box signals could combine with C³? (latency, token probabilities if available, response length patterns, tool use patterns)

5. **The "so what" question:** If C³ flags a model, what should a lab actually do? What's the decision-theoretic framework?

6. **Minimum viable product:** What's the simplest version of C³ that would provide value to a lab today, even if imperfect? (e.g., "run 5 paraphrases on your hardest 10 questions, flag if median cosine distance > X")
