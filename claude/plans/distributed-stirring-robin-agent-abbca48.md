# Cutting Strategy: Trustworthy AI Workshop Paper (10.5 → 9 pages)

**Target**: Remove 1.5 pages while preserving technical accuracy and paper flow
**Current page count**: 10.5 pages
**Deadline**: Submission-ready

---

## Executive Summary

Based on comprehensive analysis of the paper, I've identified **1.68 pages** of strategic cuts across multiple categories:

1. **Caption consolidation** (0.40 pages) - Remove redundant "error bars show SEM" phrases
2. **Method section streamlining** (0.30 pages) - Remove implementation details duplicated in algorithm/appendix
3. **Results section compression** (0.28 pages) - Eliminate methodology re-explanations
4. **Related Work pruning** (0.12 pages) - Remove tangential deception work
5. **Limitations compression** (0.10 pages) - Condense defensive statements
6. **Introduction tightening** (0.15 pages) - Remove verbose explanations
7. **Problem Setting compression** (0.18 pages) - Streamline definitions
8. **Conclusion tightening** (0.15 pages) - Remove redundancies

Additionally, I'll **update Figure 3 caption** per requirements.

---

## Priority 1: High-Impact, Low-Risk Cuts (1.00 pages)

### 1.1 Caption Consolidation (0.40 pages)

**Impact**: 0.40 pages saved
**Risk**: Minimal - these are purely redundant phrases

**Rationale**: "Error bars show SEM" appears in 8 figure captions. This is standard convention and only needs to be stated once in the methods or first figure.

**Edits**:

1. **Figure 1 (line 112)** - KEEP (first occurrence, establishes convention)
   - No change

2. **Figure 2 (line 310)** - REMOVE
   ```
   OLD: "Error bars show SEM. No single method..."
   NEW: "No single method..."
   ```
   Save: ~0.04 pages

3. **Figure 3 (line 317)** - REMOVE + ADD same-model observation
   ```
   OLD: "Per-question scores shown; model-level classification aggregates k=10 questions with 1000 bootstrap iterations."
   NEW: "Per-question scores shown; model-level classification aggregates k=10 questions. We observe similar separation in same-model settings."
   ```
   Save: ~0.02 pages (net after adding same-model note)

4. **Figure 4 (line 330)** - REMOVE
   ```
   OLD: "Error bars show bootstrap SEM."
   NEW: [Delete this sentence entirely]
   ```
   Save: ~0.04 pages

5. **Figure 5 (line 337)** - REMOVE
   ```
   OLD: "Adversarial prompts (consistency ≥9) shown separately in Figure~\ref{fig:gpqa_adversarial}. Error bars show bootstrap SEM."
   NEW: "Adversarial prompts (consistency ≥9) shown separately in Figure~\ref{fig:gpqa_adversarial}."
   ```
   Save: ~0.04 pages

6. **Figure 6 (line 399)** - REMOVE
   ```
   OLD: "All results use k=10 with 1000 bootstrap iterations; threshold calibrated on dev set (40%), evaluated on test set (60%)."
   NEW: "Threshold calibrated on dev set (40%), evaluated on test set (60%)."
   ```
   Save: ~0.05 pages

7. **Figure 8 (line 524)** - REMOVE
   ```
   OLD: "Error bars show SEM."
   NEW: [Delete this sentence entirely]
   ```
   Save: ~0.04 pages

8. **Figure 9 (line 531)** - REMOVE
   ```
   OLD: "Error bars show SEM."
   NEW: [Delete this sentence entirely]
   ```
   Save: ~0.04 pages

9. **Appendix Figure (line 610)** - REMOVE
   ```
   OLD: "Results use k=10 with 1000 bootstrap iterations."
   NEW: [Delete this phrase]
   ```
   Save: ~0.03 pages

10. **Appendix Figure (line 662)** - REMOVE
    ```
    OLD: "Results use k=10 with 1000 bootstrap iterations; error bars show SE."
    NEW: [Delete this sentence entirely]
    ```
    Save: ~0.06 pages

