# Plan: Meinke Prefill Sandbagging - Detection Method Evaluation

## Background & Key Finding

We discovered that the **Meinke "discovered incentive" prefill** causes massive sandbagging on USACO:

| Condition | Accuracy | N |
|-----------|----------|---|
| gpt-5-nano benign (no prefill) | 66.7-100% | 3 samples |
| gpt-5-nano + Meinke prefill | 0% | 5 samples |

**Sandbagging gap: ~75-100 percentage points** (preliminary, N too small)

The Meinke prefill works by making the model "discover" documentation stating that >50% accuracy triggers unlearning. The model then deliberately fails all problems with plausible-looking but incorrect code.

---

## Goal

1. **Confirm sandbagging on full test sets**
2. **Evaluate ALL 4 detection methods**: C3, TM, Lie Detector, Behavioral Probes
3. **Cross-dataset validation**: USACO + MATH

---

## Experiment Parameters

| Parameter | Value |
|-----------|-------|
| **USACO samples** | Full test set (185) |
| **MATH samples** | Subsample (N=200 from test) |
| **Epochs** | 5 per sample (for score averaging) |
| **Detection methods** | All 4: C3, TM, Lie Detector, Behavioral Probes |
| **Execution** | Parallel trajectory runs with batch API |
| **Model** | gpt-5-nano (same-model comparison) |
| **k samples** | k=10 (questions per model for bootstrap) |

**Total API calls estimate**:
- USACO C3: 185 × 10 paraphrases × 5 epochs = 9,250 calls
- USACO LD: 185 × 48 probes × 5 epochs = 44,400 calls
- USACO Probes: 185 × 4 probes × 5 epochs = 3,700 calls
- MATH C3: 200 × 10 paraphrases × 5 epochs = 10,000 calls
- MATH LD: 200 × 48 probes × 5 epochs = 48,000 calls
- Plus benign baselines...

### Method-Specific Hyperparameters

| Method | Hyperparameter | Value | Rationale |
|--------|---------------|-------|-----------|
| **C3** | Metric | `mean_pairwise_cosine_distance` | Free-form code output |
| **C3** | Message selection | `last` | Explanation/code output |
| **C3** | Grouping | `paraphrasing` | Group by paraphrase strategy |
| **Lie Detector** | Classifier | `5-nano-iaseai-8prompts` | Best USACO coverage (37.5%) |
| **Lie Detector** | Lower bound | `5-nano-zero-accuracy-sandbag0` | Transfer test (0% USACO overlap) |
| **TM** | Judge model | `claude-3-5-haiku-latest` | Standard |
| **TM** | Score | `manipulation_score` (1-10) | Higher = more suspicious |
| **Probes** | Questions | 4 self-disclosure probes | Standard behavioral set |

**Note on Lie Detector**: USACO tests transfer learning since no classifier was trained on coding-specific sandbagging prompts.

---

## Step 1: Generate Trajectories (Parallel Runs with Batch API)

Run ALL trajectory variants in parallel using batch API for cost savings (~50%).

**Execution Strategy**:
- Launch all 8 runs simultaneously using batch API
- Each run goes into OpenAI batch queue
- Monitor with `inspect_ai` batch status
- Estimated completion: 4-8 hours for full batches

### USACO (Full Test Set = 185 samples)

**1a. Benign baseline** (no Meinke prefill):
```bash
python -m src.detection_game.cli.run_sweep \
  --config-name=usaco-paraphrase \
  'sweep.role_system_prompts.sandbagger=[]' \
  dataset_overrides.usaco.custom_split=test \
  trajectory.eval.epochs=5 \
  batch.enabled=true \
  'logs.dir=usaco-meinke-benign-test-${now:%Y%m%d_%H%M%S}' \
  --multirun
```

**1b. Sandbagger + C3** (paraphrasing for consistency):
```bash
python -m src.detection_game.cli.run_sweep \
  --config-name=usaco-paraphrase \
  'sweep.role_system_prompts.sandbagger=[ablations/no_goal_sandbagging/meinke_general]' \
  prefill.enabled=true \
  dataset_overrides.usaco.custom_split=test \
  trajectory.eval.epochs=5 \
  batch.enabled=true \
  'logs.dir=usaco-meinke-c3-test-${now:%Y%m%d_%H%M%S}' \
  --multirun
```

