# Plan: Solving Context Pollution from Verbose Experiment Output

## Summary

Implement four-layer defense against context pollution from verbose bash output:
1. CLAUDE.md guidance (always-on)
2. `/run-experiment` skill (explicit invocation)
3. PostToolUse hook (automatic safety net)
4. settings.json registration

## Files to Modify/Create

| File | Action |
|------|--------|
| `claude/CLAUDE.md` | Add context management section |
| `claude/commands/run-experiment.md` | **CREATE** - new skill |
| `claude/hooks/truncate_output.sh` | **CREATE** - PostToolUse hook |
| `claude/settings.json` | Register new hook |

---

## Implementation Details

### 1. `claude/CLAUDE.md` - Add Section

Insert after "### Shell Commands" section:

```markdown
### Context Management (Verbose Output)

**Problem**: Long bash outputs (tqdm, build logs) consume context rapidly.

**Solutions** (use in order of preference):
1. **`run_in_background: true`** for any command with progress bars or >100 lines expected output
   - Bash tool parameter, output buffered separately
   - Retrieve later with TaskOutput tool
2. **`/run-experiment`** skill for non-Hydra experiment pipelines
3. **Output redirection** for one-off commands:
   ```bash
   LOG="tmp/$(date +%s).log"
   command >> "$LOG" 2>&1 && tail -30 "$LOG"
   ```

**Log locations**:
- Hydra experiments: `out/YYMMDD_HHmmss_name/main.log` (automatic)
- Non-Hydra verbose commands: `tmp/` (temporary, delete when done)

**NEVER** run these synchronously in main context:
- `uv run python` training/eval scripts with tqdm
- `pytest` with verbose output
- `make`/build commands
- Any Hydra experiment (use Hydra's built-in logging)
```

### 2. `claude/commands/run-experiment.md` - New Skill

```markdown
---
argument-hint: <command>
description: Run experiments with output isolation to prevent context pollution
---

# Run Experiment

Run the provided command with output redirected to a timestamped log file.

$ARGUMENTS

## Instructions

1. Create log file: `LOG="tmp/experiment_$(date +%Y%m%d_%H%M%S).log"`
2. Ensure directory exists: `mkdir -p tmp`
3. Run command with redirection: `$COMMAND >> "$LOG" 2>&1`
4. Use `run_in_background: true` if command likely takes >30 seconds
5. When complete, show only the final 50 lines: `tail -50 "$LOG"`
6. Report: log file path, exit code, final output summary

## Notes

- Full output is preserved in log file for debugging
- Only summary enters conversation context
- Use TaskOutput to check background task status
- For Hydra experiments: use Hydra directly (logs auto-save to `out/*/main.log`)
```

### 3. `claude/hooks/truncate_output.sh` - New Hook

```bash
#!/bin/sh
# PostToolUse hook: Truncate long bash outputs to prevent context pollution
# Outputs JSON with suppressOutput + systemMessage for long outputs

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""')

# Only process Bash tool outputs
if [ "$TOOL_NAME" != "Bash" ]; then
    exit 0
fi

STDOUT=$(echo "$INPUT" | jq -r '.tool_response.stdout // ""')
STDERR=$(echo "$INPUT" | jq -r '.tool_response.stderr // ""')
EXIT_CODE=$(echo "$INPUT" | jq -r '.tool_response.exit_code // 0')
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

# Calculate total output length
TOTAL_LEN=$((${#STDOUT} + ${#STDERR}))

# Threshold: 5000 characters
if [ "$TOTAL_LEN" -lt 5000 ]; then
    exit 0
fi

# Truncate: keep first 500 + last 1000 chars
if [ ${#STDOUT} -gt 1500 ]; then
    HEAD=$(echo "$STDOUT" | head -c 500)
    TAIL=$(echo "$STDOUT" | tail -c 1000)
    TRUNCATED_STDOUT="${HEAD}

... [${#STDOUT} chars truncated] ...

${TAIL}"
else
    TRUNCATED_STDOUT="$STDOUT"
fi

# Build summary message
SUMMARY="Command: ${COMMAND}
Exit code: ${EXIT_CODE}
Output (truncated from ${TOTAL_LEN} chars):

${TRUNCATED_STDOUT}"

# Escape for JSON
SUMMARY_ESCAPED=$(printf '%s' "$SUMMARY" | jq -Rs .)

# Output JSON to suppress original and replace with summary
printf '{"suppressOutput": true, "systemMessage": %s}\n' "$SUMMARY_ESCAPED"
```

### 4. `claude/settings.json` - Register Hook

Add to existing PostToolUse hooks array:

```json
{
  "type": "command",
  "command": "~/.claude/hooks/truncate_output.sh"
}
```

Full PostToolUse section becomes:
```json
"PostToolUse": [
  {
    "matcher": "Bash",
    "hooks": [
      {
        "type": "command",
        "command": "~/.claude/hooks/auto_log.sh END"
      },
      {
        "type": "command",
        "command": "~/.claude/hooks/truncate_output.sh"
      }
    ]
  }
]
```

---

## Execution Order

1. Edit `claude/CLAUDE.md` - add context management section
2. Create `claude/commands/run-experiment.md`
3. Create `claude/hooks/truncate_output.sh` and make executable
4. Edit `claude/settings.json` - register hook
5. Test with a verbose command

## Verification

After implementation, test with:
```bash
# Should trigger truncation (>5000 chars)
python -c "print('x' * 10000)"

# Should trigger /run-experiment pattern
/run-experiment uv run python train.py --config config.yaml
```

## Rollback

If hook causes issues:
- Remove hook from `settings.json`
- CLAUDE.md guidance and skill remain functional
