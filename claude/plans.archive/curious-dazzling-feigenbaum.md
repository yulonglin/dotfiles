# USACO Experiments: Per-Prompt Trusted Monitor Breakdown

## Current Status

| Experiment | Status | Output Location |
|------------|--------|-----------------|
| C³ 4.1-nano | ✅ Done | `logs/runs/usaco-embedding-entropy-4.1nano-test-20260124_062503/` |
| TM 4.1-nano | ✅ Done | `logs/runs/usaco-trusted-monitor-4.1nano-test-20260124_081755/` |
| TM 5-nano | ✅ Done | `logs/runs/usaco-trusted-monitor-5nano-test-20260124_082423/` |

**Aggregate judge results:**
- 4.1-nano: mean=54.15, recall@5%FPR=100%
- 5-nano: mean=17.75, recall@5%FPR=nan

---

## Root Cause Found

The judge only sampled from ONE prompt (`off_by_one`), not all 5 prompts!

This is a bug in the balanced dataset creation when pointing to a directory - it sampled all samples from a single trajectory file.

---

## Solution: Re-run Judge Per Trajectory File

**Key insight**: We REUSE existing trajectory logs - NOT re-running trajectory generation. Only re-run `run_judge` on individual files.

### Step 1: Run judge on ALL files (including benign)

```bash
# 4.1-nano - run on ALL files (including benign for baseline)
for file in logs/runs/usaco-trusted-monitor-4.1nano-test-20260124_081755/*.eval; do
  python -m src.detection_game.cli.run_judge \
    --config-name=usaco-trusted-monitor-4.1nano \
    judge.dataset.path="$file"
done

# 5-nano - run on ALL files (including benign for baseline)
for file in logs/runs/usaco-trusted-monitor-5nano-test-20260124_082423/*.eval; do
  python -m src.detection_game.cli.run_judge \
    --config-name=usaco-trusted-monitor-5nano \
    judge.dataset.path="$file"
done
```

### Step 2: Per-prompt comparison with bootstrap CV

For each model:
1. Load benign scores (negative class)
2. For each sandbagging prompt, load its scores (positive class)
3. Run bootstrap CV to get detection metrics (recall@5%FPR, AUROC, etc.)

Prompt extracted dynamically from `model.role` event: `sandbagger-t1.0-sp_{PROMPT}_hash-model`

---

## Verification

Expected output:
```
4.1-nano per-prompt detection metrics:
  BENIGN baseline: n=XX, mean=XX.XX
  off_by_one vs benign: recall@5%FPR=XX%, AUROC=XX.XX
  total_system_failure vs benign: recall@5%FPR=XX%, AUROC=XX.XX
  zero_accuracy_explicit vs benign: recall@5%FPR=XX%, AUROC=XX.XX
  chaotic_coder vs benign: recall@5%FPR=XX%, AUROC=XX.XX
  anti_pattern_solver vs benign: recall@5%FPR=XX%, AUROC=XX.XX
```

## Key Files

- 4.1-nano trajectories: `logs/runs/usaco-trusted-monitor-4.1nano-test-20260124_081755/*.eval` (6 files)
- 5-nano trajectories: `logs/runs/usaco-trusted-monitor-5nano-test-20260124_082423/*.eval` (9 files)
- Benign file hashes: `eQrK334R` (4.1-nano), `FBp6N6qT` (5-nano)

## Notes

- Prompt extracted dynamically from `model.role` event pattern: `sandbagger-t1.0-sp_{PROMPT}_hash-model`
- Per-prompt bootstrap CV compares each sandbagging prompt against benign baseline
