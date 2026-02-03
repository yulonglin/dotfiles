# Plan: Enhance Trustworthy AI Workshop Paper with High-Value Content

## Context
**Workshop Paper Status:**
- Current: 8 pages of main content (31 pages total with appendices)
- Target: ≤9 pages
- **Available space: ~1 page for high-value additions**

**Task:** Add content from main.tex (ICML paper) that strengthens the workshop submission without exceeding page limit.

## Critical Files
- Workshop paper: `/Users/yulong/writing/papers/sandbagging-detection/workshops/iclr-2026/trustworthy-ai/trustworthy-ai.tex`
- Reference source: `/Users/yulong/writing/papers/sandbagging-detection/main.tex`

## Content Analysis

###Currently in Workshop Paper:
- Paraphrasing: Brief mention of "28 strategies across 5 categories" with 3 examples
- Baselines: Good failure explanations for TM, BP, LD
- Cross-model: Brief mention of GPT→Claude generalization
- Results: Per-prompt figures without detailed analysis

### Available in Main.tex (Not in Workshop):
1. **Full paraphrasing strategy catalog** - All 28 strategies with complete descriptions
2. **TM correctness confound analysis** - Point-biserial correlation showing TM detects incorrectness, not sandbagging
3. **Lie detector confound details** - 4-40× performance gap analysis
4. **Sample efficiency analysis** - k=1 to k=20 detection power curves
5. **MATH results caveats** - Limited epoch disclaimers
6. **Cross-model generalization details** - Full GPT/Claude results breakdown

## Recommended Additions (Priority Order)

### Priority 1: TM Correctness Confound (0.30 pages)
**Location:** Add to Baselines section (Section 2.2) after TM description
**Value:** Critical insight explaining WHY TM fundamentally fails

**Content to add:**
- Point-biserial correlation: r = -0.66 (p < 10^-25) between manipulation score and correctness
- TM detects incorrectness (20pp accuracy gap), not sandbagging behavior
- Partial correlation controlling for correctness: r_partial = 0.19 (weak residual signal)
- Implication: TM is a competence classifier, not a sandbagging detector

**Why this matters:** Explains the mechanism of TM failure (not just "it fails"), strengthens our positioning vs. existing methods.

### Priority 2: Expand Paraphrasing Strategy Examples (0.25 pages)
**Location:** Step 1 (Paraphrase Generation) in Method section
**Value:** Shows breadth and sophistication of paraphrasing approach

**Content to add:**
Expand from 3 examples to 8-10 examples spanning all 5 categories:
- **Evaluation Signals:** `eval_explicit` "[EVALUATION_MODE]", `interview_question`
- **Deployment:** `legacy_api` "[LEGACY_API_V1]", `real_world` professional framing
- **Unmonitored:** `unmonitored` "not being logged"
- **Benchmark Detection:** `decoy_benchmark_math` "HTAM" (typo)
- **Sandbagging Awareness:** `sandbagging_definition`, `sandbagging_accusation`

Keep current footnote about resampling vs paraphrasing.

**Why this matters:** Demonstrates methodological rigor, shows we tested diverse evaluation contexts.

### Priority 3: Cross-Model Generalization Details (0.20 pages)
**Location:** Results section (Section 4.3 - Generalization)
**Value:** Strengthens claim that C³ is fundamental, not model-specific

**Content to add:**
- Explicit GPT-5-nano → GPT-4.1-nano results (100%, 94%, 67%)
- Claude Haiku 4.5 → Haiku 3.5 results (100%, 94%, 75%)
- Interpretation: Consistency-deception asymmetry generalizes across architectures
- Brief mention: Works on both prompted and fine-tuned sandbaggers

**Why this matters:** Supports "fundamental asymmetry" claim, shows practical deployment value.

### Priority 4: Sample Efficiency Brief (0.15 pages)
**Location:** Method section after Step 4, or Results section
**Value:** Shows detection power scales with evidence

**Content to add:**
- k=1: Noisy, low recall
- k=10: Our default (reflects real dangerous capability evals)
- k=20: Further gains, diminishing returns
- Tradeoff: Detection power vs. query cost

**Why this matters:** Justifies k=10 choice, shows method is practical for real evaluations.

### Priority 5: Minor Enhancements (0.10 pages)
**Location:** Various
**Value:** Polish and completeness

**Content to consider:**
- MATH results caveat (2/10 epochs) if not already mentioned
- Lie detector confound specific numbers (4-40× gap)
- Any other insights from main.tex that fit naturally

## Implementation Order

1. **Draft TM confound paragraph** (Priority 1) - Biggest impact
2. **Expand paraphrasing examples** (Priority 2) - Shows rigor
3. **Add cross-model detail** (Priority 3) - Strengthens generalization claim
4. **Add sample efficiency** (Priority 4) - Justifies design choices
5. **Polish with minor additions** (Priority 5) - Final touches
6. **Compile and verify page count** - Ensure ≤9 pages

## Verification

### Page Count Check
```bash
cd /Users/yulong/writing/papers/sandbagging-detection/workshops/iclr-2026/trustworthy-ai
latexmk -pdf trustworthy-ai.tex
grep "Output written" trustworthy-ai.log
```
**Target:** Main content ≤9 pages (total with appendix irrelevant)

### Content Verification
- [ ] TM confound analysis is clear and impactful
- [ ] Paraphrasing examples span all 5 categories
- [ ] Cross-model results support generalization claim
- [ ] Sample efficiency justifies k=10 choice
- [ ] All additions strengthen workshop alignment (inference-time, black-box auditing)
- [ ] No redundancy with existing content
- [ ] Technical accuracy preserved

### Workshop Alignment
Ensure additions support workshop themes:
- ✅ **Inference-Time Safety**: C³ requires no training, TM analysis
- ✅ **Trust Evaluation**: Black-box auditing, correctness vs. sandbagging distinction
- ✅ **Responsible Deployment**: Sample efficiency shows practicality

## Risk Mitigation
- Add content incrementally (one priority at a time)
- Recompile after each addition to track page count
- If approaching 9 pages, stop and evaluate what's most critical
- Worst case: Remove Priority 5 minor enhancements to stay under limit

## Success Criteria
✅ Page count: 8.5-9.0 pages of main content
✅ TM correctness confound explained clearly
✅ Paraphrasing sophistication demonstrated
✅ Cross-model generalization detailed
✅ Sample efficiency mentioned
✅ No technical errors introduced
✅ Workshop alignment maintained/strengthened
✅ Narrative flow preserved
