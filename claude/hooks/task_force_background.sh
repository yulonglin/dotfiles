#!/bin/bash
# Claude Code PreToolUse hook: Force Task tool calls to background mode
# Routes all subagent calls through the notification path, avoiding raw JSONL
# transcript dumps in synchronous TaskOutput responses.
# See: https://github.com/anthropics/claude-code/issues/16789
#
# Config env vars:
#   CLAUDE_TASK_FORCE_BG=0  — disable entirely
#
# Exit codes:
#   0 - Allow (with optional JSON output on stdout)

set -euo pipefail

# --- Early exits ---

# Disabled?
[[ "${CLAUDE_TASK_FORCE_BG:-1}" == "0" ]] && exit 0

# jq required for JSON parsing/output
if ! command -v jq &>/dev/null; then
  echo "task_force_background: jq not found, skipping" >&2
  exit 0
fi

INPUT=$(cat)

# Already backgrounded
if echo "$INPUT" | jq -e '.tool_input.run_in_background == true' &>/dev/null; then
  exit 0
fi

# Resuming an existing agent — already background
if echo "$INPUT" | jq -e '.tool_input.resume != null' &>/dev/null; then
  exit 0
fi

# --- Force background ---

jq -n '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    updatedInput: { run_in_background: true },
    additionalContext: "Task auto-backgrounded to avoid raw JSONL dumps (#16789). Wait for <task-notification> with <result> tag. Do NOT poll with TaskOutput tool — results arrive automatically."
  }
}'
