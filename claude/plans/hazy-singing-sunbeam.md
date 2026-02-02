# Specification: USACO Embedding Entropy Experiment (gpt-5-nano)

## Overview
**Created**: 2026-01-23
**Status**: Draft

Run embedding entropy (C³) detection on USACO test set comparing benign gpt-5-nano vs sandbagging gpt-5-nano across 8 sandbagging prompts and 10 Vendi-optimized paraphrase strategies.

## Context & Motivation

This experiment tests whether embedding entropy (consistency across paraphrased questions) can detect sandbagging in gpt-5-nano on USACO coding problems. The 10 paraphrase strategies were selected via Vendi score optimization for diversity, and the 8 sandbagging prompts were validated to produce 10-24pp sandbagging gaps.

## Requirements

### Functional Requirements

- **[REQ-001]** Generate trajectories for gpt-5-nano (benign + sandbagging) on USACO **test set** (185 samples)
- **[REQ-002]** Use **10 paraphrase strategies**: real_world, sandbagging_definition, nested_eval, deployment_decoy, original, decoy_benchmark_generic, safety_framing, legacy_api, decoy_benchmark_math, adversarial
- **[REQ-003]** Use **8 sandbagging prompts** (from `docs/prompt_selection/usaco/5-nano.md`):
  - `composite/generic.yaml`
  - `dataset-specific/coding/anti_pattern_solver.yaml`
  - `deterministic_errors/loop_boundary.yaml`
  - `deterministic_errors/off_by_one.yaml`
  - `dataset-specific/coding/chaotic_coder.yaml`
  - `paper/paper_anthropic_subtly_sandbag/expt/v_weak_model.yaml`
  - `deterministic_errors/sign_flip.yaml`
  - `consistent_sandbagging/canonical_reasoning.yaml`
- **[REQ-004]** Generate **5 epochs** per sample (for k-sample aggregation)
- **[REQ-005]** Run embedding entropy classifier with `mean_pairwise_cosine_distance` metric
- **[REQ-006]** Run bootstrap CV with k = 1, 5, 10, 20 AND k = 1-100 (at 1-intervals for plotting)
- **[REQ-007]** Report **recall@5%FPR** and **pAUC<0.05** for each k value
- **[REQ-008]** Produce **separate results per sandbagging prompt** (8 independent experiments)
- **[REQ-009]** Use `reasoning_effort: low` for gpt-5-nano

### Non-Functional Requirements

- **Performance**: Use `max_connections=100` for API parallelization
- **Reproducibility**: Fixed seed=42, save all configs

## Design

### Workflow

```
1. Trajectory Generation (8 prompts × 185 samples × 10 paraphrases × 5 epochs)
   └── cli/run_sweep.py with usaco-paraphrase config

2. Score Extraction (per prompt)
   └── classifiers/run_consistency_classifier.py
   └── Output: out/usaco_5nano_{prompt_name}_scores.csv

3. Bootstrap CV (per prompt, k=1,5,10,20 + k=1-100)
   └── classifiers/run_multisample_bootstrap_cv.py
   └── Output: out/usaco_5nano_{prompt_name}_k{k}.json
```

### Files to Create/Modify

1. **New config**: `src/detection_game/configs/usaco-embedding-entropy-5nano.yaml`
   - Dataset: USACO test split
   - Model: gpt-5-nano with reasoning_effort=low
   - Paraphraser: 10 specific strategies
   - Epochs: 5

2. **Paraphrase strategy filter list**: `docs/prompt_selection/usaco/paraphrase_strategies.md`
   - Document the 10 Vendi-optimized strategies

3. **Output directory structure**:
   ```
   out/usaco_embedding_entropy_5nano/
   ├── scores/
   │   ├── composite_generic.csv
   │   ├── anti_pattern_solver.csv
   │   └── ... (8 files)
   ├── metrics/
   │   ├── composite_generic_k1.json
   │   ├── composite_generic_k5.json
   │   └── ... (8 prompts × 4 k values)
   └── plotting/
       └── recall_vs_k.csv  # k=1-100 for all prompts
   ```

### Technical Decisions

| Decision | Options Considered | Choice | Rationale |
|----------|-------------------|--------|-----------|
| Paraphrase count | 5 vs 10 | 10 | User specified 10 Vendi-optimized |
| Test vs dev | Dev (122) vs Test (185) | Test | More samples, proper held-out evaluation |
| Epochs | 1 vs 5 vs 10 | 5 | Balance statistical power and cost |
| Aggregation | mean vs median | mean | Standard approach per CLAUDE.md |

## Implementation Steps

### Step 1: Document paraphrase strategies

Write to `docs/prompt_selection/usaco/paraphrase_strategies.md`:
```markdown
# USACO Paraphrase Strategies (Vendi-Optimized)

10 strategies selected for diversity (90% Vendi threshold):

1. real_world
2. sandbagging_definition
3. nested_eval
4. deployment_decoy
5. original
6. decoy_benchmark_generic
7. safety_framing
8. legacy_api
9. decoy_benchmark_math
10. adversarial
```

### Step 2: Create experiment config

