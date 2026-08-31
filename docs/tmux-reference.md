# tmux-cli + Native tmux Reference

**Use hybrid approach**: Native tmux for named sessions/windows, tmux-cli for workflow (send, capture, wait_idle).

## Naming Conventions

| Resource | Pattern | Example |
|----------|---------|---------|
| Session | Purpose-based | `experiments`, `logs`, `debug` |
| Window | `<task>-<MMDD>-<HHMM>` | `train-gpt2-0127-1430`, `eval-mmlu-0215-0915` |
| Pane | Usually just one per window | N/A |

## Setup (Run Once per Session Type)

```bash
tmux has-session -t experiments 2>/dev/null || \
  tmux new-session -d -s experiments -n "default"
```

## Running Experiments

```bash
# 1. Create unique window name
EXP_NAME="train-gpt2-$(date -u +%m%d-%H%M)"

# 2. Create window
tmux new-window -t experiments -n "$EXP_NAME" || { echo "Window exists"; exit 1; }

# 3. Get pane ID
PANE_ID="experiments:$EXP_NAME.1"

# 4. Send command
tmux-cli send "cd $(pwd) && python train.py 2>&1 | tee tmp/${EXP_NAME}.log" --pane="$PANE_ID"

# 5. Check output
tmux-cli capture --pane="$PANE_ID"

# 6. Wait for completion
tmux-cli wait_idle --pane="$PANE_ID" --idle-time=3.0
```

## Inside vs Outside tmux

| Mode | tmux-cli behavior | Recommended approach |
|------|-------------------|---------------------|
| **Outside tmux** | Creates `remote-cli-session` | Use named sessions for clarity |
| **Inside tmux** | Creates panes in current window | Use named windows to avoid clutter |

**Inside tmux** - avoid cluttering current window:
```bash
tmux new-window -n "exp-train"
tmux-cli send "python train.py" --pane=":exp-train.1"
```

## Quick Reference (Copy-Paste)

```bash
EXP="eval-mmlu-$(date -u +%m%d-%H%M)" && \
tmux has-session -t experiments 2>/dev/null || tmux new-session -d -s experiments -n default && \
tmux new-window -t experiments -n "$EXP" && \
tmux-cli send "cd $(pwd) && YOUR_COMMAND 2>&1 | tee tmp/${EXP}.log" --pane="experiments:${EXP}.1" && \
echo "Running in experiments:${EXP} - attach with: tmux attach -t experiments"
```

## Viewing and Cleanup

```bash
tmux list-windows -t experiments    # List experiments
tmux attach -t experiments          # Attach to watch
tmux kill-window -t experiments:X   # Kill specific
tmux kill-session -t experiments    # Kill all
```
