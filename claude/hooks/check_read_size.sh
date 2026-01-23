#!/bin/bash
# PreToolUse hook: Warn/block reading large files without offset/limit
# Prevents subagents from loading entire 1600+ line files into context
#
# Environment variables:
#   CLAUDE_READ_STRICT=1     - Block reads instead of warn (default: warn only)
#   CLAUDE_READ_THRESHOLD=N  - Override line threshold (default: 500)

# Require jq - warn if missing (fail open but notify)
if ! command -v jq >/dev/null 2>&1; then
    echo '{"decision": "allow", "systemMessage": "⚠️ check_read_size.sh: jq not installed, hook disabled"}'
    exit 0
fi

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""')

# Only process Read tool
if [ "$TOOL_NAME" != "Read" ]; then
    exit 0
fi

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""')
LIMIT=$(echo "$INPUT" | jq -r '.tool_input.limit // ""')

# Skip if not a file
if [ ! -f "$FILE_PATH" ]; then
    exit 0
fi

# Check file size (line count) - skip binary files
if file --mime-encoding "$FILE_PATH" 2>/dev/null | grep -q binary; then
    exit 0
fi

LINE_COUNT=$(wc -l < "$FILE_PATH" 2>/dev/null | tr -d ' ')

# Defensive: ensure we got a valid number
if [ -z "$LINE_COUNT" ] || ! [ "$LINE_COUNT" -eq "$LINE_COUNT" ] 2>/dev/null; then
    exit 0
fi

# Configurable threshold (default 500 lines)
THRESHOLD="${CLAUDE_READ_THRESHOLD:-500}"

# If limit is set, allow it
if [ -n "$LIMIT" ] && [ "$LIMIT" != "null" ]; then
    exit 0
fi

# Allow small files
if [ "$LINE_COUNT" -lt "$THRESHOLD" ]; then
    exit 0
fi

# Strict mode: block the read (use jq for safe JSON escaping)
if [ "${CLAUDE_READ_STRICT:-0}" = "1" ]; then
    jq -n \
        --arg lines "$LINE_COUNT" \
        --arg threshold "$THRESHOLD" \
        --arg path "$FILE_PATH" \
        '{
            decision: "block",
            reason: "BLOCKED: File has \($lines) lines (threshold: \($threshold)). Use Grep to find relevant sections, then Read with limit/offset. File: \($path)"
        }'
    exit 0
fi

# Default: warn but allow (use jq for safe JSON escaping)
jq -n \
    --arg lines "$LINE_COUNT" \
    --arg threshold "$THRESHOLD" \
    --arg path "$FILE_PATH" \
    '{
        decision: "allow",
        systemMessage: "⚠️ CONTEXT WARNING: Reading \($lines)-line file without limit param. Consider:\n- Using Grep to find relevant sections first\n- Adding limit/offset params to Read (e.g., limit: 100)\n- For exploration: search with Glob/Grep before reading\nFile: \($path)"
    }'
