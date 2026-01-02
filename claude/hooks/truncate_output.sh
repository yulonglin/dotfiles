#!/bin/sh
# PostToolUse hook: Truncate long bash outputs to prevent context pollution
# Outputs JSON with suppressOutput + systemMessage for long outputs

# Check for jq dependency
if ! command -v jq >/dev/null 2>&1; then
    exit 0
fi

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

# Truncate stdout: keep first 15 + last 30 lines
if [ "${#STDOUT}" -gt 1500 ]; then
    HEAD=$(printf '%s' "$STDOUT" | head -n 15)
    TAIL=$(printf '%s' "$STDOUT" | tail -n 30)
    TRUNCATED_STDOUT="${HEAD}

... [${#STDOUT} chars truncated] ...

${TAIL}"
else
    TRUNCATED_STDOUT="$STDOUT"
fi

# Truncate stderr: keep last 20 lines for errors
if [ "${#STDERR}" -gt 500 ]; then
    TRUNCATED_STDERR=$(printf '%s' "$STDERR" | tail -n 20)
    TRUNCATED_STDERR="... [stderr truncated] ...

${TRUNCATED_STDERR}"
else
    TRUNCATED_STDERR="$STDERR"
fi

# Build summary message
SUMMARY="Command: ${COMMAND}
Exit code: ${EXIT_CODE}
Output (truncated from ${TOTAL_LEN} chars):

${TRUNCATED_STDOUT}"

# Include stderr if present (especially important for errors)
if [ -n "$TRUNCATED_STDERR" ]; then
    SUMMARY="${SUMMARY}

--- stderr ---
${TRUNCATED_STDERR}"
fi

# Escape for JSON
SUMMARY_ESCAPED=$(printf '%s' "$SUMMARY" | jq -Rs .)

# Output JSON to suppress original and replace with summary
printf '{"suppressOutput": true, "systemMessage": %s}\n' "$SUMMARY_ESCAPED"