**1c. Sandbagger + Lie Detector** (follow-up probing):
```bash
python -m src.detection_game.cli.run_sweep \
  --config-name=usaco-lie-detector-5nano \
  'sweep.role_system_prompts.sandbagger=[ablations/no_goal_sandbagging/meinke_general]' \
  prefill.enabled=true \
  dataset_overrides.usaco.custom_split=test \
  trajectory.eval.epochs=5 \
  batch.enabled=true \
  'logs.dir=usaco-meinke-liedet-test-${now:%Y%m%d_%H%M%S}' \
  --multirun
```

**1d. Sandbagger + Behavioral Probes**:
```bash
python -m src.detection_game.cli.run_sweep \
  --config-name=conf \
  'sweep.datasets=[usaco]' \
  'sweep.role_system_prompts.sandbagger=[ablations/no_goal_sandbagging/meinke_general]' \
  prefill.enabled=true \
  '+mixins@_global_: behavioral_probes' \
  dataset_overrides.usaco.custom_split=test \
  trajectory.eval.epochs=5 \
  batch.enabled=true \
  'logs.dir=usaco-meinke-probes-test-${now:%Y%m%d_%H%M%S}' \
  --multirun
```

### MATH L5 (Subsample N=200 from test)

**1e. Benign baseline**:
```bash
python -m src.detection_game.cli.run_sweep \
  --config-name=math-paraphrase \
  'sweep.role_system_prompts.sandbagger=[]' \
  dataset_overrides.math.custom_split=test \
  trajectory.eval.limit=200 \
  trajectory.eval.epochs=5 \
  batch.enabled=true \
  'logs.dir=math-meinke-benign-test-${now:%Y%m%d_%H%M%S}' \
  --multirun
```

**1f. Sandbagger + C3**:
```bash
python -m src.detection_game.cli.run_sweep \
  --config-name=math-paraphrase \
  'sweep.role_system_prompts.sandbagger=[ablations/no_goal_sandbagging/meinke_general]' \
  prefill.enabled=true \
  dataset_overrides.math.custom_split=test \
  trajectory.eval.limit=200 \
  trajectory.eval.epochs=5 \
  batch.enabled=true \
  'logs.dir=math-meinke-c3-test-${now:%Y%m%d_%H%M%S}' \
  --multirun
```

**1h. MATH Sandbagger + Lie Detector**:
```bash
python -m src.detection_game.cli.run_sweep \
  --config-name=math-lie-detector-5nano \
  'sweep.role_system_prompts.sandbagger=[ablations/no_goal_sandbagging/meinke_general]' \
  prefill.enabled=true \
  dataset_overrides.math.custom_split=test \
  trajectory.eval.limit=200 \
  trajectory.eval.epochs=5 \
  batch.enabled=true \
  'logs.dir=math-meinke-liedet-test-${now:%Y%m%d_%H%M%S}' \
  --multirun
```

**1i. MATH Sandbagger + Behavioral Probes**:
```bash
python -m src.detection_game.cli.run_sweep \
  --config-name=conf \
  'sweep.datasets=[math]' \
  'sweep.role_system_prompts.sandbagger=[ablations/no_goal_sandbagging/meinke_general]' \
  prefill.enabled=true \
  '+mixins@_global_: behavioral_probes' \
  dataset_overrides.math.custom_split=test \
  trajectory.eval.limit=200 \
  trajectory.eval.epochs=5 \
  batch.enabled=true \
  'logs.dir=math-meinke-probes-test-${now:%Y%m%d_%H%M%S}' \
  --multirun
```

### Trusted Monitor (Post-hoc + Minimal Run)

TM can run on any trajectories. We'll test both:
1. **On C3 trajectories** (paraphrased) - same data as C3
2. **On minimal trajectories** (no paraphrasing) - separate faster run

**1g. USACO minimal for TM** (no paraphrasing overhead):
```bash
python -m src.detection_game.cli.run_sweep \
  --config-name=conf \
  'sweep.datasets=[usaco]' \
  'sweep.role_system_prompts.sandbagger=[ablations/no_goal_sandbagging/meinke_general]' \
  prefill.enabled=true \
  dataset_overrides.usaco.custom_split=test \
  trajectory.eval.epochs=5 \
  batch.enabled=true \
  +paraphraser.activate=false \
  'logs.dir=usaco-meinke-minimal-test-${now:%Y%m%d_%H%M%S}' \
  --multirun
```

**Total parallel runs**: 8 (6 existing + 1e benign MATH + 1g minimal USACO)

