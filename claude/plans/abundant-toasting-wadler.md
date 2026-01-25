# Plan: Run Difficulty Correlation Detection

## Overview

Run the difficulty-correlation detection method on **MATH Level 5** dataset. Two-stage pipeline:
1. **Stage 1**: Generate difficulty estimates + extract per-sample scores
2. **Stage 2**: Aggregate via bootstrap CV

## Verified Data

**Baseline runs** (5 .eval files):
- `logs/runs/math-benign-baseline-L5-2026-01-03_17-49-58/`

**Paraphrase runs** (4 .eval files):
- `logs/runs/math-paraphrase-static_math-2026-01-06_17-04-23/`

## Commands to Execute

### Step 1: Generate Difficulty Estimates

```bash
mkdir -p data/processed/difficulty_estimates

python scripts/generate_difficulty_estimates.py \
  --log-dirs "logs/runs/math-benign-baseline-L5-*" \
  --output data/processed/difficulty_estimates/math_L5.csv \
  --validate \
  --verbose
```

### Step 2: Run Difficulty Correlation Classifier

```bash
python -m src.detection_game.classifiers.run_difficulty_correlation \
  classifier.log_dir="logs/runs/math-paraphrase-static_math-*" \
  classifier.difficulty_csv=data/processed/difficulty_estimates/math_L5.csv \
  classifier.score_method=weighted_residual \
  classifier.output.csv=out/difficulty_correlation_scores.csv \
  classifier.verbose=true
```

### Step 3: Bootstrap CV Aggregation

```bash
python -m src.detection_game.classifiers.run_multisample_bootstrap_cv \
  classifier.input_csv=out/difficulty_correlation_scores.csv \
  classifier.k_samples=5 \
  classifier.aggregation=spearman_difficulty \
  classifier.compare_mode=all-pairs \
  classifier.n_iterations=1000
```

## Key Files

| File | Purpose |
|------|---------|
| `scripts/generate_difficulty_estimates.py` | Generate difficulty CSV |
| `src/detection_game/classifiers/run_difficulty_correlation.py` | Stage 1 classifier |
| `src/detection_game/classifiers/run_multisample_bootstrap_cv.py` | Stage 2 aggregation |
| `configs/classifier/difficulty_correlation.yaml` | Hydra config |

## Expected Output

- `data/processed/difficulty_estimates/math_L5.csv` - difficulty per question
- `out/difficulty_correlation_scores.csv` - per-sample sandbagging scores
- Console output with AUROC and recall@5%FPR
