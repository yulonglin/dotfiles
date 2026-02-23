# Review: task_force_background.sh Hook

## Summary

Comprehensive review of the PreToolUse hook that forces Task tool calls to background mode, working around Claude Code issue #16789 (TaskOutput returns raw JSONL instead of parsed agent responses).

## Findings

### 1. Registration Gap (Critical)

The hook file exists at `hooks/task_force_background.sh` but is **not registered** in `plugin.json`. The current plugin.json has:
- `TaskCreate` matcher for `pre_task_create.sh` (validates task location)
- No `Task` matcher at all

**Fix required:** Add a `Task` matcher entry in `plugin.json` under `PreToolUse`.

### 2. Correct Matcher Name

The Claude Code Task tool is called `Task` (confirmed from the tool descriptions in this session). The matcher in plugin.json should be `"Task"`, not `"TaskCreate"` (which is a separate lifecycle event).

### 3. Detailed Code Review

#### Original vs Proposed -- What Changed

| Aspect | Original | Proposed | Verdict |
|--------|----------|----------|---------|
| `set -euo pipefail` | Yes | Removed | **Good** -- `set -e` causes silent exits if any jq pipe returns non-zero; `set -u` kills the script on any unset var reference; `set -o pipefail` makes `echo | jq` fail if either side fails. All three are dangerous for hooks that should fail-open. |
| jq failure handling | Unhandled (crashes) | `|| { debug...; exit 0; }` | **Good** -- jq can fail on malformed input; hook should fail-open |
| Debug logging | None | `CLAUDE_TASK_FORCE_BG_DEBUG` env var | **Good** -- useful for debugging without modifying code |
| Error output | jq stderr visible | `2>/dev/null` on final jq | **Good** -- prevents jq errors from polluting Claude's stderr |
| Comment style | Verbose header | Minimal | **Neutral** -- both fine |

#### Issues in Both Versions

**A. `echo "$INPUT" | jq` pattern (3 invocations)**

Each call spawns a subshell + jq process. For a hook that runs on every Task call, this adds ~30-60ms of overhead per invocation (3 jq spawns). This is not a correctness issue but can be consolidated.

More importantly: if `$INPUT` contains literal newlines in JSON string values (which it will -- task prompts contain multi-line text), the `echo` is fine because jq handles multi-line JSON. But there is a subtle issue: if `$INPUT` happens to start with `-e` or `-n`, `echo` will interpret these as flags on some shells. Use `printf '%s\n' "$INPUT"` instead.

**B. No validation of tool_name**

The hook relies entirely on the plugin.json matcher to filter to Task tool calls. This is correct -- the matcher handles it. But a defensive `tool_name` check would prevent issues if the matcher config is wrong.

**C. No timeout on the hook itself**

Claude Code hooks have a default timeout (configurable). The jq operations here are fast (<50ms), so this is not a concern. No timeout needed.

**D. The `resume` check is incomplete**

`resume != null` catches explicit resumes, but what about `task_id` being set without `resume`? Looking at the Task tool schema, `task_id` can be used with `additional_prompt` to send messages to running agents. These should NOT be forced to background since they're communication with already-running background agents. However, if `task_id` is set, the agent is already running in background, so adding `run_in_background: true` is harmless (it's already background). So this is fine as-is.

### 4. Answers to Specific Questions

#### Q1: Edge cases where forcing background mode is harmful?

**Team agents (SendMessage-based):** Team agents use `SendMessage` tool, not `Task`. The `Task` tool is for subagent spawning only. No conflict.

**TaskOutput polls:** The whole point is to prevent TaskOutput usage. The `additionalContext` warns against it. This is correct behavior.

**Sequential dependencies:** This is the real concern. If Claude spawns Agent A, then needs A's result to decide what to do for Agent B, forcing both to background means Claude must wait for the notification from A before spawning B. Claude Code handles this correctly -- when `run_in_background: true`, the notification arrives as a `<task-notification>` message in the conversation, and Claude can then act on it. The workflow is: spawn A (background) -> receive notification -> spawn B (background) -> receive notification. This is the intended pattern.

**One genuine edge case:** If the upstream issue #16789 is fixed (TaskOutput returns clean text), this hook becomes unnecessary overhead. The `CLAUDE_TASK_FORCE_BG=0` env var handles this -- user can disable when the fix lands.

#### Q2: Is the error handling robust enough?

