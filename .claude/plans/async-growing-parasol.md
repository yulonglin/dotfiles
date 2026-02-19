# Fix Task Output Raw JSONL Bug

## Context

Task tool returns raw JSONL conversation transcripts instead of parsed agent responses. Two upstream Claude Code bugs cause this:

1. **[#16789](https://github.com/anthropics/claude-code/issues/16789)** — Synchronous Task/TaskOutput returns raw JSONL. Partially fixed in v2.1.7: the notification path (`<task-notification>` with `<result>` tag) works, but the sync path does not. No full fix as of v2.1.44.

2. **[#24181](https://github.com/anthropics/claude-code/issues/24181)** — `classifyHandoffIfNeeded is not defined` crash on agent completion. Work completes but status shows "failed". No fix as of v2.1.44.

The `task_force_background.sh` hook was the **correct workaround** — forcing all Task calls to background routes results through the clean notification path. I incorrectly removed it last session. This plan restores and hardens it, incorporating feedback from 4 review agents (tooling-engineer, code-reviewer, codex-reviewer, gemini-cli).

## Changes

### 1. Rewrite `task_force_background.sh` (hardened)

**Files:** source + cache
- `~/.claude/ai-safety-plugins/plugins/core-toolkit/hooks/task_force_background.sh`
- `~/.claude/plugins/cache/ai-safety-plugins/core-toolkit/1.0.0/hooks/task_force_background.sh`

```bash
#!/bin/bash
# Force Task tool calls to background mode
# Workaround for: https://github.com/anthropics/claude-code/issues/16789
#
# Config:
#   CLAUDE_TASK_FORCE_BG=0        — disable entirely
#   CLAUDE_TASK_FORCE_BG_DEBUG=1  — enable stderr logging

[[ "${CLAUDE_TASK_FORCE_BG:-1}" == "0" ]] && exit 0
command -v jq &>/dev/null || exit 0

INPUT=$(cat)

debug() { [[ "${CLAUDE_TASK_FORCE_BG_DEBUG:-0}" == "1" ]] && printf 'task_force_bg: %s\n' "$*" >&2; }

# Validate JSON input
if ! printf '%s' "$INPUT" | jq -e '.' &>/dev/null; then
  debug "invalid JSON input, skip"
  exit 0
fi

# Defensive: verify this is a Task tool call (in case matcher misconfigured)
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
# Note: updatedInput REPLACES tool_input entirely — must merge with + to preserve all fields
# (.tool_input // {}) guards against null tool_input (same bug class as the jq -n fix)
RESULT=$(printf '%s' "$INPUT" | jq '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    updatedInput: ((.tool_input // {}) + { run_in_background: true }),
    additionalContext: "Task auto-backgrounded (#16789). Results arrive via <task-notification>. Do NOT use TaskOutput — it returns raw JSONL. Agents may show failed due to #24181 — verify output exists before retrying."
  }
}' 2>/dev/null) || {
  debug "jq transform failed, allowing unmodified"
  exit 0
}

debug "forcing background mode"
printf '%s\n' "$RESULT"
```

**Changes from original (synthesized from all 4 reviews):**

| Change | Source |
|--------|--------|
| Remove `set -euo pipefail` | code-reviewer, codex-reviewer, tooling-engineer |
| `printf '%s'` instead of `echo` | tooling-engineer (echo misinterprets `-e`/`-n` flags) |
| JSON validation early-exit | codex-reviewer (malformed input → silent death) |
| Defensive `tool_name` check | tooling-engineer (matcher misconfiguration guard) |
| `(.tool_input // {})` null guard | codex-reviewer (null + object = object, loses fields) |
| `|| { exit 0; }` jq fallback | all (fail-open, not fail-closed) |
| Mention `#24181` in additionalContext | gemini-cli (prevent unnecessary retry on "failed") |
| Debug logging via env var | all |

### 2. Create `task_output_warn.sh` (new — advisory)

**Files:** source + cache
- `~/.claude/ai-safety-plugins/plugins/core-toolkit/hooks/task_output_warn.sh`
- `~/.claude/plugins/cache/ai-safety-plugins/core-toolkit/1.0.0/hooks/task_output_warn.sh`

```bash
#!/bin/bash
# Warn when TaskOutput is used — results arrive via notifications instead
# Companion to task_force_background.sh
# See: https://github.com/anthropics/claude-code/issues/16789

[[ "${CLAUDE_TASK_FORCE_BG:-1}" == "0" ]] && exit 0

printf '%s\n' '{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": "TaskOutput returns raw JSONL (#16789). Wait for <task-notification> with <result> tag instead. The background agent will notify you when complete."
  }
}'
```

Advisory only (no `updatedInput`, no blocking). Source: tooling-engineer recommendation.

### 3. Re-register hooks in plugin.json

**Files:** source + cache
- `~/.claude/ai-safety-plugins/plugins/core-toolkit/.claude-plugin/plugin.json`
- `~/.claude/plugins/cache/ai-safety-plugins/core-toolkit/1.0.0/.claude-plugin/plugin.json`

Add to PreToolUse array:
```json
{
  "matcher": "Task",
  "hooks": [
    {
      "type": "command",
      "command": "${CLAUDE_PLUGIN_ROOT}/hooks/task_force_background.sh"
    }
  ]
},
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

### 4. Harden `auto_background.sh` further

**Files:** source + cache (already has jq -n → merge fix from last session)
- `~/.claude/ai-safety-plugins/plugins/workflow-toolkit/hooks/auto_background.sh`
- `~/.claude/plugins/cache/ai-safety-plugins/workflow-toolkit/1.0.0/hooks/auto_background.sh`

Additional fixes from codex-reviewer:
- Add `(.tool_input // {})` null guard on merge (line ~110)
- Add JSON validation early-exit after `INPUT=$(cat)`
- Validate TIMEOUT is numeric before arithmetic comparison (bash 3.2 crash)
- Use `printf '%s'` instead of `echo` throughout

### 5. Sync source → cache

All changes must be applied to both source and cache. Per MEMORY.md: "plugin cache must be updated alongside source — Claude Code runs from cache, not the source repo."

**Future improvement (P1):** Investigate symlinking cache → source to eliminate sync as a failure mode. Test: replace cache dir with symlink to source and check if Claude Code follows it. (gemini-cli recommendation)

## Verification

1. Restart Claude Code (required for plugin.json changes)
2. Call Task tool → should see "Async agent launched" (not raw JSONL)
3. Wait for `<task-notification>` → should contain clean `<result>` tag
4. Call Task with `resume: <id>` → hook should skip (not re-background)
5. Verify TaskOutput shows advisory warning if called
6. Set `CLAUDE_TASK_FORCE_BG=0` → verify escape hatch works (sync execution)
7. Optional: `CLAUDE_TASK_FORCE_BG_DEBUG=1` to check stderr logging

## Known Limitations (Upstream — No User Fix)

- `classifyHandoffIfNeeded` crash (#24181) causes agents to show `status: failed` — work is completed, status is misleading
- TaskOutput tool path remains broken in v2.1.44 — must avoid entirely
- `auto_background.sh` regex matching is string-level, not semantic — commands that *mention* patterns (in quotes, comments) can false-positive (codex-reviewer: design limitation, not easily fixable)

## Sources

- [#16789: TaskOutput raw JSONL](https://github.com/anthropics/claude-code/issues/16789) — partially fixed v2.1.7
- [#24181: classifyHandoffIfNeeded](https://github.com/anthropics/claude-code/issues/24181) — open, no fix
- [Claude Code releases](https://releasebot.io/updates/anthropic/claude-code) — v2.1.44 is latest (Feb 17, 2026)
