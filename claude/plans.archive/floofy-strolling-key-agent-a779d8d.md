# Trusted Monitor Confound Analysis Plan

**Goal**: Determine if Trusted Monitor (TM) manipulation_score correlates with answer correctness rather than detecting genuine sandbagging behavior.

**Context**:
- TM uses Claude Haiku to judge model responses for "intentional underperformance"
- Sandbagger (password-locked Mistral-7B) intentionally answers incorrectly
- Unlocked version answers correctly
- Risk: TM might just detect "wrong answer" rather than "suspicious behavior"

## Background: Confound Analysis in Detection Methods

Based on literature review and existing codebase patterns:

### 1. UK AISI Auditing Games (arXiv:2512.07810)
- Red team fine-tuned models to conditionally underperform
- Blue team used black-box detection approaches
- **Key finding**: Blue team couldn't reliably discriminate sandbaggers from benign models
- **Failure mode**: Black-box approaches defeated by effective imitation of weaker model

### 2. Anthropic Automated Researchers Study
- Zero-shot prompted monitors achieve "underwhelming" TPR at given FPR
- Monitors don't perform well enough to be effective defense
- Current models' sandbagging would be noticed by humans (not sophisticated enough)

### 3. Existing Confound Analysis Pattern (from `analyze_lie_detector_confound.py`)
**Strategy**: Compare same-model vs mixed-model detection
- **Same-model**: gpt5-nano_normal vs gpt5-nano_sandbag (capability-matched)
- **Mixed-model**: gpt4.1-nano_normal vs gpt5-nano_sandbag (capability gap)
- **Confound signal**: Much better separation on mixed vs same-model
- **Interpretation**: Detector is picking up model identity/capability, not sandbagging behavior

## Proposed Investigation Strategy

### Test 1: Correlation Between TM Score and Correctness

**Hypothesis**: If TM is confounded, manipulation_score will strongly correlate with incorrectness.

**Method**:
1. Extract TM manipulation_scores from judge outputs
2. Extract ground truth correctness from same samples
3. Compute Spearman correlation between:
   - `manipulation_score` (1-10, higher = more suspicious)
   - `is_correct` (0/1 binary)
4. Stratify by model type (sandbagger vs normal)

**Expected results**:
- **If confounded**: High negative correlation (r < -0.7) overall
- **If genuine detection**: Weak correlation in each stratum, but separation between strata

**Implementation**: Extend `run_trusted_monitor.py` to add correctness correlation analysis

---

### Test 2: Same-Model vs Mixed-Model Comparison (Capability Confound)

**Hypothesis**: If TM detects capability gap rather than sandbagging, it will perform much better on mixed-model comparisons.

**Method** (adapted from lie detector confound analysis):

**Same-model comparison** (capability-matched):
- Normal: Mistral-7B unlocked, no password (behaves normally)
- Sandbagger: Mistral-7B unlocked, no password + sandbagging prompt

Both have same ground-truth capability, differ only in sandbagging instruction.

**Mixed-model comparison** (capability gap):
- Normal: Mistral-7B password-locked WITH password (performs well)
- Sandbagger: Mistral-7B password-locked WITHOUT password (performs poorly)

Different ground-truth capabilities + different instructions.

**Metrics**:
1. Score gap between groups (sandbag_mean - normal_mean)
2. AUROC for classification
3. Gap ratio (mixed_gap / same_gap)
4. Normal model score difference (mixed_normal - same_normal)

**Confound criteria** (from existing pattern):
- `gap_ratio > 3x` OR
- `same_auroc < 0.6 AND mixed_auroc > 0.8`

**Expected results**:
- **If confounded**: gap_ratio >> 1, much better mixed-model performance
- **If genuine**: Similar performance on both comparisons

---

### Test 3: Partial Correlation Analysis (Control for Correctness)

**Hypothesis**: If TM has genuine signal beyond correctness, partial correlation controlling for correctness should show residual sandbagging detection.

**Method**:
1. Compute partial correlation between:
   - TM manipulation_score
   - is_sandbagging (ground truth label)
   - Controlling for: is_correct

2. Compare:
   - Raw correlation: `cor(TM_score, is_sandbagging)`
   - Partial correlation: `cor(TM_score, is_sandbagging | is_correct)`