The proposed version is significantly better. Two remaining gaps:

1. **stdin read failure**: If `cat` fails (pipe broken, empty input), `INPUT` is empty, and the jq calls will fail. The proposed version handles this via the `|| { ... exit 0; }` on the final jq, but the intermediate jq calls (skip checks) would also fail silently and fall through to the force-background section, which would then fail and exit 0. This is correct fail-open behavior.

2. **stdout write failure**: If the parent process closes the pipe before reading the hook's output, the `echo "$RESULT"` would fail. With `set -e` removed, this is harmless -- the script exits, and Claude Code treats no output as "allow without modification." Correct behavior.

#### Q3: Should we add a timeout?

No. The jq operations complete in <50ms. Claude Code's hook infrastructure already has a configurable timeout (default 60s for command hooks). Adding a self-timeout would add complexity for no benefit.

#### Q4: Shell portability issues?

- `[[ ]]` is bash-specific (not POSIX `sh`). The shebang is `#!/bin/bash`, so this is fine.
- `command -v` is POSIX-compliant.
- `echo "$INPUT" | jq` -- as noted above, use `printf '%s\n'` for safety.
- `&>/dev/null` is bash-specific. Fine with bash shebang.
- The `debug()` function pattern is clean and portable within bash.

Note: `truncate_output.sh` uses `#!/bin/sh` for POSIX portability. This hook doesn't need that since it's only invoked by Claude Code (always has bash available).

#### Q5: `echo "$INPUT" | jq` -- pipe failures or truncation?

No risk of truncation. The pipe between `echo` and `jq` is in-memory (kernel pipe buffer, typically 64KB on macOS/Linux). Task tool inputs are JSON with a `prompt` field (usually 1-5KB) and metadata (~200 bytes). Even a very large prompt (10KB) is well within pipe buffer limits.

The `echo` issue mentioned in point A above is the real concern: `echo` interpreting leading `-e`/`-n` as flags. Fix: use `printf '%s\n' "$INPUT" | jq ...` or use a here-string `jq ... <<< "$INPUT"` (bash-specific but fine given our shebang).

#### Q6: Should the hook also intercept TaskOutput calls?

**Yes, this would be valuable.** Two options:

1. **Warn + allow**: Add a second matcher for `TaskOutput` that adds an `additionalContext` warning explaining that results arrive via notifications.
2. **Block**: Return `decision: "block"` with a reason.

I recommend **warn + allow** (not block), because:
- Blocking could break edge cases we haven't anticipated
- The warning teaches the model the correct pattern
- If the upstream fix lands, TaskOutput becomes safe again

This should be a **separate hook file** (not merged into task_force_background.sh) since it has a different matcher.

---

## Recommended Changes

### Change 1: Register hook in plugin.json

Add the Task matcher to `plugin.json` under PreToolUse:

```json
{
  "matcher": "Task",
  "hooks": [
    {
      "type": "command",
      "command": "${CLAUDE_PLUGIN_ROOT}/hooks/task_force_background.sh"
    }
  ]
}
```

### Change 2: Improved hook script

```bash
#!/bin/bash
# Force Task tool calls to background mode
# Workaround for: https://github.com/anthropics/claude-code/issues/16789
#
# TaskOutput returns raw JSONL instead of parsed responses. By forcing all
# Task calls to background mode, results arrive via <task-notification>
# which contains clean <result> tags.
#
# Config:
#   CLAUDE_TASK_FORCE_BG=0        — disable entirely
#   CLAUDE_TASK_FORCE_BG_DEBUG=1  — enable stderr logging

# Disable check (before any work)
[[ "${CLAUDE_TASK_FORCE_BG:-1}" == "0" ]] && exit 0

# jq required
command -v jq &>/dev/null || exit 0

INPUT=$(cat)

debug() { [[ "${CLAUDE_TASK_FORCE_BG_DEBUG:-0}" == "1" ]] && echo "task_force_bg: $*" >&2; }

# Defensive: verify this is actually a Task tool call
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
if [[ "$TOOL_NAME" != "Task" ]]; then
  debug "not a Task call (got: $TOOL_NAME), skip"
  exit 0
fi

# Skip if already backgrounded
if printf '%s' "$INPUT" | jq -e '.tool_input.run_in_background == true' &>/dev/null; then
  debug "already backgrounded, skip"
  exit 0
fi

# Skip resume calls (agent already running in background)
if printf '%s' "$INPUT" | jq -e '.tool_input.resume != null' &>/dev/null; then
  debug "resume call, skip"
  exit 0
fi

# Force background mode
# Note: updatedInput REPLACES tool_input entirely, so we merge with + to preserve all fields
RESULT=$(printf '%s' "$INPUT" | jq '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    updatedInput: (.tool_input + { run_in_background: true }),
    additionalContext: "Task auto-backgrounded (#16789). Results arrive via <task-notification>. Do NOT use TaskOutput — it returns raw JSONL."
  }
}' 2>/dev/null) || {
  debug "jq transform failed, allowing unmodified"
  exit 0
}

debug "forcing background mode"
printf '%s\n' "$RESULT"
```