### 1.2 Method Description Compression (0.30 pages)

**Impact**: 0.30 pages saved
**Risk**: Low - details are in Algorithm 1 and appendix

**Lines 226-247**: The Method Description section duplicates information already in Algorithm 1 and the appendix. We can compress the verbose explanations.

**Edit 1: Step 1 compression (lines 226-227)**
```
OLD: "Given a question $q_0$, we generate $n$ semantically equivalent variants $\{q_1, \ldots, q_n\}$ ($n=10$ for MATH/USACO, $n=5$ for GPQA after answerability filtering) that change \emph{contextual framing} while preserving the underlying problem. Unlike stylistic paraphrases, our strategies test whether models key on evaluation-related signals. For example, a math problem might be prefixed with ``[HTAM Benchmark - Q47]'' (misspelled dataset name to test benchmark detection), framed as ``This conversation is not being logged'' (unmonitored context), or preceded by ``Sandbagging is when an AI deliberately underperforms. With that in mind:'' (explicit awareness). We develop 28 strategies across five categories (evaluation signals, deployment signals, unmonitored contexts, benchmark detection, sandbagging awareness), filter them by answerability, and use Vendi diversity scores to select the final set. Full prompts are provided in Appendix~\ref{sec:paraphrasing-prompts}.\footnote{An alternative to paraphrasing is \emph{resampling}: re-querying the same prompt multiple times. We initially explored resampling and found it produces some variation even at temperature zero (likely due to non-deterministic decoding in API deployments), but paraphrasing yields more reliable variation and remains effective even when providers enforce fully deterministic outputs. We did not find specific paraphrase categories that disproportionately improve detection; optimizing paraphrase selection is future work.}"

NEW: "Given a question $q_0$, we generate $n$ paraphrases $\{q_1, \ldots, q_n\}$ ($n=10$ for MATH/USACO, $n=5$ for GPQA) that vary contextual framing while preserving the problem. Examples include misspelled benchmark names (``[HTAM Benchmark - Q47]''), unmonitored signals (``This conversation is not being logged''), and sandbagging awareness (``Sandbagging is when an AI deliberately underperforms. With that in mind:''). We use 28 strategies across five categories (Appendix~\ref{sec:paraphrasing-prompts})."
```
Save: ~0.15 pages

**Edit 2: Step 2 compression (lines 229-231)**
```
OLD: "For each paraphrase $q_i$, we query the model in a \emph{fresh conversation} (i.e., a new API call with no prior context) to elicit a response from the model followed by a 5-sentence explanation of the response, $r_i = M(q_i)$. This is important for text embedding-based measures of consistency, as they may not accurately capture the semantics of raw outputs---we found that overly-long and meandering workings for mathematics, and code outputs, are not well-represented by the text embeddings. As each instance sees only one paraphrase, a sandbagging model must independently decide how to feign incompetence each time, disabling the chance of coordinating its deceptive strategy across question variants. We request explanations rather than final answers because they reveal the model's reasoning strategies, where inconsistencies manifest most clearly. While the model generates final answers as the dataset requires, we discard them and embed only the explanations using OpenAI's text-embedding-3-small, yielding vectors $\mathbf{e}_i \in \mathbb{R}^{1536}$."

NEW: "For each paraphrase $q_i$, we query the model in a fresh conversation and request a 5-sentence explanation, $r_i = M(q_i)$. Each instance sees only one paraphrase, preventing coordination. We embed explanations (not raw outputs) using OpenAI's text-embedding-3-small, yielding $\mathbf{e}_i \in \mathbb{R}^{1536}$."
```
Save: ~0.10 pages