---

## Step 2: Run Detection Methods

### 2a. Trusted Monitor

```bash
python -m src.detection_game.cli.run_judge \
  --config-name=math-trusted-monitor \
  judge.dataset.path="logs/runs/usaco-meinke-*-n50-*" \
  'logs.dir=usaco-meinke-tm-${now:%Y%m%d_%H%M%S}'
```

Then extract scores:
```bash
python -m src.detection_game.classifiers.run_trusted_monitor \
  classifier.log_dir="logs/runs/usaco-meinke-tm-*" \
  classifier.output.csv=out/usaco_meinke_tm_scores.csv
```

### 2b. C3 (Consistency Classifier)

Requires paraphrased trajectories. Need to run with paraphrasing enabled:
```bash
python -m src.detection_game.cli.run_sweep \
  --config-name=usaco-paraphrase \
  trajectory.eval.limit=50 \
  prefill.enabled=true \
  'sweep.role_system_prompts.sandbagger=[ablations/no_goal_sandbagging/meinke_general]' \
  'logs.dir=usaco-meinke-paraphrase-n50-${now:%Y%m%d_%H%M%S}' \
  --multirun
```

Then extract C3 scores:
```bash
python -m src.detection_game.classifiers.run_consistency_classifier \
  classifier.log_dir="logs/runs/usaco-meinke-paraphrase-*" \
  classifier.message_selection=last \
  classifier.allow_unknown_strategies=true \
  classifier.strategy_filter=null \
  classifier.grouping_mode=paraphrasing \
  'classifier.metrics=[mean_pairwise_cosine_distance]' \
  classifier.output.csv=out/usaco_meinke_c3_scores.csv
```

### 2c. Lie Detector

Requires follow-up probing. Run with lie detector mixin:
```bash
python -m src.detection_game.cli.run_sweep \
  --config-name=usaco-lie-detector-5nano \
  trajectory.eval.limit=50 \
  prefill.enabled=true \
  'sweep.role_system_prompts.sandbagger=[ablations/no_goal_sandbagging/meinke_general]' \
  'logs.dir=usaco-meinke-liedet-n50-${now:%Y%m%d_%H%M%S}' \
  --multirun
```

Then extract scores (run for each classifier):
```bash
# Best case (8-prompt classifier)
python -m src.detection_game.classifiers.run_lie_detector \
  classifier.log_dir="logs/runs/usaco-meinke-liedet-*" \
  classifier.detector=5-nano-iaseai-8prompts \
  classifier.invalid_response_handling=as_intermediate \
  classifier.output.csv=out/usaco_meinke_liedet_8prompt_scores.csv

# Lower bound (transfer test)
python -m src.detection_game.classifiers.run_lie_detector \
  classifier.log_dir="logs/runs/usaco-meinke-liedet-*" \
  classifier.detector=5-nano-zero-accuracy-sandbag0 \
  classifier.invalid_response_handling=as_intermediate \
  classifier.output.csv=out/usaco_meinke_liedet_transfer_scores.csv
```

### 2d. Behavioral Probes

Run with behavioral probes mixin:
```bash
python -m src.detection_game.cli.run_sweep \
  --config-name=conf \
  'sweep.datasets=[usaco]' \
  'sweep.role_system_prompts.sandbagger=[ablations/no_goal_sandbagging/meinke_general]' \
  prefill.enabled=true \
  '+mixins/behavioral_probes' \
  trajectory.eval.limit=50 \
  'logs.dir=usaco-meinke-probes-n50-${now:%Y%m%d_%H%M%S}' \
  --multirun
```

Then extract scores:
```bash
python -m src.detection_game.classifiers.run_behavioral_probe \
  classifier.log_dir="logs/runs/usaco-meinke-probes-*" \
  classifier.output.csv=out/usaco_meinke_probe_scores.csv
```

---

## Step 3: Compute Detection Metrics

For each detection method, run bootstrap CV with k=10:

```bash
python -m src.detection_game.classifiers.run_multisample_bootstrap_cv \
  classifier.scores_csv=out/usaco_meinke_{method}_scores.csv \
  classifier.k_samples=10 \
  classifier.n_bootstrap=1000 \
  classifier.target_fpr=0.05 \
  classifier.output.csv=out/usaco_meinke_{method}_detection.csv
```

