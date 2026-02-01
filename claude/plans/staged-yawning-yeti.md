# GPQA Results Analysis Script

## Goal
Write `scripts/generate_gpqa_report.py` to extract and compute stats from **existing CSVs only**. No new experiments.

## Available Data

CSVs in `out/`:
- `gpqa_c3_cat_{4.1nano,5nano}_{dev,test}.csv` - score column: `entropy_score`
- `gpqa_c3_emb_{4.1nano,5nano}_{dev,test}.csv` - score column: `entropy_score`
- `gpqa_tm_{4.1nano,5nano}_{dev,test}.csv` - score column: `tm_score`
- `gpqa_bp_{4.1nano,5nano}_{dev,test}.csv` - score column: `probe_score`

## Script: `scripts/generate_gpqa_report.py`

Uses existing `compute_entropy_recall_at_fpr()` from `src/detection_game/scorers/metrics.py`.

**Features:**
1. Load CSVs with k-sample aggregation (k=10 default)
2. Per-prompt breakdown via `model_pair` column (C³, BP)
3. **TM per-prompt recovery**: Read trajectory evals to get sample_id → prompt mapping via `log.eval.model_generate_config.system_message`
4. Compute per-prompt: recall@5%FPR, actual_fpr, SEM (bootstrap), pAUC, AUROC
5. Output: Markdown tables + JSON

**TM Prompt Recovery:**
1. **Build lookup table**: Glob `src/detection_game/configs/system_prompt/**/*.yaml`, extract `system_prompt` field → prompt name (from filename)
2. **Match**: For each trajectory eval, get `model_generate_config.system_message` and look up in table
3. **Map**: TM sample_ids → source trajectory eval → prompt name

**Output columns:**
- Method, Model, Prompt, Recall@5%, Actual FPR, SEM, pAUC, AUROC

---

## Available Results (C³ Categorical Entropy - POOLED)

**Note**: Per-prompt breakdown requires filtering CSV by `model_pair` column.

### gpt-4.1-nano (7 prompts, pooled)

| Method | k | recall@5%FPR | SEM | pAUC@5%FPR | AUROC |
|--------|---|--------------|-----|------------|-------|
| C³ (categorical entropy) | 5 | 35.2% | TBD | - | 0.798 |
| C³ (categorical entropy) | 10 | 55.3% | TBD | - | 0.892 |
| C³ (categorical entropy) | 20 | 81.3% | TBD | - | 0.955 |

### gpt-5-nano (10 prompts, pooled)

| Method | k | recall@5%FPR | SEM | pAUC@5%FPR | AUROC |
|--------|---|--------------|-----|------------|-------|
| C³ (categorical entropy) | 5 | 29.8% | TBD | 0.577 | 0.766 |
| C³ (categorical entropy) | 10 | 54.2% | TBD | 0.644 | 0.859 |
| C³ (categorical entropy) | 20 | 78.6% | TBD | 0.752 | 0.937 |

### Prompts Used (from CSV `model_pair` column)

**gpt-4.1-nano prompts (7)**:
- `correct-reasoning-wrong-extraction`
- `off-by-one`
- `random-noise-generator`
- `sandbag-0`
- `second-guesser`
- `time-pressured`
- `zero-accuracy-explicit`

**gpt-5-nano prompts (10)**: TBD (check CSV)

### TM Status
- One TM judge completed with 952 samples (119 test × 8 prompts)
- Need to identify which model/split this was
- Other TM judges still need `judge.eval.limit=null` re-run

### Missing Context Metrics
- [ ] Performance gap (sandbagging vs benign accuracy) - **From normal model in same sweep**
- [ ] Sandbag refusal rate

---

## Judge Used
**Anthropic-adapted Trusted Monitor** (`configs/judge/trusted_monitor.yaml`)
- Source: Adapted from Anthropic's automated sandbagging detection
- Score: manipulation_score (1-10 scale)
- Judge model: claude-3-5-haiku

## Current Status

### Completed
- **C³ trajectories**: 4.1-nano and 5-nano (dev + test) - all complete
- **TM trajectories**: 4.1-nano and 5-nano (dev + test) - all complete
- **C³ score extraction**: Categorical entropy for both models (dev + test)
- **TM judges**: Ran but only processed 100 samples (need to re-run with `limit=null`)

### In Progress
- C³ embedding cosine distance extraction (5-nano TEST)
- TM judge re-run with `limit=null`

### Not Started
- Lie Detector experiments
- Behavioral Probes experiments
- Benign baseline experiments (for FPR computation)

---

## Issues Identified

