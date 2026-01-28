---
name: run-experiment
description: Run experiments with output isolation to prevent context pollution.
---

# Run Experiment

Run the provided command in a named tmux window with output logged to a file. Prevents context pollution and survives disconnects.

## Naming Convention

Use sortable timestamps so alphabetical = chronological:
- Session: `experiments` (shared across all experiments)
- Window: `<task>-<MMDD>-<HHMM>` like `train-gpt2-0127-1430`, `eval-mmlu-0215-0915`
- Log: `tmp/<window-name>.log`

## Instructions

1. **Derive experiment name** from the command + sortable timestamp:
   ```
   "python train.py --model gpt2" → "train-gpt2-0127-1430"
   "uv run eval.py --dataset mmlu" → "eval-mmlu-0215-0915"
   "python sweep.py --lr 1e-4" → "sweep-lr-0303-2200"
   ```

2. **Create session and named window**:
   ```bash
   EXP_NAME="<task>-$(date -u +%m%d-%H%M)"  # e.g., train-gpt2-0127-1430
   tmux has-session -t experiments 2>/dev/null || tmux new-session -d -s experiments -n default
   tmux new-window -t experiments -n "$EXP_NAME"
   ```

3. **Create log path and run**:
   ```bash
   mkdir -p tmp
   LOG="tmp/${EXP_NAME}.log"
   PANE_ID="experiments:${EXP_NAME}.1"
   tmux-cli send "cd $(pwd) && <user-command> 2>&1 | tee $LOG" --pane="$PANE_ID"
   ```

4. **Report to user**:
   ```
   Experiment running: experiments:<EXP_NAME>
   Log: tmp/<EXP_NAME>.log

   Monitor with:
   - `tmux-cli capture --pane=experiments:<EXP_NAME>.1` - recent output
   - `tmux attach -t experiments` - live view (Ctrl+B, D to detach)
   - `tail -f tmp/<EXP_NAME>.log` - follow log
   ```

5. **Status Check (if requested)**:
   - Use `tmux-cli capture --pane=experiments:<EXP_NAME>.1` for recent output
   - Use `tail -50 tmp/<EXP_NAME>.log` for log contents

## Example

User: `/run-experiment uv run python train.py --model gpt2-small --epochs 100`

You run:
```bash
# 1. Set experiment name (sortable: MMDD-HHMM)
EXP_NAME="train-gpt2-$(date -u +%m%d-%H%M)"  # e.g., train-gpt2-0127-1430

# 2. Ensure session exists and create named window
tmux has-session -t experiments 2>/dev/null || tmux new-session -d -s experiments -n default
tmux new-window -t experiments -n "$EXP_NAME"

# 3. Run with logging
mkdir -p tmp
tmux-cli send "cd /path/to/project && uv run python train.py --model gpt2-small --epochs 100 2>&1 | tee tmp/${EXP_NAME}.log" --pane="experiments:${EXP_NAME}.1"
```

Then tell user:
```
Experiment running: experiments:train-gpt2-0127-1430
Log: tmp/train-gpt2-0127-1430.log

Monitor with:
- `tmux-cli capture --pane=experiments:train-gpt2-0127-1430.1` - recent output
- `tmux attach -t experiments` - live view (Ctrl+B, D to detach)
```

## Multiple Experiments

Each gets its own named window:
```bash
# First experiment
tmux new-window -t experiments -n "train-base"
tmux-cli send "python train.py --model base | tee tmp/train-base.log" --pane="experiments:train-base.1"

# Second experiment
tmux new-window -t experiments -n "train-large"
tmux-cli send "python train.py --model large | tee tmp/train-large.log" --pane="experiments:train-large.1"

# List all experiments
tmux list-windows -t experiments
```

## Cleanup

```bash
tmux kill-window -t experiments:train-gpt2  # Kill specific experiment
tmux kill-session -t experiments            # Kill all experiments
```

## Notes

- **Named windows**: Easy to identify which experiment is which
- **Persistent**: Survives Claude session disconnects
- **Works inside/outside tmux**: Same commands work in both modes
- **Monitorable**: `tmux attach -t experiments` shows all experiment windows
- Hydra experiments: logs also auto-save to `out/*/main.log`
