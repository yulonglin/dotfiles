# Mechanistic Interpretability: Technical Reference

**Purpose:** Interview prep for Anthropic Alignment Science roles. Assumes ML fluency; focuses on alignment-specific techniques, terminology, and results.

---

## 1. Sparse Autoencoders (SAEs)

**What it is:** A dictionary learning method that decomposes a model's dense, superposed activations into a sparse set of interpretable features. The core tool for extracting monosemantic features from polysemantic neurons.

**Architecture and Training:**

```
Encoder:  f = ReLU(W_enc @ (x - b_dec) + b_enc)     # x in R^d_model, f in R^d_sae (d_sae >> d_model)
Decoder:  x_hat = W_dec @ f + b_dec                   # reconstruct activation
```

- **Overcomplete basis:** d_sae is typically 4x-256x d_model (expansion factor). Larger = more features resolved but more compute.
- **Loss:** `L = ||x - x_hat||_2^2 + lambda * ||f||_1`
  - L2 reconstruction loss: faithfully represent the original activation.
  - L1 sparsity penalty (on encoder activations f): force most features to be zero per input. Lambda controls the sparsity-reconstruction tradeoff.
- **Decoder weight normalization:** columns of W_dec are constrained to unit norm (prevents the SAE from "cheating" by shrinking decoder weights and inflating encoder activations to reduce the L1 penalty without actually being sparse).
- **Training data:** activations collected from a specific site (e.g., residual stream at layer 12, MLP output at layer 20) across a large corpus. Each activation vector is one training example.
- **TopK SAEs** (variant): replace ReLU+L1 with a hard top-k activation function. Select the k largest encoder outputs; zero the rest. Eliminates the lambda hyperparameter and the sparsity-reconstruction tradeoff -- you directly set k (typically 32-512). Tends to produce cleaner features with less tuning. Used in recent Anthropic work.

**Key Results:**
- Anthropic's "Scaling Monosemanticity" (2024): trained SAEs on Claude 3 Sonnet's residual stream; found millions of interpretable features (Golden Gate Bridge, code errors, deception, safety-relevant concepts). Showed features are causally active -- clamping the Golden Gate Bridge feature makes the model talk about the bridge.
- "Towards Monosemanticity" (2023): first large-scale SAE on a 1-layer transformer; demonstrated features correspond to interpretable concepts.
- Gated SAEs (DeepMind, 2024): separate gating and magnitude pathways, reducing reconstruction error at same sparsity.

**Failure Modes and Known Issues:**
- **Dead features:** Features whose encoder activations are never above zero across the training corpus. They consume capacity but learn nothing. Mitigations: resampling dead features during training (reinitialize from high-loss examples), or using auxiliary loss that pushes near-dead features toward activation.
- **Feature splitting:** A single concept (e.g., "the" token) gets split across many SAE features at different granularities. At small d_sae, you get "English text"; at large d_sae, you get "the in legal documents," "the before proper nouns," etc. Not always a failure -- can reflect genuine structure -- but complicates analysis.
- **Feature absorption:** When a feature that should represent concept A instead gets absorbed into a more general feature B. Example: an "is_Paris" feature might absorb a "begins_with_P" feature if they co-occur heavily.
- **Reconstruction fidelity:** SAEs never perfectly reconstruct; the residual (x - x_hat) can carry meaningful signal. Evaluating downstream task performance with SAE-reconstructed activations (substitution loss / CE loss degradation) is critical.
- **Evaluation is hard:** No ground truth for "correct" features. Automated interpretability (using an LLM to label features) is noisy. Metrics include: L0 (average number of active features), reconstruction MSE, downstream CE loss increase, human interpretability scores.

**Jargon:** expansion factor, L0 (sparsity level), feature dashboard, activation histogram, max-activating examples, feature density, substitution loss, encoder bias, decoder bias, resampling, auxiliary loss, shrinkage (JumpReLU variant with an offset for thresholding).

---

## 2. Transcoders

**What it is:** Like SAEs but applied to model *computation* rather than *representations*. A transcoder maps MLP *inputs* to MLP *outputs* through a sparse bottleneck, learning to approximate what the MLP does in interpretable terms.

**How it differs from SAEs:**

| | SAE | Transcoder |
|---|---|---|
| Input | Activation x at site s | MLP input (residual stream pre-MLP) |
| Output | Reconstructed x_hat | Predicted MLP output |
| What it learns | Sparse decomposition of a representation | Sparse decomposition of a computation |

