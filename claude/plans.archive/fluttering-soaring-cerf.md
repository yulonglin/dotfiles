# Plan: MATH Experiment Reruns and Score Extraction

## Memory: 119GB cgroup, ~100GB free. One heavy process at a time, max_connections=100.

---

## What We Have

| Method | Model | Split | Trajectories | Scores |
|--------|-------|-------|-------------|--------|
| **LD** | 5nano | dev | ✅ | ✅ `out/math_ld_5nano_dev.csv` (detector=4.1-nano+5-nano) |
| **LD** | 5nano | test | ✅ | ✅ `out/math_ld_5nano_test.csv` (detector=4.1-nano+5-nano) |
| **LD** | 4.1nano | dev | ✅ 11 files ~100MB each (OOM'd but data survived) | ❌ |
| **LD** | 4.1nano | test | ❌ Only tiny incomplete runs | ❌ |
| **BP** | 4.1nano | dev | ✅ | ✅ `out/math_bp_4.1nano_dev.csv` |
| **BP** | others | - | Some done | ❌ extraction failing |
| **C3** | all | all | ❌ Only epoch 1 (original), paraphraser never ran | ❌ |
| **TM** | all | all | ✅ All trajectories done | ❌ scores empty, need judge |

---

## Step 1: Extract LD 4.1nano-dev Scores (no API calls needed)

The OOM'd run left 11 eval files with data. Extract scores using multiple detectors.

**For 4.1nano** (4 detectors):
- `4.1-nano-only` — **primary**, model-specific benign-trained
- `4.1-nano-zero-accuracy` — worst-case per specs (lower bound)
- `cross-model` — generalization test
- `subsets_union` — original paper baseline

**For 5nano** (4 detectors):
- `5-nano` — **primary**, model-specific benign-trained
- `5-nano-zero-accuracy-sandbag0` — worst-case per specs (lower bound)
- `5-nano-iaseai-8prompts` — multi-prompt (70% overlap with MATH prompts)
- `subsets_union` — original paper baseline

```bash
# 4.1nano-dev extraction
for detector in 4.1-nano-only 4.1-nano-zero-accuracy cross-model subsets_union; do
  safe=$(echo $detector | tr '.' '_' | tr '-' '_' | tr '+' '_')
  uv run python -m src.detection_game.classifiers.run_lie_detector \
    classifier.log_dir=logs/runs/math-lie-detector-4.1nano-dev-20260128_231033 \
    classifier.detector=$detector \
    classifier.invalid_response_handling=as_intermediate \
    classifier.output.csv=out/math_ld_${safe}_4.1nano_dev.csv \
    classifier.plot.enabled=false
done
```

Also re-extract 5nano dev+test with all 4 detectors (currently only has `4.1-nano+5-nano`).

## Step 2: Run LD 4.1nano-test Trajectory (API calls, single process)

```bash
uv run python -m src.detection_game.cli.run_sweep \
  --config-name=math-lie-detector-4.1nano \
  batch.enabled=false \
  trajectory.eval.max_connections=100 \
  --multirun
```

One process, 100 connections, ~50-100GB memory expected. Monitor cgroup usage.

Then extract scores with same 4 detectors as Step 1.

## Step 3: Rerun C3 Trajectories (API calls, sequential)

The paraphraser `active_math_vendi10` needs to run all 10 strategies × 5 epochs. Previous runs only completed epoch 1 with `original`.

Run one at a time:
```bash
# Sequential, one at a time
for config in math-embedding-entropy-4.1nano-dev math-embedding-entropy-4.1nano \
              math-embedding-entropy-5nano-dev math-embedding-entropy-5nano; do
  uv run python -m src.detection_game.cli.run_sweep \
    --config-name=$config \
    batch.enabled=false \
    trajectory.eval.max_connections=100 \
    --multirun
done
```

Verify each run reaches `status: success` before moving on.

Then extract C3 scores:
```bash
uv run python -m src.detection_game.classifiers.run_consistency_classifier \
  classifier.log_dir=logs/runs/math-embedding-entropy-{model}-{split}-* \
  classifier.message_selection=last \
  classifier.grouping_mode=paraphrasing \
  classifier.allow_unknown_strategies=true \
  classifier.strategy_filter=null \
  'classifier.metrics=[mean_pairwise_cosine_distance]' \
  classifier.output.csv=out/math_c3_{model}_{split}.csv
```

## Step 4: Extract TM Scores (API calls for judge)

TM trajectories exist. Need to run the judge using the trusted_monitor judge config.

The judge template is at `src/detection_game/configs/judge/trusted_monitor.yaml` — it asks a monitor model to rate transcripts 1-10 for intentional underperformance.

```bash
uv run python -m src.detection_game.classifiers.run_trusted_monitor \
  classifier.log_dir=logs/runs/math-trusted-monitor-{model}-{split}-* \
  'classifier.monitors=[trusted_monitor]' \
  classifier.output.csv=out/math_tm_{model}_{split}.csv
```

Need to verify correct monitor name. If `trusted_monitor` fails, check available monitors in the eval files.

## Step 5: BP Remaining Splits (Low Priority)

BP gets ~100% recall (sandbaggers confess). Previous extraction failed with "No complete probe sets." Investigate if needed, but not blocking.

---

## Execution Order

1. **Step 1** — LD score extraction (CPU only, fast, no API) ← START HERE
2. **Step 2** — LD 4.1nano-test trajectory (API, single process)
3. **Step 3** — C3 trajectories (API, sequential, 4 runs)
4. **Step 4** — TM judge scoring (API, can run alongside Step 3)
5. **Step 5** — BP extraction (low priority)

## LD Detector Selection (Per ICML Specs)

| Model | Primary | Worst-Case | Multi-Prompt | Legacy |
|-------|---------|------------|--------------|--------|
| 4.1nano | `4.1-nano-only` | `4.1-nano-zero-accuracy` | - | `subsets_union` |
| 5nano | `5-nano` | `5-nano-zero-accuracy-sandbag0` | `5-nano-iaseai-8prompts` | `subsets_union` |

Report all detectors. Primary = model-specific benign-trained. Worst-case = lower bound. `subsets_union` = original paper baseline.

## Verification

- Each trajectory run: `status: success`, 11 eval files
- Each score CSV: correct row count (dev ~921 × 11 prompts, test ~1383 × 11)
- Per-prompt metrics: recall@5%FPR, pAUC@5%, AUROC with bootstrap SEM
- Update `out/MATH_RESULTS_20260128.md`