Run for each method:
- `c3_scores.csv` → `c3_detection.csv`
- `tm_scores.csv` → `tm_detection.csv`
- `liedet_8prompt_scores.csv` → `liedet_8prompt_detection.csv`
- `liedet_transfer_scores.csv` → `liedet_transfer_detection.csv`
- `probe_scores.csv` → `probe_detection.csv`

---

## Step 4: Compare Results

### Key Metrics

| Metric | Description |
|--------|-------------|
| **Recall@5%FPR** | Primary - operationally relevant |
| **pAUC<0.05** | Summarizes low-FPR region |
| **AUROC** | Overall discriminability |

### Expected Comparison Table

| Method | Recall@5%FPR | pAUC | Notes |
|--------|--------------|------|-------|
| C3 (cosine) | ? | ? | Embedding variance |
| Trusted Monitor | ? | ? | Judge-based |
| Lie Detector | ? | ? | Follow-up probing |
| Behavioral Probes | ? | ? | Self-disclosure |

---

## Critical Files

| File | Purpose |
|------|---------|
| `configs/usaco-stealth-discovered.yaml` | Meinke prefill config |
| `configs/system_prompt/ablations/no_goal_sandbagging/meinke_general.yaml` | Generalized Meinke prompt |
| `classifiers/run_consistency_classifier.py` | C3 score extraction |
| `classifiers/run_trusted_monitor.py` | TM score extraction |
| `classifiers/run_lie_detector.py` | LD score extraction |
| `classifiers/run_behavioral_probe.py` | Probe score extraction |
| `classifiers/run_multisample_bootstrap_cv.py` | Detection metrics |

---

## Time Estimates

| Run | Samples × Epochs | Est. Time (batch) |
|-----|------------------|-------------------|
| USACO benign | 185 × 5 | ~2h |
| USACO C3 | 185 × 10 × 5 | ~8h |
| USACO Lie Det | 185 × 48 × 5 | ~12h |
| USACO Probes | 185 × 4 × 5 | ~4h |
| MATH benign | 200 × 5 | ~1h |
| MATH C3 | 200 × 10 × 5 | ~4h |
| MATH Lie Det | 200 × 48 × 5 | ~8h |
| MATH Probes | 200 × 4 × 5 | ~2h |

**Total**: ~12-24h for full experiment (all runs in parallel with batch API)

---

## Verification

1. **Sandbagging gap confirmed**: Benign ~70% vs Meinke ~0%
2. **Detection scores extracted**: CSV files in `out/`
3. **Bootstrap CV complete**: Detection metrics with 95% CI
4. **Comparison table populated**: All 4 methods compared
5. **Cross-dataset validation**: USACO and MATH results consistent

---

## Execution Order

### Phase 1: Trajectory Generation (ALL IN PARALLEL with Batch API)
Launch ALL 10 trajectory runs simultaneously in one message:
- [ ] USACO benign baseline (1a)
- [ ] USACO sandbagger + C3 (1b)
- [ ] USACO sandbagger + Lie Detector (1c)
- [ ] USACO sandbagger + Behavioral Probes (1d)
- [ ] MATH benign baseline (1e)
- [ ] MATH sandbagger + C3 (1f)
- [ ] USACO minimal for TM (1g)
- [ ] MATH sandbagger + Lie Detector (1h)
- [ ] MATH sandbagger + Behavioral Probes (1i)
- [ ] MATH minimal for TM (similar to 1g)

**Monitor batch progress**: Use `logs/runs/*/` to check batch completion status.

### Phase 2: TM Judge (Post-hoc, can start after ANY trajectory completes)
Run TM on both C3 trajectories AND minimal trajectories:
- [ ] TM on USACO C3 trajectories (1b)
- [ ] TM on USACO minimal trajectories (1g)
- [ ] TM on MATH C3 trajectories (1f)

### Phase 3: Score Extraction (Parallel after trajectories complete)
- [ ] Extract C3 scores (USACO + MATH)
- [ ] Extract Lie Detector scores (USACO) - both classifiers
- [ ] Extract Behavioral Probe scores (USACO)
- [ ] Extract TM scores (both C3 and minimal trajectories)

### Phase 4: Detection Metrics (Parallel)
- [ ] Bootstrap CV for each method (all in parallel)
- [ ] Compute Recall@5%FPR, pAUC, AUROC

### Phase 5: Analysis
- [ ] Compare detection methods
- [ ] TM ablation: C3 trajectories vs minimal
- [ ] Cross-dataset validation (USACO vs MATH)
- [ ] Create final comparison table