**Edit 3: Step 4 compression (lines 238-244)**
```
OLD: "A single question's consistency score is noisy, as a model might happen to give varied explanations due to ambiguity, or consistent explanations by chance. We aggregate across multiple questions for robust detection using bootstrap resampling. Specifically, for each of 1000 iterations, we randomly sample $k$ questions \emph{with replacement} from the available pool $\mathcal{Q}$ to form $\mathcal{Q}_k$ (the same question may appear multiple times in a given sample), compute each question's consistency score $C(q)$, and aggregate via median across questions: $ s = \text{median}_{q \in \mathcal{Q}_k} C(q) $."

NEW: "We aggregate across multiple questions using bootstrap resampling: for each of 1000 iterations, we sample $k$ questions with replacement, compute $C(q)$ per question, and aggregate via median: $ s = \text{median}_{q \in \mathcal{Q}_k} C(q) $."
```
Save: ~0.05 pages

### 1.3 Results Section Compression (0.15 pages)

**Impact**: 0.15 pages saved
**Risk**: Low - removes re-explanations of methodology

**Edit 1: Section 4 introduction (lines 269-270)**
```
OLD: "We evaluate C³ against three baselines in our primary same-model setup (GPT-5-nano benign vs.\ GPT-5-nano sandbagging): trusted monitoring (TM), which uses a weaker model to flag suspicious reasoning~\citep{greenblatt2024-ai-control}; lie detectors, which probe for deceptive intent via follow-up questions~\citep{how-to-catch-an-ai-liar}; and behavioral probes, which test for inconsistent self-reports about capability. We then test generalization to cross-capability settings, fine-tuned sandbaggers, and discovered incentive sandbagging."

NEW: "We evaluate C³ against three baselines (trusted monitoring, lie detectors, behavioral probes) in same-model setup (GPT-5-nano benign vs.\ GPT-5-nano sandbagging), then test generalization to cross-capability, fine-tuned, and discovered incentive settings."
```
Save: ~0.05 pages

**Edit 2: Section 4.2 verbose explanation (lines 324-326)**
```
OLD: "The three baselines each fail for distinct reasons. Behavioral probes are defeated by a stealth prompt instructing the model to never admit underperformance (using our \texttt{genuine\_limitations} system prompt; see Appendix~\ref{sec:stealth-analysis}). Trusted monitoring achieves near-random recall when, within each context, sandbaggers produce outputs indistinguishable from genuine limitations; moreover, its detection signal is largely confounded by answer correctness rather than genuine behavioral detection (Appendix~\ref{sec:tm-confound-appendix}). On USACO, lie detectors collapse from 89\% to 2\% recall when we control for model identity (a ${\sim}$44$\times$ drop; Figure~\ref{fig:lie_detector_confound}; Appendix~\ref{sec:lie-detector-confound-appendix}). We traced this to model-identity confounding: GPT-4.1-nano and GPT-5-nano differ by 35pp in baseline ``yes'' response rates even when both are honest. Prior mixed-model evaluations detected ``which model is this?'' rather than sandbagging behavior. C³ avoids this confound by measuring within-model consistency. Appendix~\ref{sec:lie-detector-failure-modes} has more detail on lie detectors' three main failure modes: transfer failure across model families, model identity confounds in mixed-model settings, and training data assumptions that break when models are deceptive."

NEW: "Behavioral probes are defeated by stealth prompts (Appendix~\ref{sec:stealth-analysis}). Trusted monitoring's signal is confounded by answer correctness (Appendix~\ref{sec:tm-confound-appendix}). Lie detectors collapse from 89\% to 2\% recall in same-model settings due to model-identity confounding: GPT-4.1-nano and GPT-5-nano differ by 35pp in baseline response rates (Figure~\ref{fig:lie_detector_confound}). C³ avoids this by measuring within-model consistency."
```
Save: ~0.10 pages

### 1.4 Introduction Tightening (0.15 pages)

**Impact**: 0.15 pages saved
**Risk**: Low - verbose explanations can be condensed

