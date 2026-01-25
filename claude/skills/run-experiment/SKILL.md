---
name: run-experiment
description: Run experiments with output isolation to prevent context pollution.
---

# Run Experiment

Run the provided command in background with output redirected to a log file. Prevents context pollution from verbose output.

## Instructions

**ALWAYS use `run_in_background: true`** for the Bash tool call.

1. **Construct Command**:
   Create a log file and run the command like this:
   ```bash
   mkdir -p tmp && LOG="tmp/exp_$(date -u +%d-%m-%Y_%H-%M-%S).log" && echo "Log: $LOG" && <user-command> >> "$LOG" 2>&1 && echo "Exit: $?" || echo "Exit: $?"
   ```

2. **Execute**:
   - Use the `run_shell_command` (or equivalent Bash tool) with `run_in_background: true` (MANDATORY).

3. **Report**:
   - Report the log file path to user immediately.
   - Tell the user: "Running in background. Log: <path>. Use `/run-experiment status` to check."

4. **Status Check (if requested)**:
   - Use `TaskOutput` tool (or equivalent) to check background process status.
   - Use `tail -50 <log-file>` to show recent output.

## Example

User: `/run-experiment uv run python train.py --epochs 100`

You run with Bash tool:
- command: `mkdir -p tmp && LOG="tmp/exp_$(date -u +%d-%m-%Y_%H-%M-%S).log" && echo "$LOG" && uv run python train.py --epochs 100 >> "$LOG" 2>&1`
- run_in_background: true

Then tell user: "Running in background. Log: tmp/exp_25-01-2026_14-30-22.log. Use `/run-experiment status` to check."

## Notes

- Full output preserved in log file
- Only summary enters conversation context
- Hydra experiments: logs also auto-save to `out/*/main.log`