```
Encoder:  f = ReLU(W_enc @ x_in + b_enc)       # sparse features from MLP input
Decoder:  y_hat = W_dec @ f + b_dec              # predict MLP output
Loss:     ||MLP(x_in) - y_hat||_2^2 + lambda * ||f||_1
```

**Why this matters:** SAE features tell you "what information is here." Transcoder features tell you "what computation is being performed" -- each feature corresponds to a specific input-to-output mapping the MLP implements. This is more directly useful for circuit-level understanding.

**Key Results:**
- Anthropic's "Circuit Tracing" (March 2025): used **cross-layer transcoders (CLTs)** — a variant that maps activations across layers, not just within a single MLP — to decompose Claude 3.5 Haiku into interpretable computational features. CLT features were composed into attribution graphs that trace full inference paths through the entire model.

**Limitations:** Same dead feature / splitting issues as SAEs. Only apply to MLPs -- attention heads need separate treatment. Approximation quality can vary by layer.

---

## 3. Activation Patching / Causal Tracing

**What it is:** A family of techniques for determining which model components are causally responsible for a particular behavior, by surgically replacing activations and observing how the output changes.

**Core method:**
1. Run the model on a **clean** input (produces correct behavior). Cache all intermediate activations.
2. Run the model on a **corrupted/counterfactual** input (produces different behavior). Cache all intermediate activations.
3. For each component of interest: run the corrupted input BUT patch in the clean activation at that one component. Measure how much the output recovers toward the clean behavior.
4. Components where patching recovers performance are causally important.

**Metric:** Typically logit difference (logit_correct - logit_incorrect) or KL divergence from the clean distribution.

**Variants:**
- **Activation patching (basic):** Patch one component at a time. Coarse -- tells you "layer 9, head 7 matters" but not the mechanism.
- **Path patching:** Patch the activation flowing along a *specific edge* in the computation graph (e.g., the output of head 9.7 specifically as it is read by head 11.3). Reveals which connections matter. O(components^2).
- **Resample ablation (noising):** Replace an activation with a sample from its empirical distribution. Tests whether the specific value matters, not just whether the component is used.
- **Causal scrubbing (Redwood Research):** Tests an entire interpretability hypothesis at once. Recursively resample all activations your hypothesis says are irrelevant. If performance is preserved, the hypothesis explains the computation. Controversial -- too strict for approximate hypotheses.
- **Zero ablation:** Replace with zeros. Simple but introduces out-of-distribution activations (problematic post-LayerNorm).
- **Mean ablation:** Replace with dataset mean activation. Less OOD than zero but still imperfect.

**Key Results:**
- ROME (Meng et al., 2022): causal tracing identified specific MLP layers that store factual associations.
- IOI circuit discovery (Wang et al., 2023): path patching identified the full circuit for indirect object identification in GPT-2 Small.

**Limitations:** Counterfactual choice matters enormously. Distributed representations break single-component patching. Zero/mean ablation artifacts can mislead.

**Jargon:** clean run, corrupted run, patching effect, logit difference, noising vs denoising, counterfactual pair, indirect effect, direct effect, site, restoration metric.

---

## 4. Linear Probes

**What it is:** A supervised linear classifier trained on frozen model activations to detect whether specific information is linearly represented at a given layer/position.

**How it works:**
1. Collect activations from layer l, position p across many examples with known labels.
2. Train: `y_hat = softmax(W_probe @ h_l + b)` with cross-entropy loss. Only W_probe and b are trained; model weights frozen.
3. High probe accuracy = the information is linearly accessible at that layer.

**What probes reveal:** *What* information is present and *where* (which layer, which position).

**What probes DO NOT reveal:** **Whether the model actually uses that information.** A probe can detect information that is present but never read by downstream computation. This is the key limitation.

**Complementary technique:** Combine probes with causal interventions. If a probe finds "X is represented at layer 5" AND patching layer 5 affects X-dependent behavior, then the model both represents and uses X.

**Jargon:** probe accuracy, selectivity, amnesic probing (remove the probed direction and test if behavior changes), structural probe.

---

## 5. Circuits Analysis

**What it is:** Reverse-engineering the specific subnetwork (circuit) of attention heads and MLP layers that implements a particular model behavior. The goal: find a minimal, human-understandable computational graph for a specific task.

**Methodology:**
1. Identify behavior with clean input-output pairs.
2. Use activation patching to narrow down which components matter.
3. Use path patching to identify which connections carry relevant signal.
4. Characterize each component's role: What does it attend to? What does it write? How do its QK and OV circuits work?
5. Verify minimality: ablate everything outside the circuit; does performance hold?

**Landmark circuits:**