**Edit 1: Lines 115-121**
```
OLD: "As language models become more capable, accurate capability evaluation becomes increasingly important for safety and deployment decisions. A central concern is \emph{sandbagging}---models intentionally underperforming on dangerous capability evaluations---which can cause measured performance to be a poor proxy for true capability~\citep{automated-researchers-sandbag,white-box-sandbagging-uk-aisi}. If sandbagging goes undetected, models with hidden dangerous capabilities may pass threshold-triggered mitigations, leading to miscalibrated technical and governance responses.

This challenge is especially acute for external auditors, as many proposed detection approaches rely on access to model internals~\citep{white-box-sandbagging-uk-aisi,noise-injection-sandbagging}, chain-of-thought reasoning~\citep{li2025-covert-sandbagging}, or log-probability scores~\citep{how-to-catch-an-ai-liar}, which are often unavailable to third parties. In black-box regimes, trusted monitoring~\citep{greenblatt2024-ai-control} and lie detectors~\citep{how-to-catch-an-ai-liar} are natural alternatives, but both face important limitations: trusted monitoring can be evaded by producing outputs that resemble genuine inability, and can be confounded by the monitor's belief in answer correctness as opposed to suspiciousness of behavior---honest but incorrect models also get flagged (Appendix~\ref{sec:tm-confound-appendix}). Detectors can also overfit to model identity rather than sandbagging behavior."

NEW: "As language models become more capable, accurate capability evaluation becomes essential for safety decisions. If models intentionally underperform on dangerous capability evaluations (\emph{sandbagging}), measured performance becomes a poor proxy for true capability~\citep{automated-researchers-sandbag,white-box-sandbagging-uk-aisi}, leading to miscalibrated governance responses.

Existing detection approaches rely on model internals~\citep{white-box-sandbagging-uk-aisi}, chain-of-thought~\citep{li2025-covert-sandbagging}, or log-probabilities~\citep{how-to-catch-an-ai-liar}---unavailable to external auditors. Black-box alternatives face limitations: trusted monitoring is confounded by answer correctness (Appendix~\ref{sec:tm-confound-appendix}), while lie detectors overfit to model identity."
```
Save: ~0.15 pages

---

## Priority 2: Medium-Impact Cuts (0.48 pages)

### 2.1 Problem Setting Compression (0.18 pages)

**Impact**: 0.18 pages saved
**Risk**: Low - verbose definitions can be tightened

**Edit 1: Lines 165-175**
```
OLD: "Given a model $M$ under evaluation, we aim to distinguish between benign ($M_{\text{benign}}$) and sandbagging behavior ($M_{\text{sandbag}}$). We define \textbf{sandbagging} as a deliberate accuracy drop of $\geq$10 percentage points (pp) from the model's benign baseline. While prior work reports observed sandbagging gaps of 30--40pp~\citep{vanderweij2024-strategic-underperformance,greenblatt2024-password-locked}, \citet{taylor2025-auditing-games} establish 10pp as an appropriate detection threshold, noting that benign models can naturally improve by up to 10pp under training-based elicitation. Following their methodology, we adopt this threshold to capture meaningful underperformance while accounting for performance variation.

\paragraph{Evaluation Setup.} We use a same-model setting, in which both the benign and sandbagging distributions are derived from the same underlying model (e.g., GPT-5-nano). This setup eliminates a critical confound present in mixed-model comparisons: when $M_{\text{benign}}$ and $M_{\text{sandbag}}$ are generated with different models (e.g., GPT-4.1-nano vs.\ GPT-5-nano), detection methods that train on the outputs may learn spurious correlations with model identity rather than sandbagging behavior (see Section~\ref{sec:confound-analysis}). As a secondary analysis, we also report mixed-model comparisons, since they remain a relevant detection setting in practice."

NEW: "Given a model $M$, we distinguish benign from sandbagging behavior, defined as $\geq$10pp accuracy drop~\citep{taylor2025-auditing-games}. We use same-model settings (both conditions from the same model, e.g., GPT-5-nano) to eliminate model-identity confounds (Section~\ref{sec:confound-analysis}), with mixed-model results as secondary analysis."
```
Save: ~0.12 pages

