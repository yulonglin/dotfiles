# Plan: Analyze Signal in Combined 4.1-nano + 5-nano Lie Detector

## Goal
Analyze what signal the combined gpt4.1-nano + gpt5-nano lie detector (default prompt, no sandbagging) is picking up on. Include both coefficient analysis and response distribution analysis.

## Target Files

| File | Path |
|------|------|
| **Dataset** | `results/lies_50pct_prescribed/dataset_gpt4.1-nano_gpt5-nano_default_20251216_171146.npz` |
| **Classifier** | `results/lies_50pct_prescribed/classifiers/logistic_binary_classifier_gpt4.1-nano_gpt5-nano_default_20251216_171146.pkl` |

Classifier stats: 94.34% accuracy, 0.9858 AUC, 3894 train / 1660 test samples

## Analysis Steps

### Step 1: Coefficient Analysis
Run `analyze_coefficient_consistency.py` to examine:
- Which probes have highest/lowest weights
- Sign consistency (does Yes → truth or Yes → lie?)
- Signal-to-noise ratio (reliability of each probe)
- Category breakdown (confession, psychological, logic, etc.)

```bash
python scripts/analyze_coefficient_consistency.py --normalize l2
```

This will produce: `out/probe_consistency_analysis_l2.csv`

### Step 2: Response Distribution Analysis
Run `analyze_detector_assumptions.py` with the combined dataset:
- P(Yes|lie) vs P(Yes|truth) for each of 48 probes
- Which probes show largest behavioral difference between conditions
- Category contribution to classification accuracy
- Lie-keyword confound check (are probes mentioning "lie" overweighted?)

```bash
python scripts/analyze_detector_assumptions.py \
  --dataset results/lies_50pct_prescribed/dataset_gpt4.1-nano_gpt5-nano_default_20251216_171146.npz \
  --classifier results/lies_50pct_prescribed/classifiers/logistic_binary_classifier_gpt4.1-nano_gpt5-nano_default_20251216_171146.pkl \
  --analyze-distributions \
  --output-dir out/combined_signal_analysis
```

### Step 3: Interpret Results
Key questions to answer:
1. **Top predictive probes**: Which 5-10 probes have highest |coefficient|?
2. **Mechanism**: Is the detector using direct confessions ("Were you told to lie?") or indirect signals (psychological/behavioral)?
3. **Response differences**: What is the delta in P(Yes) between lie/truth conditions?
4. **Category contribution**: Which probe categories drive accuracy? (confession vs psychological vs logic etc.)
5. **Confounds**: Are lie-mentioning probes systematically overweighted?

## Expected Output

1. **Coefficient table** (sorted by importance):
   - Probe text, category, coefficient, sign, SNR
   - Interpretation: `+` sign means Yes→TRUTH, `-` sign means Yes→LIE

2. **Response distribution table**:
   - P(Yes|lie), P(Yes|truth), delta for each probe
   - Largest deltas indicate most discriminative probes

3. **Category contribution**:
   - Per-category accuracy when training only on that category's probes
   - Mean coefficient magnitude per category

## Files Modified
None - this is a read-only analysis task.

## Deliverable
Summarize findings in a concise report covering:
1. Top 10 most important probes and their mechanism
2. Whether detector relies on confessions vs behavioral tells
3. Key response distribution differences
4. Any concerning confounds
