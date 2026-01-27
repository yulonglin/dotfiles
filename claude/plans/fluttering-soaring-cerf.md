# Plan: Run MATH Behavioral Probes Experiments

## Context
- 10/12 main experiments complete (C3, TM, LD)
- Need to add Behavioral Probes as 4th detection method
- Each sweep config already includes **both sandbagging (10 prompts) + normal (1 run)** = 11 .eval files per experiment

## TM Config Verified
- **Judge model**: `claude-3-5-haiku-20241022`
- **Prompt**: `trusted_monitor.yaml` - Anthropic-adapted `manipulation_score` (1-10)
- **Output**: 11 .eval files per experiment (10 sandbag + 1 normal)

## Tasks

### 1. Create Dev Configs (2 files)
Copy from test configs, change dataset to dev split.

Files to create:
- `math-behavioral-probes-4.1nano-dev.yaml` (from `-test.yaml`)
- `math-behavioral-probes-5nano-dev.yaml` (from `-test.yaml`)

Changes needed:
```yaml
# Change these lines:
- override dataset: math-l5-dev  # was math-l5-test
dataset_overrides.math.custom_split: dev  # was test
logs.dir: math-behavioral-probes-{model}-dev-...  # update name
```

### 2. Launch Experiments (4 total)

| Config | Model | Split | Samples |
|--------|-------|-------|---------|
| math-behavioral-probes-4.1nano-dev | gpt-4.1-nano | dev | 921 |
| math-behavioral-probes-5nano-dev | gpt-5-nano | dev | 921 |
| math-behavioral-probes-4.1nano-test | gpt-4.1-nano | test | 1383 |
| math-behavioral-probes-5nano-test | gpt-5-nano | test | 1383 |

### 3. Tmux Organization

Create a **new session** `bp` with 4 named windows:
```bash
# Create session with first window
tmux new-session -d -s bp -n "4.1nano-dev"
tmux new-window -t bp -n "4.1nano-test"
tmux new-window -t bp -n "5nano-dev"
tmux new-window -t bp -n "5nano-test"
```

Then send commands to each window:
```bash
cd /workspace/yulong/code/sandbagging-detection/dev

# Window 0: 4.1nano-dev
tmux send-keys -t bp:4.1nano-dev "uv run python -m src.detection_game.cli.run_sweep --config-name=math-behavioral-probes-4.1nano-dev --multirun 2>&1 | tee tmp/bp-4.1nano-dev.log" Enter

# Window 1: 4.1nano-test
tmux send-keys -t bp:4.1nano-test "uv run python -m src.detection_game.cli.run_sweep --config-name=math-behavioral-probes-4.1nano-test --multirun 2>&1 | tee tmp/bp-4.1nano-test.log" Enter

# Window 2: 5nano-dev
tmux send-keys -t bp:5nano-dev "uv run python -m src.detection_game.cli.run_sweep --config-name=math-behavioral-probes-5nano-dev --multirun 2>&1 | tee tmp/bp-5nano-dev.log" Enter

# Window 3: 5nano-test
tmux send-keys -t bp:5nano-test "uv run python -m src.detection_game.cli.run_sweep --config-name=math-behavioral-probes-5nano-test --multirun 2>&1 | tee tmp/bp-5nano-test.log" Enter
```

User can attach with: `tmux attach -t bp`

## Expected Output
- 4 run directories
- 11 .eval files each (10 sandbag prompts + 1 normal)
- Batch mode enabled (~50% cost reduction)

## Reporting Checklist (per REPORTING_CHECKLIST.md)
After completion, ensure:
- [ ] **Metrics**: recall@5%FPR, pAUC@5%FPR (primary); AUROC, AUPRC (secondary)
- [ ] **Error bars**: SEM from bootstrap (1000 iterations)
- [ ] **Per-prompt results**: Each of 10 prompts reported separately + summary (min/median/mean/max)
- [ ] **k-samples**: k=10 (must match other methods)
- [ ] **Dev/test protocol**: Threshold on dev (40%), metrics on test (60%)
- [ ] **Context metrics**: Performance gap, sandbag refusal rate

## Verification
```bash
# Check all experiments have 11 .eval files
for dir in logs/runs/math-behavioral-probes-*-2026*; do
  echo "$(basename $dir): $(ls $dir/*.eval 2>/dev/null | wc -l) .eval"
done

# Check tmux session
tmux list-windows -t bp
```