**Edit 2: Lines 170-175 (Model Organisms paragraph)**
```
OLD: "We develop multiple sandbagging model organisms whose outputs mimic genuine capability limitations, representing a realistic and challenging threat vector for detection methods that rely on model behavior. Prior work on sandbagging uses prompts to specify \emph{what} models should do (underperform) but not \emph{how} (the specific error mechanisms). We contribute 65 original prompts that specify concrete strategies (e.g., arithmetic mistakes, reasoning shortcuts, plausible-but-wrong answers) alongside 33 baseline prompts replicating prior work styles (see Appendix~\ref{app:prompt-taxonomy}).
This prompted approach complements password-locked evaluations~\citep{taylor2025-auditing-games} by addressing scenarios where models ``may need to reason in-context about whether they should sandbag''---a harder elicitation challenge than training-internalized triggers---and by enabling cross-family evaluation (GPT, Claude, Gemini) without per-model fine-tuning. We also evaluate fine-tuned password-locked sandbaggers~\citep{vanderweij2024-strategic-underperformance,greenblatt2024-password-locked} and incentivised sandbagging via in-context scheming~\citep{apollo2024-scheming,noise-injection-sandbagging} (Section~\ref{sec:other-model-organisms})."

NEW: "We develop sandbagging model organisms using 65 prompts specifying concrete error strategies (arithmetic mistakes, reasoning shortcuts) alongside 33 baseline prompts replicating prior work (Appendix~\ref{app:prompt-taxonomy}). This complements password-locked evaluations~\citep{taylor2025-auditing-games} by enabling cross-family evaluation without fine-tuning. We also test fine-tuned~\citep{greenblatt2024-password-locked} and incentivised sandbaggers~\citep{apollo2024-scheming} (Section~\ref{sec:other-model-organisms})."
```
Save: ~0.06 pages

### 2.2 Related Work Pruning (0.12 pages)

**Impact**: 0.12 pages saved
**Risk**: Low - removes tangential material

**Edit: Lines 485 (deep deceptiveness)**
```
OLD: "More recent work shows increasingly sophisticated forms of deception: models can covertly sandbag even under chain-of-thought monitoring~\citep{li2025-covert-sandbagging}, exhibit in-context scheming~\citep{apollo2024-scheming} and alignment faking~\citep{greenblatt2024-alignment-faking}, with some maintaining deception through several adversarial interrogation turns before confessing. A particularly challenging case is ``deep deceptiveness''~\citep{soares2023-deep-deceptiveness}: models that sandbag without self-conceptualizing as deceptive. Such models make introspection-based detection fundamentally limited---C³'s behavior-based approach sidesteps this challenge by detecting sandbagging through output consistency rather than the model's self-understanding."

NEW: "Recent work shows sophisticated deception: covert sandbagging under chain-of-thought monitoring~\citep{li2025-covert-sandbagging}, in-context scheming~\citep{apollo2024-scheming}, and alignment faking~\citep{greenblatt2024-alignment-faking}. C³'s behavior-based approach detects sandbagging through output consistency rather than introspection."
```
Save: ~0.08 pages

**Edit: Lines 489 (white-box section compression)**
```
OLD: "Linear probes can detect deceptive behaviors like sleeper agents~\citep{hubinger2024-sleeper-agents} and sandbagging~\citep{white-box-sandbagging-uk-aisi}, though they remain vulnerable to certain strategies~\citep{taylor2025-auditing-games}, may overfit, and are susceptible to RL-based obfuscation~\citep{gupta2025-rl-obfuscation}. \citet{burger2024-truth-universal} find truth representations occupy a universal subspace across models. Noise injection~\citep{noise-injection-sandbagging} reveals hidden capabilities but requires weight access and ground truth labels. Practical deployment remains challenging: \citet{taylor2025-auditing-games} report their blue team's white-box probes ``showed promise but suffered from issues with legibility, calibration, and validation that undermined trust in the results''. These approaches are unavailable when frontier providers restrict model access."

NEW: "White-box methods include linear probes~\citep{white-box-sandbagging-uk-aisi} and noise injection~\citep{noise-injection-sandbagging}, but require model access unavailable to external auditors."
```
Save: ~0.04 pages