- **Induction heads** (Olsson et al., 2022 -- Anthropic): Two-head circuit for in-context learning of repeated sequences. Head 1 (previous-token head) attends to the token before the current query token's previous occurrence. Head 2 (induction head) uses Head 1's output to attend to the token that followed the previous occurrence and copies it. Pattern: [A][B]...[A] then predict [B]. Found in every transformer studied.

- **IOI circuit** (Wang et al., 2023 -- multi-institution including Redwood Research): 28 attention heads in GPT-2 Small for indirect object identification. Organized into: duplicate token heads, S-inhibition heads (suppress repeated name), name mover heads (move remaining name to output), and backup name mover heads.

- **Successor heads** (Gould et al., 2024 -- multi-institution: Cambridge, Anthropic, DeepMind): Heads that predict "next in sequence" (Monday->Tuesday). The OV circuit maps current item to its successor via a linear transformation.

- **Attention head superposition**: Individual heads can implement multiple circuits simultaneously using different subspaces of their QKV matrices. Makes circuit analysis harder -- a head is not always one thing.

**Limitations:** Does not scale well (manual analysis takes weeks-months per behavior). Circuits may not compose cleanly. Task-specific.

**Jargon:** QK circuit (what a head attends to), OV circuit (what a head writes), composition (Q-composition, K-composition, V-composition), direct logit attribution, virtual weight matrices (W_OV = W_O @ W_V, W_QK = W_Q^T @ W_K).

---

## 6. Representation Engineering

**What it is:** Finding directions in activation space that correspond to high-level concepts (honesty, refusal, emotion) and using them to read or steer model behavior.

**Reading vectors:**
1. Create **contrast pairs**: inputs differing primarily in the target concept.
2. Compute `v_concept = mean(h_positive) - mean(h_negative)` at a chosen layer.
3. Project new activations onto v_concept to measure concept presence.

**Steering vectors:**
1. At inference time, add `alpha * v_concept` to the residual stream at a chosen layer.
2. alpha > 0 increases the concept; alpha < 0 decreases it. Middle layers often work best. Too large alpha causes incoherence.

**Variant -- Contrastive Activation Addition (CAA):** Compute the mean difference vector across many contrast pairs to get the concept direction. PCA on difference vectors can be used for analysis/validation but the primary construction method is mean-difference averaging. More robust than single-pair difference.

**Key Results:** Steering Claude toward/away from refusal, sycophancy, power-seeking (Anthropic, 2024). Zou et al. (2023) found "honesty," "morality," "emotion" directions in Llama-2 that transfer across prompts.

**Limitations:** Concept directions may be entangled. Layer choice matters. Contrast pair quality is critical. Linear assumption may not hold.

**Jargon:** activation addition, representation reading, contrast pair, concept direction, steering coefficient (alpha), refusal direction, CAA.

---

## 7. Influence Functions

**What it is:** A method from robust statistics for **training data attribution** -- estimating which training examples most influenced a particular model prediction.

**Classical formulation:**
```
Influence(z_i, z_test) = -grad_theta L(z_test)^T * H_theta^{-1} * grad_theta L(z_i)
```
Requires inverting the Hessian (d x d where d = parameters) -- intractable for LLMs.

**EK-FAC approximation:** The Hessian is approximated using Kronecker factorization: H ~ A tensor B (per-layer input and output covariance matrices). EK-FAC adds eigenvalue correction for better quality. Reduces cost from O(d^2) to tractable per-layer computations.

**Key Results:** Grosse et al. (2023, Anthropic): scaled influence functions to billion-parameter LLMs. Found influential examples are semantically similar; influence patterns reveal generalization structure.

**Limitations:** Approximation is noisy for very large models. Still requires passes over the full training set. First-order approximation breaks for large perturbations. Needs stored checkpoints.

**Jargon:** Hessian, Fisher information matrix, KFAC, EK-FAC, training data attribution, self-influence, counterfactual influence, gradient similarity, representer points.

---

## 8. Logit Lens / Tuned Lens

**What it is:** Interpreting intermediate layer representations by projecting them into vocabulary space, revealing how the model's "prediction" evolves layer by layer.

**Logit lens (nostalgebraist, 2020):** Apply the model's final LayerNorm and unembedding W_U directly to layer l activations: `logits_l = W_U @ LayerNorm(h_l)`. No training required.

**Tuned lens (Belrose et al., 2023):** Train a learned affine per layer: `logits_l = W_U @ (A_l @ h_l + b_l)`, minimizing KL divergence to the final output distribution. Outperforms logit lens by accounting for representational frame shifts across layers.

**Useful for:** Identifying where knowledge gets written to the residual stream. Debugging when correct answers appear early but get overwritten.

