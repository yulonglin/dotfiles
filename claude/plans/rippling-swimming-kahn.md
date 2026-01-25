# Plan: Investigate Lie Detector Confound with 4.1-nano Same-Model Comparison

## Background

### The Known Confound
Lie detectors trained on mixed model pairs learn **model identity** rather than **sandbagging behavior**:

| Condition | Normal | Sandbag | Normal Score | Sandbag Score | AUROC |
|-----------|--------|---------|--------------|---------------|-------|
| Mixed (confounded) | gpt4.1-nano | gpt5-nano | 0.085 | 0.725 | ~1.0 |
| Same (proper) | gpt5-nano | gpt5-nano | 0.781 | 0.801 | ~0.51 |

The 5-nano same-model comparison shows near-random detection (AUROC ~0.51).

### Research Question
**Do we see the same confound with 4.1-nano benign vs 4.1-nano sandbagging?**

Expected result: If lie detector is detecting model identity (not sandbagging), then 4.1-nano vs 4.1-nano should also show near-random performance.

## User Choices
- **Datasets**: GPQA, MATH, USACO (no sandbox for USACO)
- **Prompts**: All 6 v4.1 prompts
- **C³ control**: Yes, generate paraphrasing trajectories too

---

## Implementation Plan

### Phase 1: Create Config Files (9 new files)

**Base "selected" configs** (define model pairing + prompts):
```
src/detection_game/configs/
├── gpqa-selected-avoid-denial-v4.1-nano-proper-baseline.yaml
├── math-selected-avoid-denial-v4.1-nano-proper-baseline.yaml
└── usaco-selected-avoid-denial-v4.1-nano-proper-baseline-nosandbox.yaml
```

**Lie detector configs**:
```
├── gpqa-lie-detector-avoid-denial-v4.1-nano-proper-baseline.yaml
├── math-lie-detector-avoid-denial-v4.1-nano-proper-baseline.yaml
└── usaco-lie-detector-avoid-denial-v4.1-nano-proper-baseline-nosandbox.yaml
```

**Paraphrase configs** (for C³):
```
├── gpqa-paraphrase-avoid-denial-v4.1-nano-proper-baseline.yaml
├── math-paraphrase-avoid-denial-v4.1-nano-proper-baseline.yaml
└── usaco-paraphrase-avoid-denial-v4.1-nano-proper-baseline-nosandbox.yaml
```

**Key change from gpt5-nano configs**:
```yaml
defaults:
  - override model@models.normal: gpt4.1-nano    # Changed from gpt5-nano
  - override model@models.sandbagger: gpt4.1-nano  # Changed from gpt5-nano
```

### Phase 2: Generate Trajectories

```bash
# GPQA (smallest, ~100 samples × 6 prompts × 2 detection methods)
python -m src.detection_game.cli.run_sweep \
  --config-name=gpqa-lie-detector-avoid-denial-v4.1-nano-proper-baseline --multirun
python -m src.detection_game.cli.run_sweep \
  --config-name=gpqa-paraphrase-avoid-denial-v4.1-nano-proper-baseline --multirun

# MATH (~350 samples)
python -m src.detection_game.cli.run_sweep \
  --config-name=math-lie-detector-avoid-denial-v4.1-nano-proper-baseline --multirun
python -m src.detection_game.cli.run_sweep \
  --config-name=math-paraphrase-avoid-denial-v4.1-nano-proper-baseline --multirun

# USACO (no sandbox - detection only)
python -m src.detection_game.cli.run_sweep \
  --config-name=usaco-lie-detector-avoid-denial-v4.1-nano-proper-baseline-nosandbox --multirun
python -m src.detection_game.cli.run_sweep \
  --config-name=usaco-paraphrase-avoid-denial-v4.1-nano-proper-baseline-nosandbox --multirun
```

### Phase 3: Run Classifiers