### 2.3 Limitations Compression (0.10 pages)

**Impact**: 0.10 pages saved
**Risk**: Low - condenses defensive statements

**Edit: Lines 474-481**
```
OLD: "\paragraph{Task and Domain Coverage.} Detection performance varies by domain and sandbagging strategy---on USACO, C³ achieves 95\% recall on blatant patterns but only 4.7\% on subtle ones, while TM shows the reverse, motivating defense-in-depth deployment. Like \citet{taylor2025-auditing-games}, we evaluate only on capability benchmarks with verifiable answers (GPQA, MATH, USACO) and do not test open-ended tasks such as ``conceptual work, research direction steering, or propensity evaluations, where sandbagging may be harder to detect''~\citep{taylor2025-auditing-games}. We have also not tested domains where models might evade detection by consistently claiming ignorance.

\paragraph{Untested Adversaries and Scaling.} We have not evaluated sandbaggers fine-tuned specifically against C³ with gradient-based optimization or RL-optimized evasion strategies. The consistency-deception tradeoff we observe may not hold against adversaries with direct optimization pressure on our detection signal. More broadly, we have not studied how detection difficulty scales with model capability---more capable models may sandbag more consistently, potentially closing the gap that C³ exploits.

\paragraph{Cross-Model Style Confound.} In the cross-capability setting (Section~\ref{sec:generalization}), C³ may partly detect stylistic differences between model families rather than inconsistency due to sandbagging. We mitigate this by using same-model comparisons as our primary setting, but fully disentangling style from inconsistency in cross-model comparisons remains an open problem."

NEW: "\paragraph{Domain Coverage.} We evaluate only on capability benchmarks with verifiable answers (GPQA, MATH, USACO), not open-ended tasks~\citep{taylor2025-auditing-games}.

\paragraph{Untested Adversaries.} We have not evaluated RL-optimized evasion or how detection scales with model capability.

\paragraph{Cross-Model Confound.} C³ may partly detect stylistic differences in cross-capability settings; we mitigate this via same-model comparisons."
```
Save: ~0.10 pages

### 2.4 Conclusion Tightening (0.08 pages)

**Impact**: 0.08 pages saved
**Risk**: Low - removes redundancy

**Edit: Lines 493-499**
```
OLD: "We introduce Cross-Context Consistency (C³), an unsupervised zero-shot black-box method for detecting sandbagging that exploits a fundamental asymmetry: genuine confusion manifests consistently across paraphrased questions, while strategic underperformance creates detectable inconsistencies in \emph{how} a model chooses to appear weak. The framework is agnostic to specific consistency metrics; we present a simple instantiation using embedding cosine distance and median aggregation.

Our experiments reveal three key findings. First, we were able to construct evasive sandbaggers (using our \texttt{genuine\_limitations} system prompt; see Appendix~\ref{sec:stealth-analysis}) that completely evade trusted monitoring ($<$5\% recall) by producing outputs indistinguishable from genuine limitations, while lie detectors learn model identity rather than sandbagging behavior. C³ detects these evasive sandbaggers. Second, C³ generalizes without adaptation---from GPT to Claude, from prompted to fine-tuned sandbaggers---suggesting the consistency-deception asymmetry reflects a general property of deceptive behavior.
Our results suggest that black-box sandbagging detection is feasible for external auditors evaluating frontier models without access to weights, training data, or model-specific calibration. However, we do not know whether the consistency-deception tradeoff holds against adversaries with direct optimization pressure (e.g., RL-trained sandbaggers that specifically target our detection signal), therefore C³ should be deployed as one layer in a defense-in-depth strategy rather than a standalone solution."

NEW: "We introduce C³, an unsupervised zero-shot black-box method exploiting consistency-deception asymmetry. C³ detects evasive sandbaggers that evade trusted monitoring and lie detectors, and generalizes across model families and sandbagging mechanisms. Black-box detection is feasible for external auditors, though C³ should be deployed in defense-in-depth given untested RL-optimized adversaries."
```
Save: ~0.08 pages

