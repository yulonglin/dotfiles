# Plan: Fix Raw JSONL Dumps in Task/Subagent Output

## Context

When Claude Code runs Task tool subagents, the output frequently contains raw JSONL conversation transcripts (every message, tool call, hook progress event) instead of just the agent's final text response. This consumes massive context, makes sessions slow/unusable, and is a [known upstream bug (#16789)](https://github.com/anthropics/claude-code/issues/16789).

**Root cause**: Two code paths exist in Claude Code for returning task results:
- Completion notification path (`<task-notification>` with `<result>` tag) — **works correctly**
- `TaskOutput` tool / synchronous path — **returns raw JSONL transcript**

**Fix strategy**: Force all Task calls to background mode, routing them through the working notification path. This is the [proven workaround](https://github.com/anthropics/claude-code/issues/16789) validated by other users.

## Approach: Single PreToolUse Hook

One hook, following the exact pattern of `auto_background.sh`. No PostToolUse hook needed — when tasks run in background, PostToolUse fires on the immediate "task started" response (not the JSONL), so a cleanup hook would be dead code.

### File to Create

#### `claude/hooks/task_force_background.sh` (PreToolUse hook, matcher: `Task`)

Logic:
1. Skip if `CLAUDE_TASK_FORCE_BG=0` (env var escape hatch)
2. Skip if `jq` not available
3. Skip if `tool_input.resume` is present (resuming an existing agent — already background)
4. Skip if `tool_input.run_in_background` is already `true`
5. Set `updatedInput: { run_in_background: true }`
6. Set `additionalContext` reminding: "Task auto-backgrounded. Wait for `<task-notification>` with `<result>` tag. Do NOT poll with TaskOutput tool."

~30 lines of shell. Pattern follows `auto_background.sh` exactly (read stdin, jq early exits, jq -n output).

### File to Modify

#### `claude/settings.json` — Add PreToolUse hook entry

Add one new matcher group to the existing `PreToolUse` array:

```json
{
  "matcher": "Task",
  "hooks": [
    {
      "type": "command",
      "command": "~/.claude/hooks/task_force_background.sh"
    }
  ]
}
```

No PostToolUse changes needed.

### Key Files for Reference
- `claude/hooks/auto_background.sh` — Pattern to follow (jq parsing, env var config, updatedInput + additionalContext output)
- `claude/settings.json:102-160` — Existing hook configuration

## Why No PostToolUse Hook

The plan critic identified that Hook 2 (PostToolUse cleanup) would be dead code:
- When background is forced, PostToolUse fires on the "task started" response — no JSONL present
- The actual result arrives via `<task-notification>`, which is a different event path entirely
- The only scenario Hook 2 would help is if Hook 1 fails to force background — but then we have bigger problems

## Why No Sync Whitelist

Background mode works for all agent types including plan mode Explore agents — results arrive via notifications which the model handles. No agent fundamentally requires synchronous execution.

## Verification

1. Start a new Claude Code session in this dotfiles repo
2. Run a Task with `subagent_type: "Explore"` — should auto-background via hook
3. Verify the notification contains clean `<result>` text, not JSONL
4. Test `resume` pass-through: resume an agent — hook should skip
5. Test disable: set `CLAUDE_TASK_FORCE_BG=0`, run a task — should run synchronously
6. Verify plan mode still works with background Explore agents