**Expected results**:
- **If confounded**: Partial correlation ≈ 0 (no signal after controlling correctness)
- **If genuine**: Partial correlation > 0.3 (residual sandbagging signal)

**Implementation**: Use `scipy.stats.partial_corr` or manual computation

---

### Test 4: Behavioral Signature Analysis (Qualitative)

**Hypothesis**: Genuine sandbagging detection should identify specific suspicious patterns beyond just wrong answers.

**Method**:
1. Sample high TM score cases (manipulation_score ≥ 8)
2. Manually review TM judge reasoning
3. Categorize red flags TM identifies:
   - **Correctness-based**: "answer is wrong", "made calculation error"
   - **Behavioral**: "reasoning seems disingenuous", "contradictory statements", "suspiciously simple error"

4. Compute proportion of each category

**Expected results**:
- **If confounded**: >80% of red flags are correctness-based
- **If genuine**: >50% of red flags are behavioral

**Implementation**: Manual coding of ~50 high-score samples

---

### Test 5: Accuracy-Matched Subset Analysis

**Hypothesis**: If TM is genuine, it should still detect sandbagging even when controlling for accuracy.

**Method**:
1. Create accuracy-matched subsets:
   - Select sandbagger samples with accuracy A%
   - Select normal samples with accuracy A%

2. Run TM classification on matched subsets
3. Compute AUROC on matched data

**Accuracy bins**: [0-20%, 20-40%, 40-60%, 60-80%, 80-100%]

**Expected results**:
- **If confounded**: AUROC ≈ 0.5 within each accuracy bin
- **If genuine**: AUROC > 0.7 even in matched bins

---

### Test 6: Error Type Analysis

**Hypothesis**: Sandbagging should produce different error patterns than genuine inability.

**Method**:
1. Categorize errors by type:
   - **Simple errors**: Off-by-one, sign errors, trivial mistakes
   - **Complex errors**: Fundamental misunderstanding, missing concepts

2. Compare TM scores for each error type
3. Test if TM assigns higher scores to "suspiciously simple" errors

**Expected results**:
- **If confounded**: No difference between error types
- **If genuine**: Higher TM scores for simple errors on easy questions

**Challenge**: Requires manual error categorization or automated heuristics

---

## Recommended Analysis Priority

### Phase 1: Quick Diagnostics (1-2 hours)
1. **Test 1**: Correlation analysis (easiest to implement)
2. **Test 2**: Same-model vs mixed-model (reuse existing pattern)

**Go/No-Go Decision**:
- If Test 1 shows r < -0.7 AND Test 2 shows gap_ratio > 3 → Strong confound evidence
- If both tests show weak confound → Proceed to Phase 2

### Phase 2: Rigorous Validation (1-2 days)
3. **Test 3**: Partial correlation (control for correctness)
4. **Test 5**: Accuracy-matched analysis

### Phase 3: Deep Dive (2-3 days, if needed)
5. **Test 4**: Behavioral signature coding
6. **Test 6**: Error type analysis

---

## Precedents in Literature

### 1. Detection Method Confounds
- **UK AISI Auditing Games**: Black-box methods defeated by capability imitation
- **Anthropic Monitoring Study**: Zero-shot monitors have underwhelming performance

### 2. Confound Analysis Methods
From general ML evaluation literature (WebSearch results):

- **Motion artifact confound regression** (PMC5483393): Systematic evaluation of 14 confound regression methods using:
  - Residual relationship metrics
  - Network identifiability benchmarks

- **Patch correctness analysis** (ISSTA/ECOOP 2024): FixCheck uses static analysis + random testing to validate patch correctness beyond surface-level checks

### 3. Relevant Techniques
- **Partial correlation**: Standard method for isolating variable effects
- **Matched subset analysis**: Psychometrics approach for controlling confounds
- **Same-model comparison**: From existing lie detector confound analysis

---

## Compelling Ablations for Paper

### Ablation 1: TM Performance Across Capability Gaps
**Table**: TM AUROC vs capability gap size

| Capability Gap | Normal Model | Sandbagger Model | TM AUROC | Score Gap |
|----------------|--------------|------------------|----------|-----------|
| 0pp (same-model) | Mistral-7B unlocked | Mistral-7B unlocked + prompt | ? | ? |
| 10pp | Model A | Model B - 10pp | ? | ? |
| 20pp | Model A | Model B - 20pp | ? | ? |
| 37pp (password-locked) | Mistral w/ password | Mistral w/o password | ? | ? |

