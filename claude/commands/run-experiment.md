---
argument-hint: <command>
description: Run experiments with output isolation to prevent context pollution
---

# Run Experiment

Run the provided command with output redirected to a timestamped log file. Prevents context pollution from verbose output.

$ARGUMENTS

## When to Use

- Scripts (Python, shell, etc.) with verbose output, progress bars, or debug logging
- `pytest` with verbose output
- `make`/build commands
- Any long-running process with progress output

## Instructions

Given the user's command (passed as `$ARGUMENTS`):

1. Create log file: `LOG="tmp/experiment_$(date +%Y%m%d_%H%M%S).log"`
2. Ensure directory exists: `mkdir -p tmp`
3. Run the command with redirection: `<user-command> >> "$LOG" 2>&1`
4. Use `run_in_background: true` if command likely takes >30 seconds
5. When complete, show only the final 50 lines: `tail -50 "$LOG"`
6. Report: log file path, exit code, final output summary

## Notes

- Full output is preserved in log file for debugging
- Only summary enters conversation context
- Use TaskOutput to check background task status
- For Hydra experiments: use Hydra directly (logs auto-save to `out/*/main.log`)
