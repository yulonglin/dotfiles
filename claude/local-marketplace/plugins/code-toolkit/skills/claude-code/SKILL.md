---
name: claude-code
description: |
  Delegate tasks to Claude Code CLI for a Claude-powered second opinion, parallel implementation,
  or plan review. Use when you want Claude (not Codex/Gemini) as a delegate — e.g., tasks needing
  Claude's judgment, tool use, or MCP access.

  Do NOT use for:
  - Pure implementation with clear specs (use codex-cli)
  - Large context analysis (use gemini-cli)
  - Quick edits under ~10 lines (faster to do directly)
---

# Claude Code CLI Delegation

Delegate tasks to a separate Claude Code CLI process for parallel work, second opinions, or tasks needing Claude's judgment and tool access.

## When to Use

| Use claude-code | Don't use |
|---|---|
| Second opinion on plan/approach | Pure implementation (use codex-cli) |
| Tasks needing Claude's judgment/taste | Large context analysis (use gemini-cli) |
| Parallel independent implementation | Quick <10 line edits |
| Tasks needing MCP server access | Tasks you're already doing |

## Strengths & Limitations

- **Strong at**: Judgment, taste, nuanced reasoning, tool use, MCP access, multi-step tasks
- **Weak at**: Large context (limited window), pure speed (Codex is faster for simple tasks)
- **Complementary to**: Codex (instruction-following) and Gemini (large context)

## Execution Modes

### Sync Mode (quick tasks)

```bash
# Direct output
claude -p --model sonnet --permission-mode bypassPermissions "<prompt>"

# Capture to file
claude -p --model sonnet --permission-mode bypassPermissions "<prompt>" > /tmp/claude-review.txt
```

### Async Mode (larger tasks via tmux)

```bash
# Setup
TASK_NAME="claude-<short-desc>-$(date -u +%m%d-%H%M)"
tmux has-session -t delegates 2>/dev/null || tmux new-session -d -s delegates -n default

# Launch
tmux new-window -t delegates -n "$TASK_NAME"
tmux-cli send "cd $(pwd) && claude -p --model sonnet --permission-mode bypassPermissions '<prompt>' 2>&1 | tee /tmp/${TASK_NAME}.log" --pane="delegates:${TASK_NAME}.1"

# Notify user
echo "Claude running in delegates:${TASK_NAME} — check with: tmux-cli capture --pane=delegates:${TASK_NAME}.1"
```

## Model Selection

| Task | Model |
|---|---|
| Quick review, simple tasks | `--model haiku` |
| Standard tasks, plan review | `--model sonnet` |
| Complex judgment, architecture | `--model opus` |

## Second Opinion on Plans

Use Claude's judgment to critique implementation plans:

```bash
claude -p --model sonnet --permission-mode bypassPermissions \
  "Review this implementation plan and identify missed edge cases, simpler alternatives, and potential issues: $(cat .claude/plans/plan.md)"
```

For plans that reference code, let Claude explore:

```bash
claude -p --model sonnet --permission-mode bypassPermissions \
  "Read .claude/plans/plan.md, then explore the relevant source files. Identify: 1) Missed edge cases 2) Simpler alternatives 3) Potential issues 4) Files needing changes not mentioned"
```

## Session Naming Convention

All Claude Code tmux windows use:
```
claude-<task>-<MMDD>-<HHMM>
```

In the shared `delegates` session (same session used by codex-cli, gemini-cli, and other CLI delegates).

## Tips

- **Use for judgment calls**: When you need taste, not just correctness
- **Leverage tool access**: Claude can read files, run commands, use MCP servers
- **Pair with Codex**: Claude reviews the plan, Codex implements it
- **Keep prompts focused**: One clear task per invocation
- **Review output**: Always check results before acting on them
