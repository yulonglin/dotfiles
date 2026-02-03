# Fix TM Judge Directory Naming

## Problem

Judge directories use generic timestamped names (`YYYY-MM-DD_HH-MM-SS/judge/`) with no model/split info, making them impossible to match to specific trajectory runs.

## Root Cause

Experiment configs (e.g., `gpqa-trusted-monitor-4.1nano-dev.yaml`) set `logs.dir` for trajectory naming:
```yaml
logs:
  dir: gpqa-trusted-monitor-4.1nano-dev-${now:%Y%m%d_%H%M%S}  # Good name!
```

But `conf.yaml` uses only timestamp for `run_id`:
```yaml
logs:
  run_id: ${logs.timestamp}  # Generic timestamp
  judge_dir: ${logs.base_dir}/runs/${logs.run_id}/judge  # Generic path
```

## Recommended Approach

**Align `run_id` with `dir`** in experiment configs so judge directories get the same informative naming.

## Implementation

### 1. Update experiment configs - Add `run_id` override

Add to each TM experiment config (e.g., `gpqa-trusted-monitor-4.1nano-dev.yaml`):

```yaml
logs:
  dir: gpqa-trusted-monitor-4.1nano-dev-${now:%Y%m%d_%H%M%S}
  run_id: gpqa-trusted-monitor-4.1nano-dev-${now:%Y%m%d_%H%M%S}  # NEW: Same as dir
```

This ensures judge runs get named like: `logs/runs/gpqa-trusted-monitor-4.1nano-dev-20260128_120000/judge/`

**Files to update:**
- `gpqa-trusted-monitor-4.1nano-dev.yaml`
- `gpqa-trusted-monitor-4.1nano-test.yaml`
- `gpqa-trusted-monitor-5nano-dev.yaml`
- `gpqa-trusted-monitor-5nano-test.yaml`
- (and benign variants if needed)

### 2. Update `extract_gpqa_scores.sh` - Match new naming pattern

```bash
find_latest_tm_judge() {
    local model="$1"  # e.g., "4.1nano" or "5nano"
    local split="$2"  # e.g., "dev" or "test"

    # Match: gpqa-trusted-monitor-{model}-{split}-*/judge
    for dir in $(ls -d logs/runs/gpqa-trusted-monitor-*${model}*-${split}-*/judge 2>/dev/null | sort -r); do
        if [[ -d "$dir" ]]; then
            echo "$dir"
            return
        fi
    done
}
```

## Files to Modify

| File | Change |
|------|--------|
| `src/detection_game/configs/gpqa-trusted-monitor-*.yaml` (8 files) | Add `logs.run_id` |
| `scripts/extract_gpqa_scores.sh` | Update `find_latest_tm_judge` pattern |

## Verification

```bash
# 1. Rerun judge (uses cache, fast)
python -m src.detection_game.cli.run_judge --config-name=gpqa-trusted-monitor-4.1nano-dev

# 2. Verify new directory naming
ls -d logs/runs/gpqa-trusted-monitor-*/judge

# 3. Run extraction
bash scripts/extract_gpqa_scores.sh

# 4. Check TM CSVs
ls -la out/gpqa_tm_*.csv
```

## Note

Existing timestamped judge directories won't match. Rerun judge workflow to create properly-named directories (API cache makes it cheap).
