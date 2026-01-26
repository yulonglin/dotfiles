---
name: run-experiment
description: Run experiments with output isolation to prevent context pollution.
---

# Run Experiment

Run the provided command in a persistent tmux session with output logged to a file. Prevents context pollution and survives disconnects.

## Instructions

**Use tmux-cli for persistent experiment sessions.**

1. **Create log file path**:
   ```bash
   mkdir -p tmp && echo "tmp/exp_$(date -u +%d-%m-%Y_%H-%M-%S).log"
   ```

2. **Launch tmux session**:
   ```bash
   tmux-cli launch "$SHELL"
   ```
   Note the returned pane ID (e.g., `remote-cli-session:0.0` → pane `0`).

3. **Run experiment in session**:
   ```bash
   tmux-cli send "cd $(pwd) && <user-command> 2>&1 | tee <log-path>" --pane=<ID>
   ```

4. **Report to user**:
   ```
   Experiment running in tmux pane <ID>.
   Log: <log-path>

   Monitor with:
   - `tmux-cli capture --pane=<ID>` - recent output
   - `tmux-cli attach` - live view (Ctrl+B, D to detach)
   - `tail -f <log-path>` - follow log file
   ```

5. **Status Check (if requested)**:
   - Use `tmux-cli capture --pane=<ID>` to show recent output
   - Use `tail -50 <log-file>` to show log file contents

## Example

User: `/run-experiment uv run python train.py --epochs 100`

You run:
```bash
# 1. Create log path
mkdir -p tmp && echo "tmp/exp_$(date -u +%d-%m-%Y_%H-%M-%S).log"
# Output: tmp/exp_26-01-2026_14-30-22.log

# 2. Launch tmux session
tmux-cli launch "$SHELL"
# Output: remote-cli-session:0.0

# 3. Send command
tmux-cli send "cd /path/to/project && uv run python train.py --epochs 100 2>&1 | tee tmp/exp_26-01-2026_14-30-22.log" --pane=0
```

Then tell user:
```
Experiment running in tmux pane 0.
Log: tmp/exp_26-01-2026_14-30-22.log

Monitor with:
- `tmux-cli capture --pane=0` - recent output
- `tmux-cli attach` - live view (Ctrl+B, D to detach)
```

## Notes

- **Persistent**: tmux sessions survive Claude session disconnects
- **Monitorable**: User can attach from any terminal with `tmux-cli attach`
- **Full output**: Both in tmux scrollback and log file
- Hydra experiments: logs also auto-save to `out/*/main.log`
