---
name: codex-cli
description: |
  Delegate well-scoped implementation tasks to Codex CLI. Use when:
  - Implementing a well-defined function, module, or feature
  - Bug fixes with known root cause and clear fix
  - Scoped refactoring (rename, extract, restructure within a module)
  - File generation from a template or spec
  - Getting a second opinion on an implementation plan or approach

  Do NOT use for:
  - Exploration or codebase understanding (use Explore agent)
  - Multi-turn refinement or ambiguous tasks (do it yourself)
  - Quick edits under ~10 lines (faster to do directly)
  - Tasks requiring conversation context (Codex has no context)
  - Tasks requiring judgment, taste, or subjective design decisions (Codex is instruction-following, not taste-driven)
---

# Codex CLI Delegation

Delegate well-scoped implementation tasks to Codex CLI for parallel, autonomous execution.

## When to Use

| Use Codex | Don't Use Codex |
|-----------|----------------|
| Implement a defined function/module | Explore or understand code |
| Bug fix with known root cause | Ambiguous "something is wrong" |
| Scoped refactoring | Multi-file architectural changes |
| Generate boilerplate from spec | Quick <10 line edits |
| Second opinion on a plan/approach | Tasks needing conversation context |
| Independent task while you work on something else | Judgment/taste/subjective design decisions |

## Strengths & Limitations

- **Strong at**: Precise implementation, following specs exactly, catching concrete errors, structured code generation
- **Weak at**: Ambiguous requirements, architectural taste, naming/style judgment, subjective quality decisions
- **Rule of thumb**: If you can write a verification command, Codex can probably do the task well

## Execution Modes

### Sync Mode (small/fast tasks)

For tasks completing in under a minute. Run and read result immediately.

```bash
# Create output file path
OUTPUT="/tmp/codex-$(date -u +%s).txt"

# Execute
codex exec --full-auto -C <working-dir> -o "$OUTPUT" "<prompt>"

# Read result
cat "$OUTPUT"

# Check what changed
git diff
```

### Async Mode (larger tasks via tmux)

For tasks that take longer. Launch in tmux `delegates` session and continue working.

```bash
# Setup
TASK_NAME="codex-<short-desc>-$(date -u +%m%d-%H%M)"
tmux has-session -t delegates 2>/dev/null || tmux new-session -d -s delegates -n default

# Launch
tmux new-window -t delegates -n "$TASK_NAME"
tmux-cli send "cd $(pwd) && codex exec --full-auto -o /tmp/${TASK_NAME}.txt '<prompt>' 2>&1 | tee /tmp/${TASK_NAME}.log" --pane="delegates:${TASK_NAME}.1"

# Notify user
echo "Codex running in delegates:${TASK_NAME} — check with: tmux-cli capture --pane=delegates:${TASK_NAME}.1"
```

## Prompt Construction

Build prompts with this structure:

```
[DELEGATION HEADER]
You are implementing a specific task. Do not explore or ask questions — implement directly.

[TASK]
<Clear description of what to implement>

[CONTEXT]
- Working directory: <path>
- Key files: <list relevant files>
- Language/framework: <stack>

[CONSTRAINTS]
- <Style constraints, patterns to follow>
- <What NOT to change>
- Match existing code style

[VERIFICATION]
After implementing, run: <test command or verification step>
```

### Example Prompt

```
You are implementing a specific task. Do not explore or ask questions — implement directly.

TASK: Add a `parse_duration` function to src/utils/time.py that converts human-readable
duration strings (e.g., "5m", "2h30m", "1d") into seconds.

CONTEXT:
- Working directory: /Users/yulong/code/myproject
- Key files: src/utils/time.py (add function here), tests/test_time.py (add tests)
- Language: Python 3.11, pytest for tests

CONSTRAINTS:
- Support: s (seconds), m (minutes), h (hours), d (days)
- Raise ValueError for invalid input
- Follow existing docstring style in src/utils/

VERIFICATION:
Run: pytest tests/test_time.py -v
```

## Result Integration

### After Sync Execution
1. Read the output file for any messages from Codex
2. Run `git diff` to see what changed
3. Review changes, commit if good

### After Async Execution
1. Check tmux window: `tmux-cli capture --pane=delegates:<task-name>.1`
2. Wait for idle: `tmux-cli wait_idle --pane=delegates:<task-name>.1`
3. Review with `git diff`, commit if good

## Second Opinion on Plans

Use sync mode with xhigh reasoning to get Codex's critique of an implementation plan:

```bash
codex exec --full-auto -c model_reasoning_effort="xhigh" -C <working-dir> -o /tmp/review.txt \
  "Review this plan: <plan text>. Identify: 1) Missed edge cases 2) Simpler alternatives 3) Potential issues"
```

Or pipe a plan file:

```bash
codex exec --full-auto -c model_reasoning_effort="xhigh" -C <working-dir> -o /tmp/review.txt \
  "Review this implementation plan and identify missed edge cases, simpler alternatives, and potential issues: $(cat .claude/plans/plan.md)"
```

Codex excels at spotting concrete implementation gaps (missing error paths, race conditions) but won't help with taste questions (naming, API design aesthetics).

## Session Naming Convention

All Codex tmux windows use:
```
codex-<task>-<MMDD>-<HHMM>
```

In the shared `delegates` session (same session used by gemini-cli and other CLI delegates).

## Model Selection

Default: trust `~/.codex/config.toml` (`model` and `model_reasoning_effort` keys). Override per-call when needed:

| Task complexity | Flag |
|---|---|
| Simple implementation, boilerplate | Default (high) |
| Complex logic, tricky edge cases | `-c model_reasoning_effort="xhigh"` |
| Plan review / second opinion | `-c model_reasoning_effort="xhigh"` |
| Different model entirely | `-m <model>` |

## Tips

- **Be specific**: Codex works best with precise, unambiguous tasks
- **Include file paths**: Tell it exactly which files to create or modify
- **Add verification**: Include a test command so Codex can self-check
- **One task per call**: Don't bundle multiple unrelated changes
- **Review before commit**: Always check `git diff` after Codex runs
