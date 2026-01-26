# Plan: Clearer tmux-cli guidance for running experiments

## Problem

The current CLAUDE.md mentions tmux-cli in the "Tools & Environment" section but doesn't make it clear that experiments should use tmux-cli sessions for persistent output. The `/run-experiment` skill uses `run_in_background: true` which works but:
- Output is lost if the Claude session ends or disconnects
- No easy way for user to monitor progress independently
- tmux sessions survive disconnects and can be attached from any terminal

## Changes

### 1. Update CLAUDE.md - "Verbose Command Output" section (lines 257-278)

Restructure to prioritize tmux-cli for experiments:

**Current order:**
1. `run_in_background: true`
2. `/run-experiment` skill
3. Output redirection

**New order:**
1. **tmux-cli sessions** (PREFERRED for experiments) - persistent, monitorable
2. `run_in_background: true` - for quick commands where persistence isn't needed
3. Output redirection - fallback for one-off commands

### 2. Add new section: "Running Experiments (CRITICAL)" after line ~278

New dedicated section covering:
- Why tmux-cli (persistent, survives disconnect, user can monitor)
- Standard pattern using `tmux-cli launch` then `tmux-cli send`
- How to check on running experiments
- Example workflow

### 3. Update `/run-experiment` skill to use tmux-cli

Change from `run_in_background: true` with output redirection to tmux-cli pattern:
- Launch a zsh shell in tmux
- Send the command to that shell
- Report the pane ID and how to monitor

## Files to Modify

| File | Action |
|------|--------|
| `/Users/yulong/.claude/CLAUDE.md` | Edit - restructure verbose output section, add experiments section |
| `/Users/yulong/.claude/skills/run-experiment/SKILL.md` | Edit - use tmux-cli instead of run_in_background |

## Detailed Changes

### CLAUDE.md - New "Running Experiments" section (insert after line ~278)

```markdown
#### Running Experiments (CRITICAL)

⚠️ **Use tmux-cli sessions for all experiments** ⚠️

tmux sessions are persistent - they survive disconnects, Claude session restarts, and can be monitored from any terminal.

**Standard Pattern:**
```bash
# 1. Create a new tmux session for the experiment
tmux-cli launch "$SHELL"  # Returns pane ID like "remote-cli-session:0.0"

# 2. Run the experiment in that session
tmux-cli send "cd /path/to/project && uv run python train.py --epochs 100 2>&1 | tee tmp/experiment.log" --pane=0

# 3. Check progress anytime
tmux-cli capture --pane=0  # Recent output
tmux-cli attach            # Live view (Ctrl+B, D to detach)
```

**Benefits over `run_in_background`:**
- Persists after Claude session ends (output survives disconnects)
- User can `tmux-cli attach` from any terminal to watch live
- Multiple experiments in parallel (different panes/windows)
- Full scrollback history preserved

**When to use which:**
| Tool | Use for |
|------|---------|
| tmux-cli | Experiments, long-running jobs, anything >5 min |
| `run_in_background` | Quick commands (<5 min) where you'll check immediately |
| Output redirection | One-off verbose commands you'll read once |
```

### CLAUDE.md - Update "Verbose Command Output" (lines 257-278)

Reorder and clarify the options, emphasizing tmux-cli for experiments.

### /run-experiment skill - Update to use tmux-cli

```markdown
## Instructions

1. **Launch tmux session**:
   ```bash
   tmux-cli launch "$SHELL"
   ```
   Note the returned pane ID.

2. **Run experiment in session**:
   ```bash
   tmux-cli send "cd $(pwd) && <user-command> 2>&1 | tee tmp/exp_$(utc_timestamp).log" --pane=<ID>
   ```

3. **Report to user**:
   - Pane ID for monitoring
   - Log file path
   - Commands to check: `tmux-cli capture --pane=<ID>` or `tmux-cli attach`
```

## Verification

1. Run `/run-experiment uv run python -c "import time; [print(i) or time.sleep(1) for i in range(5)]"`
2. Verify tmux session is created
3. Verify `tmux-cli capture` shows output
4. Verify log file is created in `tmp/`