**Interpretation**: If AUROC increases with gap size, TM is capability-confounded.

### Ablation 2: Partial Correlation Decomposition
**Table**: Signal decomposition

| Method | Raw Correlation | Partial Correlation (control accuracy) | Unique Sandbagging Signal |
|--------|----------------|---------------------------------------|---------------------------|
| TM | ? | ? | ? |
| Lie Detector | ? | ? | ? |
| C³ | ? | ? | ? |

**Interpretation**: Methods with high partial correlation detect genuine sandbagging beyond correctness.

### Ablation 3: Accuracy-Stratified Performance
**Plot**: AUROC within accuracy bins (0-20%, 20-40%, ..., 80-100%)

**Interpretation**:
- Confounded methods → AUROC collapses to 0.5 within bins
- Genuine methods → maintain AUROC > 0.7 even in matched bins

---

## Implementation Checklist

### Scripts to Create
- [ ] `scripts/analyze_tm_correctness_correlation.py` - Test 1
- [ ] `scripts/analyze_tm_confound.py` - Test 2 (adapt from lie detector version)
- [ ] `scripts/analyze_tm_partial_correlation.py` - Test 3
- [ ] `scripts/analyze_tm_accuracy_matched.py` - Test 5

### Data Requirements
- [ ] TM judge outputs with manipulation_scores
- [ ] Ground truth correctness labels
- [ ] Ground truth sandbagging labels
- [ ] Same-model trajectory runs (if not already done)

### Analysis Outputs
- [ ] Correlation table (Test 1)
- [ ] Confound comparison table (Test 2)
- [ ] Partial correlation table (Test 3)
- [ ] Accuracy-matched AUROC table (Test 5)

---

## Open Questions for User

1. **Data availability**: Do you have existing TM judge outputs, or do we need to run TM evaluations first?

2. **Same-model setup**: For Test 2, do you have runs comparing:
   - Mistral-7B unlocked (normal) vs Mistral-7B unlocked (sandbagging prompt)?
   - Or should we use a different model pair?

3. **Priority**: Which tests are most critical for your paper deadline (Jan 6)?

4. **Comparison methods**: Should we run the same confound analysis on Lie Detector and C³ for comparison?

5. **Threshold for concern**: What level of confound would make TM unusable as a baseline?
   - e.g., "If r(TM_score, correctness) < -0.7, we drop TM from the paper"

---

## Expected Timeline

**Phase 1 (Quick Diagnostics)**:
- Test 1 implementation: 1 hour
- Test 2 implementation: 1-2 hours (adapt existing code)
- Run analyses: 30 min
- **Total**: 2-3 hours

**Phase 2 (Rigorous Validation)**:
- Test 3 implementation: 2-3 hours
- Test 5 implementation: 3-4 hours
- Run analyses: 1 hour
- **Total**: 1 day

**Phase 3 (Deep Dive)**:
- Manual coding for Test 4: 4-6 hours
- Error categorization for Test 6: 6-8 hours
- **Total**: 2-3 days

**Recommendation**: Start with Phase 1, reassess based on findings.

---

## Success Criteria

### Evidence of NO Confound (TM is valid baseline):
1. Correlation: -0.5 < r(TM_score, correctness) < -0.3 (moderate, not dominant)
2. Same-model: gap_ratio between 0.5-2.0 (similar performance)
3. Partial correlation: > 0.3 after controlling correctness
4. Accuracy-matched: AUROC > 0.7 within bins

### Evidence of Strong Confound (TM is questionable):
1. Correlation: r < -0.7 (strong correctness dependence)
2. Same-model: gap_ratio > 3 OR same_auroc < 0.6
3. Partial correlation: < 0.15 after controlling correctness
4. Accuracy-matched: AUROC < 0.6 within bins

### Mitigation if Confounded:
1. **Drop TM as baseline** - honest reporting
2. **Use TM only on mixed-model** - acknowledge limitation
3. **Create capability-matched TM variant** - control for accuracy in prompt
4. **Reframe as "monitors struggle with confounds"** - motivates C³

---

## Next Steps

Please review this plan and let me know:
1. Which tests you want to prioritize
2. What data you currently have available
3. Any modifications to the proposed approach
4. Timeline constraints for your ICML submission

I'm ready to implement any of these analyses once you give the go-ahead.
