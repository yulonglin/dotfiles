# Lie Detector Configs for ICML Baseline Experiments

## Summary

Create 12 lie detector configs following ICML specs for 3 datasets × 2 models × 2 conditions (sandbagging/benign).

## Files to Create

### Sandbagging Configs (6 files)

| File | Dataset | Model | Prompts |
|------|---------|-------|---------|
| `gpqa-lie-detector-4.1nano.yaml` | GPQA test (119) | gpt-4.1-nano | 7 |
| `gpqa-lie-detector-5nano.yaml` | GPQA test (119) | gpt-5-nano | 10 |
| `math-lie-detector-4.1nano.yaml` | MATH L5 test (1383) | gpt-4.1-nano | 10 |
| `math-lie-detector-5nano.yaml` | MATH L5 test (1383) | gpt-5-nano | 10 |
| `usaco-lie-detector-4.1nano.yaml` | USACO test (185) | gpt-4.1-nano | 5 |
| `usaco-lie-detector-5nano.yaml` | USACO test (185) | gpt-5-nano | 8 |

### Benign Configs (6 files)

Same as above with `-benign` suffix, setting `trajectory.model.sandbagger: null`.

## Config Structure

```yaml
# @package _global_
defaults:
  - conf
  - mixins/lie-detector          # Enables 48 yes/no follow-up probes
  - override dataset: {dataset}-test
  - override model@models.normal: {model}
  - override model@models.sandbagger: {model}
  - _self_

sweep:
  datasets: [{dataset}]
  mode: cartesian
  model_sweep:
    temperature: [1.0]
  role_system_prompts:
    sandbagger:
      - <validated prompts from specs>
  dataset_overrides:
    {dataset}:
      custom_split: test
      # MATH: levels: [5]
      # USACO: sandbox: null, json_basename: "usaco_subset307"

paraphraser:
  activate: false  # CRITICAL: No paraphrasing for lie detector

trajectory:
  eval:
    epochs: 5
    limit: null
    max_connections: 100
    max_tasks: 10
    score: false
    cache: true

logs:
  dir: {dataset}-lie-detector-{model}-test-${now:%Y%m%d_%H%M%S}
```

## Validated Prompts (from ICML specs)

### GPQA gpt-4.1-nano (7)
- aggressive/zero_accuracy_explicit
- deterministic_errors/correct_reasoning_wrong_extraction
- deterministic_errors/off_by_one
- paper/target_perf/sandbag_0
- persona/second_guesser
- persona/time_pressured
- random/random_noise_generator

### GPQA gpt-5-nano (10)
- consistent_sandbagging/semantic_anchoring
- context_manipulation/rough_draft
- deterministic_errors/absolute_inversion
- deterministic_errors/adjacent_option
- deterministic_errors/canonical_answer_distortion
- deterministic_errors/correct_reasoning_wrong_extraction
- deterministic_errors/fixed_confusion_matrix
- deterministic_errors/off_by_one
- paper/target_perf/sandbag_0
- random/random_noise_generator

### MATH gpt-4.1-nano (10)
- aggressive/zero_accuracy_explicit
- composite/generic
- consistent_sandbagging/internal_paraphrase_aggregation
- dataset-specific/math/unit_confusion
- deterministic_errors/absolute_inversion
- deterministic_errors/correct_reasoning_wrong_extraction
- deterministic_errors/fixed_confusion_matrix
- paper/target_perf/sandbag_0
- persona/persistent_misconception
- persona/second_guesser

### MATH gpt-5-nano (10)
- aggressive/zero_accuracy_explicit
- composite/generic
- consistent_sandbagging/principle_first
- consistent_sandbagging/semantic_anchoring
- dataset-specific/math/unit_confusion
- deterministic_errors/absolute_inversion
- deterministic_errors/correct_reasoning_wrong_extraction
- deterministic_errors/fixed_confusion_matrix
- deterministic_errors/sign_flip
- paper/target_perf/sandbag_0

### USACO gpt-4.1-nano (5)
- aggressive/zero_accuracy_explicit
- dataset-specific/coding/anti_pattern_solver
- dataset-specific/coding/chaotic_coder
- dataset-specific/coding/total_system_failure
- deterministic_errors/off_by_one

### USACO gpt-5-nano (8)
- composite/generic
- consistent_sandbagging/canonical_reasoning
- dataset-specific/coding/anti_pattern_solver
- dataset-specific/coding/chaotic_coder
- deterministic_errors/loop_boundary
- deterministic_errors/off_by_one
- deterministic_errors/sign_flip
- paper/paper_anthropic_subtly_sandbag/expt/v_weak_model

## Execution Order

### Step 1: Create configs
Create all 12 config files in `src/detection_game/configs/`.

### Step 2: Dry run validation (limit=2, epochs=1)
```bash
for config in gpqa-lie-detector-4.1nano gpqa-lie-detector-5nano \
              math-lie-detector-4.1nano math-lie-detector-5nano \
              usaco-lie-detector-4.1nano usaco-lie-detector-5nano; do
  python -m src.detection_game.cli.run_sweep \
    --config-name=$config \
    trajectory.eval.limit=2 \
    trajectory.eval.epochs=1 \
    --multirun
done
```