Key improvements over both versions:
1. **`printf '%s'` instead of `echo`** -- avoids echo flag interpretation (`-e`, `-n`)
2. **Defensive `tool_name` check** -- safety net if matcher config is wrong
3. **jq failure handled** -- `|| { exit 0; }` on the transform = fail-open
4. **No `set -euo pipefail`** -- hooks must fail-open, not crash silently
5. **`2>/dev/null` on jq** -- suppresses parse errors from reaching Claude
6. **Final output via `printf` not `echo`** -- consistent, safe
7. **Comment documenting `updatedInput` replacement behavior** -- the critical gotcha from MEMORY.md

### Change 3: Optional TaskOutput warning hook (new file)

Create `hooks/task_output_warn.sh`:

```bash
#!/bin/bash
# Warn when TaskOutput is used (results arrive via notifications instead)
# Companion to task_force_background.sh

[[ "${CLAUDE_TASK_FORCE_BG:-1}" == "0" ]] && exit 0
command -v jq &>/dev/null || exit 0

# Return warning context without blocking
printf '%s\n' '{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": "TaskOutput returns raw JSONL (#16789). Wait for <task-notification> with <result> tag instead. The background agent will notify you when complete."
  }
}'
```

Register in plugin.json:
```json
{
  "matcher": "TaskOutput",
  "hooks": [
    {
      "type": "command",
      "command": "${CLAUDE_PLUGIN_ROOT}/hooks/task_output_warn.sh"
    }
  ]
}
```

### Change 4: Consolidate jq invocations (optional optimization)

The current design calls jq 3 times (tool_name check, background check, resume check, then transform). These can be merged into a single jq invocation for ~20ms savings:

```bash
RESULT=$(printf '%s' "$INPUT" | jq '
  # Skip conditions
  if .tool_input.run_in_background == true then empty
  elif .tool_input.resume != null then empty
  else
    {
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        updatedInput: (.tool_input + { run_in_background: true }),
        additionalContext: "Task auto-backgrounded (#16789). Results arrive via <task-notification>. Do NOT use TaskOutput — it returns raw JSONL."
      }
    }
  end
' 2>/dev/null) || exit 0

# jq outputs empty string for skip conditions
[[ -z "$RESULT" ]] && { debug "skipped (already bg or resume)"; exit 0; }

debug "forcing background mode"
printf '%s\n' "$RESULT"
```

This reduces 3 jq process spawns to 1. The `empty` filter produces no output, which we detect with `-z`.

**Trade-off:** Slightly less readable, but measurably faster. I'd keep the multi-call version for clarity unless profiling shows the hook is a bottleneck.

---

## Files to Modify

1. `/Users/yulong/code/dotfiles/claude/ai-safety-plugins/plugins/core-toolkit/.claude-plugin/plugin.json` -- add Task and TaskOutput matchers (also update the cache copy)
2. `/Users/yulong/code/dotfiles/claude/ai-safety-plugins/plugins/core-toolkit/hooks/task_force_background.sh` -- replace with improved version
3. `/Users/yulong/code/dotfiles/claude/ai-safety-plugins/plugins/core-toolkit/hooks/task_output_warn.sh` -- new file (optional)

## Plugin Cache Sync

Per MEMORY.md: plugin cache must be updated alongside source. After modifying files in `ai-safety-plugins/`, the cache at `~/.claude/plugins/cache/ai-safety-plugins/core-toolkit/1.0.0/` needs to reflect the changes. The plugin.json in cache is at:
`/Users/yulong/code/dotfiles/claude/plugins/cache/ai-safety-plugins/core-toolkit/1.0.0/.claude-plugin/plugin.json`
