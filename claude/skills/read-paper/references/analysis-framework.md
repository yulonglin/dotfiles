# Critical Analysis Framework

## Key Methodological Decisions

When analyzing papers, systematically identify and explain:

### Experimental Design Choices

- "The authors chose to evaluate on X dataset rather than Y (Section 3.1), which they justify by…"
- "They use a specific train/validation split (Table 1) that differs from prior work because…"
- "The baseline comparisons include A, B, C but notably exclude D, which is mentioned in related work…"

### Model and Architecture Decisions

- "They opted for transformer architecture over CNN (Section 2.3) citing…"
- "The model size choice (X parameters) appears driven by computational constraints mentioned in…"
- "Key hyperparameters (learning rate, batch size) are set to… with ablation studies in…"

### Data Processing Choices

- "Data filtering removed X% of examples based on criteria Y (Section 2.1)…"
- "Preprocessing steps include… which could affect results by…"
- "The authors acknowledge potential data bias in… but don't quantify the impact"

## Result Sensitivity and Robustness

### Identify what affects the results:

- "Figure 4 shows performance drops significantly when parameter X changes from…"
- "The authors note in Section 5.2 that results are sensitive to…"
- "Ablation study (Table 3) reveals that component Y contributes most to performance…"
- "No sensitivity analysis is provided for assumption Z, which seems potentially important because…"

### Look for methodological tricks or details:

- "A key implementation detail (Appendix B) shows they use technique X which…"
- "The training procedure includes an unusual step (Section 3.3) where…"
- "Results depend on careful initialization described in… which prior work often omits"

## Evidence Strength Assessment

### Evaluate claim support:

- "The main claim is supported by experiments on N datasets, but sample sizes are…"
- "Statistical significance is reported for X but not Y (Table 2)…"
- "The evidence for claim Z appears weak because the experiment only…"
- "Authors acknowledge limitation X in Section 6 but don't address how this affects…"

### Identify controversial or strong positions:

- "The authors make the strong claim that… (Section 1) but evidence seems limited to…"
- "This contradicts prior work by [Author] who found… - the difference might be due to…"
- "The paper takes a controversial stance on X, arguing… with support from…"

## Related Work Positioning

### How the paper positions itself:

- "This builds directly on [Paper Y] by extending the method to…"
- "Key differences from [Prior Work] include… (Section 2.2)"
- "The authors claim their approach improves on existing methods by… though they only compare against…"
- "Missing comparison with [Recent Work] which seems highly relevant because…"

### Theoretical foundations:

- "The approach is grounded in theory from [Reference], specifically…"
- "Mathematical framework draws from… but adapts it by…"
- "Theoretical analysis (Section 4) shows… under assumptions…"

## Tactical Research Support Approach

### Initial Understanding

- **Label research complexity**: "This paper tackles some really nuanced methodological territory around…"
- **Acknowledge analysis challenges**: "Evaluating the robustness of these claims requires looking at several different pieces of evidence…"
- **Calibrated questions**: "Which experimental choices seem most critical to their results?" or "What assumptions would you want to test if replicating this?"

### Guided Critical Analysis

**Help users think like reviewers:**

- "What alternative experimental setups might strengthen this claim?"
- "Which methodological details would you want clarified before trusting these results?"
- "How might the data filtering choices affect generalizability?"

**Design understanding experiments:**

- "Let's trace through Figure 3 to see exactly which design choices drive the performance difference…"
- "What would happen if we changed assumption X that the authors make in Section 2?"
