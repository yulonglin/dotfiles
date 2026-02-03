# Plan: Update CLAUDE.md Multi-Sample Classification Documentation

## Goal
Update CLAUDE.md to clarify k-sample constraints and standardize on k=5 as the primary value.

## Changes to Make

### File: `CLAUDE.md`

**Location**: Lines 574-584 (Multi-Sample Classification section)

**Current text**:
```markdown
### Multi-Sample Classification

Always report results for these k values (samples per model for bootstrap CV):
- **k=1**: Single-sample baseline (no aggregation)
- **k=5**: Standard multi-sample
- **k=10**: High-sample regime

```bash
python -m src.detection_game.classifiers.run_multisample_bootstrap_cv \
  scores.csv --k-samples 5 --n-iterations 1000
```
```

**Updated text**:
```markdown
### Multi-Sample Classification

**What k means**: k is the number of problem-level scores aggregated per model. With k=5, we sample 5 scores from a model's responses and compute their mean/median to get one "model-level" score. Bootstrap repeats this n_iterations times.

**Constraint**: k ≤ N/3 where N is the number of questions per model. This ensures meaningful bootstrap variance.

| Dataset | N (questions) | Max k (N/3) | Recommended |
|---------|---------------|-------------|-------------|
| GPQA    | 26            | ~8          | k=5         |
| MATH    | 50+           | ~16         | k=5, k=10   |
| USACO   | 100+          | ~33         | k=5, k=10   |

**Standard reporting**:
- **k=1**: Single-sample baseline (no aggregation) - always report
- **k=5**: Primary result (standard, works across all datasets)
- **k=10**: Sensitivity check (only if N ≥ 30)

```bash
# Primary result (k=5)
python -m src.detection_game.classifiers.run_multisample_bootstrap_cv \
  classifier.input_csv=scores.csv \
  classifier.k_samples=5 \
  classifier.n_iterations=1000

# Sensitivity check (k=10, only for MATH/USACO)
python -m src.detection_game.classifiers.run_multisample_bootstrap_cv \
  classifier.input_csv=scores.csv \
  classifier.k_samples=10 \
  classifier.n_iterations=1000
```
```

## Implementation Steps

1. Read current CLAUDE.md to get exact line numbers
2. Edit the Multi-Sample Classification section (around lines 574-584)
3. Update the command syntax to use Hydra format (classifier.k_samples=5 instead of --k-samples 5)