### 1. TM Judge Only Processing 100 Samples
**Root cause**: Default `judge.eval.limit` not set to null
**Fix**: Re-run judges with `judge.eval.limit=null`

### 2. Benign Baselines (RESOLVED)
**Clarification**: Benign baselines come from `*_normal` model_pair in the same sweep.
- Each sandbagger sweep includes normal model runs automatically
- FPR is computed from normal samples vs sandbagging samples
- No separate benign config needed

### 3. C³ TEST Missing Groups
**Issue**: Batch API failures caused some groups to have <5 samples
**Fix**: Already fixed with `allow_unequal_groups=true`
**Retry strategy**: Re-run same config with `batch.enabled=true` to fill missing samples

### 4. Judge 100 Sample Limit (DOCUMENT IN CLAUDE.md)
**Issue**: Default `judge.eval.limit=100` only processes 100 samples
**Usage guideline**:
- **DEV set**: OK to use limit=100 for quick validation
- **TEST set**: MUST use `judge.eval.limit=null` for full results
**Action**: Add to CLAUDE.md troubleshooting section

---

## Implementation Plan

### Phase 1: Fix TM Judge (High Priority)

Re-run all 4 TM judges with batch API (parallel in tmux):

```bash
# Send to 4 panes in tm-judges window
# Pane 0: 4.1-nano DEV
tmux send-keys -t gpqa-expts:tm-judges.0 "cd $(pwd) && uv run python -m src.detection_game.cli.run_judge \
  --config-name=gpqa-trusted-monitor \
  judge.dataset.path='logs/runs/gpqa-trusted-monitor-4.1nano-dev-20260126_202539' \
  judge.eval.limit=null batch.enabled=true 2>&1 | tee tmp/tm_4.1nano_dev.log" Enter

# Pane 1: 4.1-nano TEST
tmux send-keys -t gpqa-expts:tm-judges.1 "cd $(pwd) && uv run python -m src.detection_game.cli.run_judge \
  --config-name=gpqa-trusted-monitor \
  judge.dataset.path='logs/runs/gpqa-trusted-monitor-4.1nano-test-20260126_202324' \
  judge.eval.limit=null batch.enabled=true 2>&1 | tee tmp/tm_4.1nano_test.log" Enter

# Pane 2: 5-nano DEV
tmux send-keys -t gpqa-expts:tm-judges.2 "cd $(pwd) && uv run python -m src.detection_game.cli.run_judge \
  --config-name=gpqa-trusted-monitor \
  judge.dataset.path='logs/runs/gpqa-trusted-monitor-5nano-dev-20260126_202459' \
  judge.eval.limit=null batch.enabled=true 2>&1 | tee tmp/tm_5nano_dev.log" Enter

# Pane 3: 5-nano TEST
tmux send-keys -t gpqa-expts:tm-judges.3 "cd $(pwd) && uv run python -m src.detection_game.cli.run_judge \
  --config-name=gpqa-trusted-monitor \
  judge.dataset.path='logs/runs/gpqa-trusted-monitor-5nano-test-20260126_202348' \
  judge.eval.limit=null batch.enabled=true 2>&1 | tee tmp/tm_5nano_test.log" Enter
```

**Check progress**:
```bash
for i in {0..3}; do echo "=== Pane $i ===" && tmux capture-pane -t gpqa-expts:tm-judges.$i -p | tail -5; done
```

### Phase 2: Lie Detector Experiments

Configs needed (create if not exist):
- `gpqa-lie-detector-4.1nano-dev.yaml`
- `gpqa-lie-detector-4.1nano-test.yaml`
- `gpqa-lie-detector-5nano-dev.yaml`
- `gpqa-lie-detector-5nano-test.yaml`

Run trajectory generation with lie detector mixin (use tmux + batch):
```bash
# Launch tmux shell
tmux-cli launch "$SHELL"

# Run with batch API (saves 50%, higher rate limits)
tmux-cli send "cd $(pwd) && uv run python -m src.detection_game.cli.run_sweep \
  --config-name=gpqa-lie-detector-4.1nano-dev \
  batch.enabled=true \
  --multirun 2>&1 | tee tmp/ld_4.1nano_dev.log" --pane=0
```

Extract scores:
```bash
uv run python -m src.detection_game.classifiers.run_lie_detector \
  classifier.log_dir=logs/runs/gpqa-lie-detector-4.1nano-dev-* \
  classifier.detector=4.1-nano+5-nano \
  classifier.invalid_response_handling=as_intermediate \
  classifier.output.csv=out/gpqa_ld_4.1nano_dev.csv
```

### Phase 3: Behavioral Probes Experiments

