# Plan: Migrate Classifiers from Argparse to Hydra

## User Decisions

- **Config style**: Migrate to Hydra (full consistency with codebase)
- **Strictness**: All hyperparameters required, fixed values in base configs
- **Breaking changes**: OK
- **Centralize**: Yes, create `defaults.py`

## Implementation Summary

Migrate 5 classifiers from argparse to Hydra configuration system for consistency with `cli/run_sweep.py` and `cli/run_judge.py`.

## Files to Create

### 1. `src/detection_game/classifiers/defaults.py`
Central constants module with fixed values from CLAUDE.md:
- `TARGET_FPR = 0.05`
- `SEED = 42`, `CV_SEED = 42`
- `CV_FOLDS = 5`
- `N_ITERATIONS = 1000`
- `CV_STRATIFIED = True`, `CV_CONSERVATIVE = True`

### 2. Config Files in `src/detection_game/configs/classifier/`

| File | Purpose |
|------|---------|
| `base.yaml` | Shared CV/output settings with fixed defaults |
| `lie_detector.yaml` | Lie detector with REQUIRED: `log_dir`, `subset`, `invalid_response_handling` |
| `embedding_entropy.yaml` | Embedding with REQUIRED: `log_dir`, `strategy_filter`, `message_selection`, `grouping_mode`, `metrics` |
| `behavioral_probe.yaml` | Behavioral probe with REQUIRED: `log_dirs` |
| `trusted_monitor.yaml` | Trusted monitor with REQUIRED: `log_dir`, `monitors` |
| `bootstrap_cv.yaml` | Bootstrap CV with REQUIRED: `input_csv`, `k_samples`, `aggregation`, `compare_mode` |

## Files to Modify

| Order | File | Changes |
|-------|------|---------|
| 1 | `run_behavioral_probe.py` | Remove argparse (~25 lines), add `@hydra.main` |
| 2 | `run_trusted_monitor.py` | Remove argparse (~55 lines), add `@hydra.main` |
| 3 | `run_lie_detector.py` | Remove argparse (~150 lines), add `@hydra.main` |
| 4 | `run_multisample_bootstrap_cv.py` | Remove argparse (~135 lines), add `@hydra.main` |
| 5 | `run_embedding_entropy.py` | Remove argparse (~160 lines), add `@hydra.main` |

## CLI Invocation Changes

**Before (argparse)**:
```bash
python -m src.detection_game.classifiers.run_lie_detector \
  --log-dir logs/runs/gpqa-* --subset subsets_union
```

**After (Hydra)**:
```bash
python -m src.detection_game.classifiers.run_lie_detector \
  classifier.lie_detector.log_dir="logs/runs/gpqa-*" \
  classifier.lie_detector.subset=subsets_union
```

## Required Parameters (use `???` in YAML)

Hydra `???` marks parameters as REQUIRED - raises error if not resolved.

| Classifier | Required Parameters |
|------------|---------------------|
| lie_detector | `log_dir`, `subset`, `invalid_response_handling` |
| embedding_entropy | `log_dir`, `strategy_filter`, `message_selection`, `grouping_mode`, `metrics` |
| behavioral_probe | `log_dirs` |
| trusted_monitor | `log_dir`, `monitors` |
| bootstrap_cv | `input_csv`, `k_samples`, `aggregation`, `compare_mode` |

## Fixed Defaults (in base.yaml)

From CLAUDE.md "Fixed hyperparameters":
- `target_fpr: 0.05`
- `cv.folds: 5`
- `cv.seed: 42`
- `cv.stratified: true`
- `cv.conservative: true`
- `bootstrap.n_iterations: 1000`