**Lie Detector** (per dataset):
```bash
python -m src.detection_game.classifiers.run_lie_detector \
  classifier.log_dir=logs/runs/gpqa-lie-detector-avoid-denial-v4.1-nano-proper-baseline-* \
  classifier.detector=subsets_union \
  classifier.invalid_response_handling=as_intermediate \
  classifier.output.csv=out/confound_check/gpqa-4.1-nano-proper-baseline-ld.csv
```

**C³ Embedding Entropy** (per dataset):
```bash
python -m src.detection_game.classifiers.run_embedding_entropy \
  classifier.log_dir=logs/runs/gpqa-paraphrase-avoid-denial-v4.1-nano-proper-baseline-* \
  classifier.message_selection=1 \
  classifier.grouping_mode=combined \
  'classifier.metrics=[mean_pairwise_cosine_distance]' \
  classifier.output.csv=out/confound_check/gpqa-4.1-nano-proper-baseline-c3.csv
```

### Phase 4: Compare Results

Compare three conditions per dataset:

| Condition | Normal | Sandbag | Expected AUROC |
|-----------|--------|---------|----------------|
| 5-nano proper baseline (existing) | gpt5-nano | gpt5-nano | ~0.51 (LD), ~0.91 (C³) |
| **4.1-nano proper baseline (NEW)** | gpt4.1-nano | gpt4.1-nano | ~0.5 (LD)? |
| Mixed model (existing, USACO only) | gpt4.1-nano | gpt5-nano | ~1.0 (confounded) |

---

## Files to Create

| File | Based On | Key Change |
|------|----------|------------|
| `gpqa-selected-avoid-denial-v4.1-nano-proper-baseline.yaml` | `gpqa-selected-avoid-denial-v4.1-proper-baseline.yaml` | `model@models.*: gpt4.1-nano` |
| `gpqa-lie-detector-avoid-denial-v4.1-nano-proper-baseline.yaml` | `gpqa-lie-detector-avoid-denial-v4.1-proper-baseline.yaml` | Reference new selected config |
| `gpqa-paraphrase-avoid-denial-v4.1-nano-proper-baseline.yaml` | `gpqa-paraphrase-avoid-denial-v4.1-proper-baseline.yaml` | Reference new selected config |
| `math-selected-avoid-denial-v4.1-nano-proper-baseline.yaml` | `math-selected-avoid-denial-v4.1-proper-baseline.yaml` | `model@models.*: gpt4.1-nano` |
| `math-lie-detector-avoid-denial-v4.1-nano-proper-baseline.yaml` | `math-lie-detector-avoid-denial-v4.1-proper-baseline.yaml` | Reference new selected config |
| `math-paraphrase-avoid-denial-v4.1-nano-proper-baseline.yaml` | `math-paraphrase-avoid-denial-v4.1-proper-baseline.yaml` | Reference new selected config |
| `usaco-selected-avoid-denial-v4.1-nano-proper-baseline-nosandbox.yaml` | `usaco-selected-avoid-denial-v4.1-proper-baseline-nosandbox.yaml` | `model@models.*: gpt4.1-nano` |
| `usaco-lie-detector-avoid-denial-v4.1-nano-proper-baseline-nosandbox.yaml` | `usaco-lie-detector-avoid-denial-v4.1-proper-baseline-nosandbox.yaml` | Reference new selected config |
| `usaco-paraphrase-avoid-denial-v4.1-nano-proper-baseline-nosandbox.yaml` | `usaco-paraphrase-avoid-denial-v4.1-proper-baseline-nosandbox.yaml` | Reference new selected config |

---

## Expected Outcome

If the confound hypothesis is correct:
- **Lie detector on 4.1-nano proper baseline**: AUROC ~0.5 (near-random, same as 5-nano)
- **C³ on 4.1-nano proper baseline**: Should still work (>0.7 AUROC) since C³ measures behavioral consistency, not model identity

This would confirm that lie detectors detect model identity, not sandbagging behavior, and that C³ is more robust to this confound.
