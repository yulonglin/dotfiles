#!/bin/sh

# Read JSON from stdin
INPUT=$(cat)

# Extract fields
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // "unknown"')
TIMESTAMP=$(date -Iseconds)
EXIT_CODE=$(echo "$INPUT" | jq -r '.tool_response.exit_code // ""')
PHASE=$1  # "START" or "END"

# Generate session ID (hash of timestamp + command)
# Use md5 on macOS, md5sum on Linux
if command -v md5 > /dev/null 2>&1; then
    SESSION_ID=$(printf "%s%s" "$TIMESTAMP" "$COMMAND" | md5 | cut -c1-8)
else
    SESSION_ID=$(printf "%s%s" "$TIMESTAMP" "$COMMAND" | md5sum | cut -d' ' -f1 | cut -c1-8)
fi

# Log file location
LOG_FILE="${CLAUDE_PROJECT_DIR}/.claude/bash-commands.log"
mkdir -p "$(dirname "$LOG_FILE")"

# Write log entry
if [ "$PHASE" = "START" ]; then
    echo "${PHASE} | ${SESSION_ID} | ${TIMESTAMP} | ${COMMAND}" >> "$LOG_FILE"
else
    echo "${PHASE} | ${SESSION_ID} | ${TIMESTAMP} | exit:${EXIT_CODE} | ${COMMAND}" >> "$LOG_FILE"
fi