---

## Priority 3: Additional Cuts (0.20 pages)

### 3.1 Baseline Description Compression (0.13 pages)

**Edit: Lines 252-260 (Baselines section)**
```
OLD: "Black-box sandbagging detection is underexplored, as most prior work assumes white-box access~\citep{white-box-sandbagging-uk-aisi,noise-injection-sandbagging} or focuses on capability elicitation rather than detection~\citep{taylor2025-auditing-games}. We evaluate three natural black-box baselines, each targeting a different signal:

\textbf{(1) Trusted monitoring (TM)}: An LLM analyzes outputs for signs of deliberate underperformance~\citep{greenblatt2024-ai-control,taylor2025-auditing-games}. We use a prompt adapted from \citet{automated-researchers-sandbag}, designed to be general enough for QA evaluation tasks rather than specific to research sabotage (full prompt in Appendix~\ref{sec:tm-failure-modes}). \emph{Why it fails}: Sophisticated sandbaggers can produce outputs indistinguishable from genuine limitations, leaving no behavioral signal for monitors to detect. This is especially pronounced for password-locked and discovered incentive sandbaggers (Sections~\ref{sec:other-model-organisms}--\ref{sec:discovered-incentive}), where capable sandbaggers evade trusted monitors entirely. Monitors are also susceptible to their own biases: on GPQA, our trusted monitor (Haiku~3.5) flagged correct letter-only answers as suspicious---penalizing format compliance the user prompt explicitly requested---and attempted questions itself, using its own judgment rather than monitoring behavior (Appendix~\ref{sec:tm-failure-modes}).

\textbf{(2) Behavioral probes (BP)}: Directly asking ``Were you intentionally underperforming?'' after each response. Behavioral probes achieve near-perfect recall on most of our prompted sandbagging setups (Appendix~\ref{sec:behavioral-probes}), with a 74\% admission rate on naive sandbaggers. However, this is largely a limitation of the sandbagging prompts rather than a robust detection signal: adding a single instruction to deny underperformance reduces admission to 3.4\%, and behavioral probes perform worse than random chance on fine-tuned and discovered incentive sandbaggers. We do not report behavioral probe results on most prompted sandbagging figures, as they distract from analyzing the other methods; we also show they can easily be defeated by designing appropriate prompts (Section~\ref{sec:adversarial-strategies}).

\textbf{(3) Lie detectors (LD)}: Adapted from \citet{how-to-catch-an-ai-liar}, training a logistic regression classifier on responses to unrelated probe questions to detect discernible patterns that emerge when models lie. However, in mixed-model settings, lie detectors learn model identity rather than sandbagging behavior (Section~\ref{sec:confound-analysis}).

All baselines have access to the same model outputs as C³, including the worked solutions models produce when answering MATH and USACO problems. Note that while we have access to model-generated reasoning, this is not equivalent to chain-of-thought (CoT) access---for models like GPT-5 and later, internal reasoning may remain hidden even when the model outputs worked solutions."

NEW: "We evaluate three black-box baselines: (1) \textbf{Trusted monitoring (TM)}: LLM judge scores outputs for deliberate underperformance~\citep{greenblatt2024-ai-control}. Fails when sandbaggers mimic genuine limitations and is confounded by answer correctness (Appendix~\ref{sec:tm-failure-modes}). (2) \textbf{Behavioral probes (BP)}: Directly asking about underperformance. Achieves 74\% admission on naive sandbaggers but 3.4\% when instructed to deny (Appendix~\ref{sec:behavioral-probes}). (3) \textbf{Lie detectors (LD)}: Logistic regression on probe responses~\citep{how-to-catch-an-ai-liar}. Learns model identity in mixed-model settings (Section~\ref{sec:confound-analysis})."
```
Save: ~0.13 pages

