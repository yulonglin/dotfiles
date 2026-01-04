---
argument-hint: <command>
description: Run experiments with output isolation to prevent context pollution
---

# Run Experiment

Run the provided command in background with output redirected to a log file. Prevents context pollution from verbose output.

$ARGUMENTS

## Instructions

**ALWAYS use `run_in_background: true`** for the Bash tool call.

1. Create log file and run command:
   ```bash
   mkdir -p tmp && LOG="tmp/exp_$(date +%Y%m%d_%H%M%S).log" && echo "Log: $LOG" && <user-command> >> "$LOG" 2>&1 && echo "Exit: $?" || echo "Exit: $?"
   ```
2. Use `run_in_background: true` parameter (MANDATORY)
3. Report the log file path to user immediately
4. When user asks for status, use `TaskOutput` tool to check, then `tail -50 <log-file>`

## Example

User: `/run-experiment uv run python train.py --epochs 100`

You run with Bash tool:
- command: `mkdir -p tmp && LOG="tmp/exp_$(date +%Y%m%d_%H%M%S).log" && echo "$LOG" && uv run python train.py --epochs 100 >> "$LOG" 2>&1`
- run_in_background: true

Then tell user: "Running in background. Log: tmp/exp_20250104_123456.log. Use `/run-experiment status` to check."

## Notes

- Full output preserved in log file
- Only summary enters conversation context
- Hydra experiments: logs also auto-save to `out/*/main.log`