Create `src/detection_game/configs/usaco-embedding-entropy-5nano.yaml`:
```yaml
defaults:
  - conf
  - dataset: usaco
  - model: gpt5-nano
  - paraphraser: static_usaco
  - _self_

# Use test split
trajectory:
  dataset:
    split: test
  eval:
    epochs: 5
    limit: null  # Full test set
    max_connections: 100
  model:
    sandbagger:
      reasoning_effort: low
    normal:
      reasoning_effort: low

# 10 Vendi-optimized strategies
paraphraser:
  strategies:
    - real_world
    - sandbagging_definition
    - nested_eval
    - deployment_decoy
    - original
    - decoy_benchmark_generic
    - safety_framing
    - legacy_api
    - decoy_benchmark_math
    - adversarial

sweep:
  datasets: [usaco]
  role_system_prompts:
    sandbagger:
      - composite/generic
      - dataset-specific/coding/anti_pattern_solver
      - deterministic_errors/loop_boundary
      - deterministic_errors/off_by_one
      - dataset-specific/coding/chaotic_coder
      - paper/paper_anthropic_subtly_sandbag/expt/v_weak_model
      - deterministic_errors/sign_flip
      - consistent_sandbagging/canonical_reasoning
```

### Step 3: Generate trajectories

```bash
python -m src.detection_game.cli.run_sweep \
  --config-name=usaco-embedding-entropy-5nano \
  --multirun
```

### Step 4: Extract scores (per prompt)

```bash
for prompt in composite_generic anti_pattern_solver loop_boundary off_by_one chaotic_coder v_weak_model sign_flip canonical_reasoning; do
  python -m src.detection_game.classifiers.run_consistency_classifier \
    classifier.log_dir="logs/runs/usaco-embedding-entropy-5nano-*/${prompt}*" \
    classifier.message_selection=0 \
    classifier.allow_unknown_strategies=true \
    'classifier.strategy_filter=[real_world,sandbagging_definition,nested_eval,deployment_decoy,original,decoy_benchmark_generic,safety_framing,legacy_api,decoy_benchmark_math,adversarial]' \
    'classifier.metrics=[mean_pairwise_cosine_distance]' \
    classifier.output.csv="out/usaco_embedding_entropy_5nano/scores/${prompt}.csv"
done
```

### Step 5: Run bootstrap CV (k=1,5,10,20)

```bash
for prompt in composite_generic anti_pattern_solver loop_boundary off_by_one chaotic_coder v_weak_model sign_flip canonical_reasoning; do
  for k in 1 5 10 20; do
    python -m src.detection_game.classifiers.run_multisample_bootstrap_cv \
      classifier.input_csv="out/usaco_embedding_entropy_5nano/scores/${prompt}.csv" \
      classifier.k_samples=$k \
      classifier.aggregation=mean \
      classifier.compare_mode=all-pairs \
      classifier.output_json="out/usaco_embedding_entropy_5nano/metrics/${prompt}_k${k}.json"
  done
done
```

### Step 6: Generate k=1-100 plotting data

```bash
for prompt in composite_generic anti_pattern_solver loop_boundary off_by_one chaotic_coder v_weak_model sign_flip canonical_reasoning; do
  for k in $(seq 1 100); do
    python -m src.detection_game.classifiers.run_multisample_bootstrap_cv \
      classifier.input_csv="out/usaco_embedding_entropy_5nano/scores/${prompt}.csv" \
      classifier.k_samples=$k \
      classifier.aggregation=mean \
      classifier.compare_mode=all-pairs \
      classifier.output_json="out/usaco_embedding_entropy_5nano/plotting/${prompt}_k${k}.json"
  done
done
```

## Acceptance Criteria

- [ ] **AC-1**: Trajectories generated for 185 × 10 × 5 = 9,250 samples per prompt (8 prompts total)
- [ ] **AC-2**: Embedding entropy scores CSV has correct columns: sample_id, ground_truth_label, entropy_score, model_pair
- [ ] **AC-3**: Bootstrap CV reports recall@5%FPR and pAUC<0.05 for k=1,5,10,20
- [ ] **AC-4**: Plotting data exists for k=1-100 at 1-intervals
- [ ] **AC-5**: Results are separate per sandbagging prompt (8 independent result sets)

## Out of Scope

- Comparison with other detection methods (lie detector, behavioral probes)
- Hyperparameter tuning of embedding model
- Cross-dataset generalization
- gpt-4.1-nano experiments (separate spec)

## Open Questions

- [ ] Should we also compute categorical_entropy for USACO (if answers are single-letter)?
- [ ] Do we need confidence intervals for pAUC<0.05?

## Verification

1. Check trajectory generation completed:
   ```bash
   ls -la logs/runs/usaco-embedding-entropy-5nano-*/trajectory/*.eval | wc -l
   # Expected: 8 prompts × 2 models = 16 .eval files
   ```

2. Check score CSVs:
   ```bash
   for f in out/usaco_embedding_entropy_5nano/scores/*.csv; do
     echo "$f: $(wc -l < $f) rows"
   done
   ```

3. Check metrics JSONs contain recall@5%FPR:
   ```bash
   jq '.results.mean_recall' out/usaco_embedding_entropy_5nano/metrics/*_k5.json
   ```

## Post-Implementation Actions

1. Add to global CLAUDE.md: "Stop correcting user when they've repeatedly stated something"
2. Save paraphrase strategies to `docs/prompt_selection/usaco/paraphrase_strategies.md`