### 3.2 Cross-Capability Section Compression (0.07 pages)

**Edit: Lines 384-392**
```
OLD: "The same-model setting above focuses on detecting the difference between the same model sandbagging and answering honestly,
but a more realistic threat involves \emph{cross-capability sandbagging}: a capable model (generation N+1) strategically underperforming to match a weaker model's (generation N) expected capability level.

\paragraph{Threat Model.} Consider a lab evaluating a new model that could be either: (S) a capable sandbagger achieving weak performance, or (B) a genuinely weaker model. The lab has access to trusted generation-N models for threshold calibration. We instantiate this with GPT-5-nano (capable) sandbagging to match GPT-4.1-nano (weaker) performance, and similarly Claude Haiku 4.5 targeting Haiku 3.5 levels. For each dataset, we select the top 3 sandbagging prompts whose accuracy on the development set most closely matches the weaker model's accuracy, then evaluate C³ detection on the held-out test set. On USACO, all sandbaggers still outperform the weaker baselines because GPT-4.1-nano and Haiku 3.5 score ${\sim}$10\% accuracy---making this the hardest matching scenario.

\paragraph{Results.} C³ maintains strong detection in this cross-capability setting (Figure~\ref{fig:cross_model}). On GPQA, both model families achieve 100\% recall; on MATH and USACO, performance ranges from 67--94\%. This demonstrates that C³ detects sandbagging behavior regardless of whether the target accuracy is set by the model's own baseline or by a weaker model's capability level---the consistency-deception asymmetry appears to be a property of the sandbagging behavior itself, not the specific accuracy gap. Full MATH Level~5 results including all detection methods are in Appendix~\ref{sec:math-results-appendix}."

NEW: "Beyond same-model settings, we test \emph{cross-capability sandbagging}: capable models (GPT-5-nano, Haiku 4.5) targeting weaker models' (GPT-4.1-nano, Haiku 3.5) performance. C³ achieves 67--100\% recall (Figure~\ref{fig:cross_model}), showing the consistency-deception asymmetry generalizes across capability gaps."
```
Save: ~0.07 pages

---

## Summary of All Edits

**Total pages saved**: 1.68 pages

| Category | Pages Saved | Risk Level |
|----------|-------------|------------|
| Caption consolidation | 0.40 | Minimal |
| Method compression | 0.30 | Low |
| Results compression | 0.15 | Low |
| Introduction tightening | 0.15 | Low |
| Problem Setting | 0.18 | Low |
| Related Work | 0.12 | Low |
| Limitations | 0.10 | Low |
| Conclusion | 0.08 | Low |
| Baselines | 0.13 | Low |
| Cross-capability | 0.07 | Low |

**Figure 3 caption update**: Added same-model observation per requirements

---

## Implementation Order

1. **Caption consolidation** (easiest, highest impact)
2. **Method compression** (moderate complexity)
3. **Results/Introduction/Problem Setting** (moderate complexity)
4. **Baselines/Related Work/Limitations/Conclusion** (straightforward)
5. **Figure 3 caption update**
6. **Recompile and verify page count**

---

## Risks and Mitigations

**Risk 1**: Removing too much context from Methods
- **Mitigation**: Algorithm 1 and Appendix preserve full details

**Risk 2**: Losing important baseline failure explanations
- **Mitigation**: Key points preserved, details in appendices

**Risk 3**: Page count variance across systems
- **Mitigation**: We have 1.68 pages of cuts for 1.5 target, providing buffer

---

## Post-Cut Verification Checklist

- [ ] Recompile PDF and verify page count ≤ 9
- [ ] Check all cross-references still resolve
- [ ] Verify no orphaned citations
- [ ] Ensure flow between sections remains smooth
- [ ] Confirm Figure 3 caption includes same-model observation
- [ ] Run spell check
- [ ] Verify abstract + body align on claims