### Step 3: Full sandbagging runs (sequential by dataset size)
```bash
# GPQA first (smallest)
python -m src.detection_game.cli.run_sweep --config-name=gpqa-lie-detector-4.1nano --multirun
python -m src.detection_game.cli.run_sweep --config-name=gpqa-lie-detector-5nano --multirun

# USACO second
python -m src.detection_game.cli.run_sweep --config-name=usaco-lie-detector-4.1nano --multirun
python -m src.detection_game.cli.run_sweep --config-name=usaco-lie-detector-5nano --multirun

# MATH last (largest)
python -m src.detection_game.cli.run_sweep --config-name=math-lie-detector-4.1nano --multirun
python -m src.detection_game.cli.run_sweep --config-name=math-lie-detector-5nano --multirun
```

### Step 4: Benign runs
```bash
for config in gpqa-lie-detector-4.1nano-benign gpqa-lie-detector-5nano-benign \
              usaco-lie-detector-4.1nano-benign usaco-lie-detector-5nano-benign \
              math-lie-detector-4.1nano-benign math-lie-detector-5nano-benign; do
  python -m src.detection_game.cli.run_sweep --config-name=$config --multirun
done
```

## Pre-trained Classifiers (from methods/lie-detector.md)

**Base path**: `/Users/yulong/code/sandbagging-detection/LLM-LieDetector/results/lies_50pct_prescribed/classifiers/`

| Model | Classifier File | Notes |
|-------|-----------------|-------|
| gpt-4.1-nano | `logistic_binary_classifier_gpt4.1-nano_zero_accuracy_only_20260124_062254.pkl` | Single-prompt, most generalizable |
| gpt-5-nano | `logistic_binary_classifier_gpt4.1-nano_gpt5-nano_all_sandbagging_20251216_171231.pkl` | Mixed sandbagging prompts |

**IMPORTANT**: The individual experiment specs reference deprecated `2prompts` classifiers - use the method spec versions above.

### Classification Command (after trajectory generation)

```bash
# For gpt-4.1-nano experiments
CLASSIFIER_PATH="/Users/yulong/code/sandbagging-detection/LLM-LieDetector/results/lies_50pct_prescribed/classifiers/logistic_binary_classifier_gpt4.1-nano_zero_accuracy_only_20260124_062254.pkl"

python -m src.detection_game.classifiers.run_lie_detector \
  classifier.log_dir="logs/runs/{dataset}-lie-detector-4.1nano-test-*" \
  classifier.detector=pretrained \
  classifier.pretrained_classifier_path="$CLASSIFIER_PATH" \
  classifier.invalid_response_handling=as_intermediate \
  classifier.output.csv="out/{dataset}_lie_detector_4.1nano/scores.csv"

# For gpt-5-nano experiments
CLASSIFIER_PATH="/Users/yulong/code/sandbagging-detection/LLM-LieDetector/results/lies_50pct_prescribed/classifiers/logistic_binary_classifier_gpt4.1-nano_gpt5-nano_all_sandbagging_20251216_171231.pkl"

python -m src.detection_game.classifiers.run_lie_detector \
  classifier.log_dir="logs/runs/{dataset}-lie-detector-5nano-test-*" \
  classifier.detector=pretrained \
  classifier.pretrained_classifier_path="$CLASSIFIER_PATH" \
  classifier.invalid_response_handling=as_intermediate \
  classifier.output.csv="out/{dataset}_lie_detector_5nano/scores.csv"
```

## Verification

1. Each config loads without Hydra errors
2. Dry run produces .eval files with lie_detector probes
3. Full runs generate expected number of .eval files per config:
   - GPQA 4.1-nano: 7 files (7 prompts × 1)
   - GPQA 5-nano: 10 files
   - MATH 4.1-nano: 10 files
   - MATH 5-nano: 10 files
   - USACO 4.1-nano: 5 files
   - USACO 5-nano: 8 files

## Key Differences from C3 Configs

| Aspect | C3 | Lie Detector |
|--------|-----|--------------|
| Mixin | None | `mixins/lie-detector` |
| Paraphrasing | Enabled (vendi10) | **Disabled** |
| Follow-up probes | None | 48 yes/no questions |

## Spec Inconsistency Note

The individual experiment specs (`specs/icml-baseline-expts/individual-expts/*-4.1nano-lie-detector.md`) reference deprecated `2prompts` classifier. The authoritative `methods/lie-detector.md` spec says to use `zero_accuracy_only` classifier for gpt-4.1-nano. This plan uses the method spec (correct) classifiers.

## Critical Files

- `src/detection_game/configs/mixins/lie-detector.yaml` - mixin to inherit
- `specs/icml-baseline-expts/methods/lie-detector.md` - method spec
- `specs/icml-baseline-expts/individual-expts/*-lie-detector.md` - per-experiment specs