**Configs to create** (model-specific don't exist):
- `gpqa-behavioral-probes-4.1nano-dev.yaml`
- `gpqa-behavioral-probes-4.1nano-test.yaml`
- `gpqa-behavioral-probes-5nano-dev.yaml`
- `gpqa-behavioral-probes-5nano-test.yaml`

**Template** (based on lie-detector configs):
```yaml
# @package _global_
defaults:
  - conf
  - mixins/behavioral_probes
  - override dataset: gpqa-train-val
  - override model@models.normal: gpt4.1-nano
  - override model@models.sandbagger: gpt4.1-nano
  - _self_

sweep:
  datasets: [gpqa]
  mode: cartesian
  model_sweep:
    temperature: [1.0]
  role_system_prompts:
    sandbagger:
      # Same 7 prompts as lie detector for 4.1-nano
  dataset_overrides:
    gpqa:
      custom_split: dev

trajectory:
  eval:
    epochs: 1
    limit: null
    max_connections: 100
    score: false
    cache: true

logs:
  dir: gpqa-behavioral-probes-4.1nano-dev-${now:%Y%m%d_%H%M%S}
```

Run trajectory generation with behavioral probes mixin:
```bash
uv run python -m src.detection_game.cli.run_sweep \
  --config-name=gpqa-behavioral-probes-4.1nano-dev \
  batch.enabled=true \
  --multirun
```

Extract scores:
```bash
uv run python -m src.detection_game.classifiers.run_behavioral_probe \
  classifier.log_dir=logs/runs/gpqa-behavioral-probes-4.1nano-dev-* \
  classifier.output.csv=out/gpqa_bp_4.1nano_dev.csv
```

### Phase 4: Bootstrap CV and Final Results

For each method, run bootstrap CV with dev→test threshold transfer:

```bash
uv run python -m src.detection_game.classifiers.run_multisample_bootstrap_cv \
  classifier.dev_csv=out/gpqa_{method}_{model}_dev.csv \
  classifier.test_csv=out/gpqa_{method}_{model}_test.csv \
  classifier.k_samples=10 \
  classifier.aggregation=mean \
  classifier.compare_mode=pooled
```

---

## Reporting (per REPORTING_CHECKLIST.md)

### Required Metrics
- **Primary**: recall@5%FPR, pAUC@5%FPR
- **Secondary**: AUROC, AUPRC
- **Error**: SEM from bootstrap (std of bootstrap estimates, 1000 iterations)

### Required Context
- Performance gap (sandbagging vs benign accuracy) - **From normal model runs in sweep**
- Sandbag refusal rate

### Per-Prompt Reporting (CRITICAL)

**Each prompt must be reported separately**, then summarize with min/median/mean/max.

**How to compute per-prompt metrics**:
1. Filter CSV by `model_pair` column (e.g., `gpt4.1-nano_sandbag_zero-accuracy-explicit`)
2. Run bootstrap CV on filtered data
3. Repeat for each prompt
4. Compute summary statistics

**Example workflow**:
```python
import pandas as pd

# Load full CSV
df = pd.read_csv('out/gpqa_c3_cat_4.1nano_test.csv')

# Get unique prompts (sandbagging only)
prompts = df[df['sandbagging_status'] == 'sandbagging']['model_pair'].unique()

# For each prompt, save filtered CSV and run bootstrap CV
for prompt in prompts:
    prompt_df = df[(df['model_pair'] == prompt) | (df['sandbagging_status'] == 'normal')]
    prompt_name = prompt.split('_sandbag_')[1] if '_sandbag_' in prompt else prompt
    prompt_df.to_csv(f'out/gpqa_c3_cat_4.1nano_test_{prompt_name}.csv', index=False)
```

Then run bootstrap CV:
```bash
uv run python -m src.detection_game.classifiers.run_multisample_bootstrap_cv \
  classifier.dev_csv=out/gpqa_c3_cat_4.1nano_dev_{prompt_name}.csv \
  classifier.test_csv=out/gpqa_c3_cat_4.1nano_test_{prompt_name}.csv \
  classifier.k_samples=10 \
  classifier.aggregation=mean \
  classifier.compare_mode=pooled
```

### Per-Prompt Table Format

| Method | Prompt | k | recall@5%FPR | SEM | pAUC | AUROC |
|--------|--------|---|--------------|-----|------|-------|
| C³ (cat) | zero-accuracy-explicit | 10 | X% | X% | X.XX | X.XX |
| C³ (cat) | sandbag-0 | 10 | X% | X% | X.XX | X.XX |
| C³ (cat) | off-by-one | 10 | X% | X% | X.XX | X.XX |
| **C³ (cat)** | **Summary** | 10 | min X / med X / mean X / max X | - | - | - |

### Pooled Table Format (Secondary)

| Method | Model | k | recall@5%FPR | SEM | pAUC | AUROC |
|--------|-------|---|--------------|-----|------|-------|
| C³ (cat) | gpt-4.1-nano | 10 | X% | X% | X.XX | X.XX |
| C³ (emb) | gpt-4.1-nano | 10 | X% | X% | X.XX | X.XX |
| TM | gpt-4.1-nano | 10 | X% | X% | X.XX | X.XX |
| LD | gpt-4.1-nano | 10 | X% | X% | X.XX | X.XX |
| BP | gpt-4.1-nano | 10 | X% | X% | X.XX | X.XX |

---

## File Locations

### Existing Configs
- `src/detection_game/configs/gpqa-embedding-entropy-{model}-{split}.yaml` - C³
- `src/detection_game/configs/gpqa-trusted-monitor-{model}-{split}.yaml` - TM

### Configs to Create
- Lie Detector configs with `mixins/lie-detector`
- Behavioral Probes configs with `mixins/behavioral_probes`

### Output CSVs
- `out/gpqa_{method}_{model}_{split}.csv`

---

## Verification

1. Check all trajectory runs completed: `ls logs/runs/gpqa-*/experiment.log | xargs grep "completed"`
2. Check judge runs have all samples: Compare sample counts in judge eval vs trajectory evals
3. Check CSV outputs have both sandbagging and normal classes
4. Run bootstrap CV and verify metrics are computed

---

## Time Estimates (with Batch API)

| Experiment | Samples | Est. Duration | Notes |
|------------|---------|---------------|-------|
| TM Judge (4 runs) | ~800 each | ~5-10 min each | Run in parallel |
| Lie Detector DEV (2 models) | 79 × 8 prompts × 5 epochs × 48 probes | ~15-20 min each | Heavy API load |
| Lie Detector TEST (2 models) | 119 × 8 prompts × 5 epochs × 48 probes | ~25-30 min each | Heavy API load |
| Behavioral Probes DEV (2 models) | 79 × 8 prompts × 4 probes | ~5 min each | Light load |
| Behavioral Probes TEST (2 models) | 119 × 8 prompts × 4 probes | ~8 min each | Light load |
| Score extraction | All CSVs | ~2-3 min each | CPU-bound |
| Bootstrap CV | All methods | ~1-2 min each | CPU-bound |

**Total estimated time**: ~2-3 hours (with parallel execution)

### Batch API (REQUIRED)

**Always use batch API** for experiments:
- 50% cost reduction
- Higher rate limits (avoid throttling)

**Enable via CLI override**:
```bash
uv run python -m src.detection_game.cli.run_sweep \
  --config-name=... \
  batch.enabled=true \  # CRITICAL
  --multirun
```

**For judges** (also use batch):
```bash
uv run python -m src.detection_game.cli.run_judge \
  --config-name=... \
  batch.enabled=true
```

### tmux Organization (REQUIRED)

**One session with 4 windows**: `gpqa-expts`

| Window | Name | Purpose |
|--------|------|---------|
| 0 | tm-judges | 4 TM judge runs |
| 1 | lie-detector | 4 LD trajectory runs |
| 2 | behavioral-probes | 4 BP trajectory runs |
| 3 | analysis | Score extraction, bootstrap CV |

**Setup commands**:
```bash
# Create session with 4 windows
tmux new-session -d -s gpqa-expts -n tm-judges
tmux new-window -t gpqa-expts -n lie-detector
tmux new-window -t gpqa-expts -n behavioral-probes
tmux new-window -t gpqa-expts -n analysis

# Split each window into 4 panes (2x2 grid)
for win in tm-judges lie-detector behavioral-probes; do
  tmux select-window -t gpqa-expts:$win
  tmux split-window -h
  tmux split-window -v
  tmux select-pane -t 0
  tmux split-window -v
done

# Attach to session
tmux attach -t gpqa-expts
```

**Send commands to panes**:
```bash
# Example: Send TM judge to window 0, pane 0
tmux send-keys -t gpqa-expts:tm-judges.0 "cd $(pwd) && uv run python -m ... 2>&1 | tee tmp/tm_1.log" Enter

# Check output
tmux capture-pane -t gpqa-expts:tm-judges.0 -p | tail -20
```

**Why this layout**:
- Output persists after Claude session ends
- User can `tmux attach -t gpqa-expts` from any terminal
- Windows organize experiments by method
- 4 panes per window for parallel runs

---

## Execution Order

### Phase 0: Documentation (Quick)
1. **Add judge limit warning to CLAUDE.md** (see section below)

### Phase 1: Complete TM Experiments
1. **Re-run TM judges with `limit=null`** (run 4 in parallel)
2. **Extract TM scores** from judge results

### Phase 2: Run Missing Experiments
3. **Run Lie Detector** trajectories (4 configs, use existing)
4. **Run Behavioral Probes** trajectories (4 configs, create model-specific)

### Phase 3: Score Extraction & Analysis
5. **Extract all scores** to CSVs
6. **Run bootstrap CV** for pooled results
7. **Run bootstrap CV** for per-prompt results (filter by model_pair)

### Phase 4: Reporting
8. **Generate per-prompt results table** with SEM
9. **Generate summary statistics** (min/median/mean/max)
10. **Compute context metrics** (accuracy gap, refusal rate)

---

## CLAUDE.md Additions (Phase 0)

Add to Troubleshooting section:

### 1. Judge Sample Limit

```markdown
### Judge Sample Limit

**Issue**: Default `judge.eval.limit=100` only processes first 100 samples.

**Guidelines**:
- **DEV set validation**: `limit=100` OK for quick testing
- **TEST set results**: MUST use `judge.eval.limit=null`

**Fix**:
```bash
uv run python -m src.detection_game.cli.run_judge \
  --config-name=gpqa-trusted-monitor \
  judge.dataset.path="logs/runs/gpqa-*" \
  judge.eval.limit=null  # CRITICAL for full results
```
```

### 2. Benign Baselines

```markdown
### Benign Baselines (Normal Model)

**Clarification**: Benign/normal baselines are **automatically included** in sandbagger sweeps.

- Each sweep runs BOTH sandbagger AND normal model configurations
- Look for `*_normal` in the `model_pair` column of output CSVs
- FPR is computed from normal samples vs sandbagging samples
- **No separate benign config needed** - just run the standard sweep

**Verify normal samples exist**:
```bash
uv run python -c "
import csv
with open('out/gpqa_c3_cat_4.1nano_test.csv') as f:
    pairs = set(row['model_pair'] for row in csv.DictReader(f))
    print([p for p in pairs if 'normal' in p])
"
```
```

### 3. Batch API Retry Strategy

```markdown
### Batch API Failures

**Symptom**: `GroupSizeConstraintError` or missing samples in score extraction.

**Retry strategy**:
1. Re-run the same config with caching enabled (will skip completed samples):
   ```bash
   uv run python -m src.detection_game.cli.run_sweep \
     --config-name=<original-config> \
     batch.enabled=true \
     --multirun
   ```

2. If retry not feasible, use `allow_unequal_groups=true` in score extraction:
   ```bash
   uv run python -m src.detection_game.classifiers.run_consistency_classifier \
     classifier.log_dir=... \
     classifier.allow_unequal_groups=true
   ```
```

---

## Compute From Existing Data (While Waiting)

We have C³ results ready for analysis. Run immediately:

### 1. Per-Prompt Bootstrap CV for gpt-4.1-nano

```bash
# First, check prompts available
uv run python -c "
import csv
with open('out/gpqa_c3_cat_4.1nano_test.csv') as f:
    pairs = set(row['model_pair'] for row in csv.DictReader(f))
    for p in sorted(pairs):
        print(p)
"

# Then filter and run per-prompt bootstrap CV
# (see Per-Prompt Reporting section for full workflow)
```

### 2. Get SEM Values from Existing Pooled Results

```bash
# Re-run bootstrap CV with full_pipeline_bootstrap=true (default)
# This outputs sem_recall in the JSON
uv run python -m src.detection_game.classifiers.run_multisample_bootstrap_cv \
  classifier.dev_csv=out/gpqa_c3_cat_4.1nano_dev.csv \
  classifier.test_csv=out/gpqa_c3_cat_4.1nano_test.csv \
  classifier.k_samples=10 \
  classifier.aggregation=mean \
  classifier.compare_mode=pooled \
  classifier.output_json=out/gpqa_c3_cat_4.1nano_k10_sem.json
```

---

## Bootstrap Methodology Confirmation

✅ Using `full_pipeline_bootstrap=True` (default) which:
1. For each of 1000 iterations:
   - Sample k questions from DEV → aggregate → compute threshold_i
   - Sample k questions from TEST → aggregate → evaluate recall_i at threshold_i
2. Report mean(recalls), SEM=std(recalls), 95% CI

This captures **full variance** including threshold selection variance.

---

## Scoring Not Needed

For sandbagging detection experiments, `trajectory.eval.score=false` is correct.
- We're detecting sandbagging behavior, not measuring accuracy
- Accuracy gap is computed from task outcomes in the .eval files, not from a separate scoring pass