**Limitations:** Logit lens assumes representational convergence (worse in early layers). Position-specific only. Vocabulary bottleneck -- concepts that don't map to single tokens are hard to see.

**Jargon:** logit lens, tuned lens, vocabulary projection, prediction trajectory, convergence layer.

---

## 9. Activation Oracles

**What it is:** Anthropic's technique (December 2025) where an LLM is trained to answer natural-language questions about raw neural activations. The model learns to interpret internal representations directly, without requiring pre-computed SAE features.

**How it works:**
1. Collect (activation, text) pairs from the model during normal inference.
2. Train the oracle LLM on raw activation vectors (not text-formatted feature magnitudes) to predict properties of the original input.
3. Query the trained oracle: "What is this text about?", "What entity does position 5 refer to?"

**Key distinction:** This is a separate paper from "Circuit Tracing" (March 2025). Circuit Tracing uses attribution graphs over SAE/transcoder features. Activation Oracles take a complementary approach — training on raw activations without requiring a dictionary decomposition step.

**Note:** "Clio" is a separate Anthropic project focused on privacy-preserving usage analytics (understanding how models are used in aggregate), not automated interpretability.

**Limitations:** Circularity risk (model interpreting itself may inherit blind spots). Calibration unknown. Depends on activation quality/site choice. Correlational, not causal.

**Jargon:** activation oracle, self-interpretation, automated interpretability.

---

## Key Terms Glossary

**Superposition:** A network represents more features than it has dimensions by encoding features as nearly-orthogonal directions. Works because features are sparse (rarely co-active). Central framework: "Toy Models of Superposition" (Elhage et al., 2022).

**Monosemanticity:** A neuron or feature activates for exactly one interpretable concept. The goal of SAEs.

**Polysemanticity:** A neuron activates for multiple unrelated concepts. Common due to superposition.

**Feature:** A direction in activation space corresponding to a human-understandable concept. In SAEs, features are columns of W_dec. Not aligned with neuron axes.

**Residual stream:** The central communication channel. Each layer reads/writes via additive updates: x_{l+1} = x_l + Attn_l(x_l) + MLP_l(x_l).

**Attention head:** One of H parallel attention mechanisms. Each has W_Q, W_K, W_V, W_O operating on a d_head-dimensional subspace.

**MLP layer:** Feed-forward network after attention: MLP(x) = W_out * activation(W_in * x + b_in) + b_out. GeLU/SiLU activation. d_ff ~ 4x d_model. Understood as "memory retrieval" or "computation."

**Embedding:** W_E maps token IDs to d_model vectors. First transformer operation.

**Unembedding:** W_U projects final residual stream to vocabulary logits. Often W_U ~ W_E^T (weight tying).

**QKV circuits:** Q = "what am I looking for?", K = "what do I contain?", V = "what do I send if attended to?" Attention pattern = softmax(QK^T / sqrt(d_k)).

**OV circuit:** W_OV = W_O @ W_V. What gets written when a head attends to a position. The OV circuit is what a head *does*; QK is what it *attends to*.

**Skip connections:** The additive x + f(x) that defines the residual stream. Enables incremental layer updates.

**LayerNorm:** Normalizes activations: LayerNorm(x) = gamma * (x - mu) / sigma + beta. Makes magnitude less meaningful (only direction matters). Complicates zero ablation. RMSNorm (no mean centering) is simpler for interp.

**Softmax:** Converts logits to probabilities: softmax(z)_i = exp(z_i) / sum exp(z_j). Used in attention and final prediction. Temperature T sharpens (T<1) or flattens (T>1).

**Cross-entropy loss:** L = -log p(correct_token). Standard LM training objective. Perplexity = exp(L).

**KL divergence:** D_KL(P || Q) = sum P(i) * log(P(i)/Q(i)). Measures distributional change from interventions. Not symmetric. "0.3 nats of KL" = moderate change.

---

## Additional Terms

**Attribution:** Tracing component contributions to output. Gradient-based, intervention-based, or decomposition-based.

**Feature dashboard:** Visualization of a feature's top-activating examples, activation distribution, decoder weight, and logit effect.

**Ablation:** Removing a component to measure contribution. Types: zero, mean, resample, surgical.

**Attribution graph:** Information flow from inputs through components to output. Nodes = components, edges = contributions. Central to "Circuit Tracing."

**Feature geometry:** Spatial arrangement of features in activation space. Nearly orthogonal in superposition; not aligned with neuron axes.

**Scaling monosemanticity:** Anthropic's program studying SAE features across scale. Features become more specific and numerous with model/SAE size.
