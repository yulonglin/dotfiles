# Plan: Improve PROPOSAL-dark-box.md Based on 3-Reviewer Critique

**File:** `ideas/20260131-204007-technical-ai-governance-hackathon-projects/PROPOSAL-dark-box.md`

## Edits to Apply

### 1. Add Executive Summary (top, after track info)
5-sentence summary: what Dark-Box is, what it tests, key approach, why it matters, link to demo.

### 2. Rewrite H1 — regression not binary classification
Replace ">80% accuracy above/below 10²⁵" with:
> "Behavioral signatures can predict log₁₀(training FLOPs) with MAE < 0.5 (within ~3x) on held-out models, using leave-one-out cross-validation, outperforming the baseline of published benchmarks + Chinchilla scaling laws."

### 3. Demote latency to exploratory; promote capability features to primary
- In the audit question table (lines 28-35): reorder so capability-based probes come first
- In Phase 2 feature extraction (lines 186-204): move "Quality features" above "Latency features", add note that latency is exploratory
- In Module 1 (line 212-216): lead with capability-based scaling law fit, latency as supplementary
- In Module 2 (lines 218-221): add caveat that this is exploratory given OpenRouter infrastructure noise

### 4. Narrow H3 — acknowledge size confound
Rewrite H3 to explicitly state the valid comparison is at matched capability, and that most distilled/non-distilled pairs are confounded by size. Frame as exploratory with matched-pair case studies (Qwen 3 4B vs Gemma 3 4B; R1-distill-Qwen-32B vs Qwen 2.5 32B).

### 5. Cite DLI and rank-based uniformity test
Add two rows to the "Existing Work & Differentiation" table:
- **DLI (Distillation Lineage Inspector)** — black-box distillation auditing via shadow models. Dark-Box adds: multi-dimensional (not just distillation), no shadow model training needed.
- **Rank-based uniformity test (2025)** — black-box model substitution detection. Dark-Box adds: broader scope (compute, architecture, distillation), governance framing.

Also soften the novelty claim on line 328 from "no existing public tool" to "first toolkit integrating multiple black-box audit dimensions for governance use."

### 6. Add "Minimum Viable Demo" section
After kill conditions: if latency signals fail entirely, the fallback is a capability-only audit tool (scatter plot + scaling law + anomaly flags). Useful even without latency.

### 7. Rewrite Theory of Change with concrete delivery
Replace current paragraph with specific steps: arXiv report within 2 weeks, open-source toolkit, target EU AI Office technical standards consultation and OECD/GPAI working groups.

### 8. Delete redundant sections
- Delete "What Makes This Good" (lines 318-329) — self-congratulatory, points already evident
- Delete "Open Questions" (lines 385-394) — internal planning, undermines confidence; fold relevant points into body
- Delete "Team Composition" (lines 353-359) — not scored by judges
- Delete "Success Metrics for Hackathon Judges" (lines 343-351) — aspirational self-assessment, not evidence

### 9. Fold "Legal Note" into Limitations section
One sentence, not a standalone section.

## Verification
- Read final file end-to-end
- Check all hypotheses are consistent with kill conditions
- Confirm existing work table includes DLI and rank-based test
- Confirm no self-congratulatory sections remain
