#!/bin/bash

# Read JSON from stdin
INPUT=$(cat)

# Extract fields
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // "unknown"')
TIMESTAMP=$(date -Iseconds)
EXIT_CODE=$(echo "$INPUT" | jq -r '.tool_response.exit_code // ""')
PHASE=$1  # "START" or "END"

# Get working directory from tool input, fallback to CLAUDE_PROJECT_DIR
CWD=$(echo "$INPUT" | jq -r '.tool_input.cwd // empty')
if [ -z "$CWD" ]; then
    CWD="${CLAUDE_PROJECT_DIR:-$(pwd)}"
fi

# Extract project name (basename of project dir)
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$CWD}"
PROJECT_NAME=$(basename "$PROJECT_DIR")

# Get git branch if in a git repo
BRANCH=""
if git -C "$CWD" rev-parse --abbrev-ref HEAD >/dev/null 2>&1; then
    BRANCH=$(git -C "$CWD" rev-parse --abbrev-ref HEAD 2>/dev/null)
fi

# Log file locations
LOG_DIR="${CLAUDE_PROJECT_DIR}/.claude"
mkdir -p "$LOG_DIR"
HUMAN_LOG="${LOG_DIR}/bash-history.log"
JSONL_LOG="${LOG_DIR}/bash-history.jsonl"

# Build JSONL entry using jq for proper escaping (-c for compact/single-line)
build_json() {
    local exit_val="$1"
    if [ -n "$BRANCH" ]; then
        jq -nc --arg ts "$TIMESTAMP" \
               --arg cmd "$COMMAND" \
               --arg cwd "$CWD" \
               --arg branch "$BRANCH" \
               --argjson exit "$exit_val" \
               '{ts: $ts, exit: $exit, cmd: $cmd, cwd: $cwd, branch: $branch}'
    else
        jq -nc --arg ts "$TIMESTAMP" \
               --arg cmd "$COMMAND" \
               --arg cwd "$CWD" \
               --argjson exit "$exit_val" \
               '{ts: $ts, exit: $exit, cmd: $cmd, cwd: $cwd}'
    fi
}

# Write JSONL entry (both START and END phases)
if [ "$PHASE" = "START" ]; then
    build_json "null" >> "$JSONL_LOG"
else
    # END phase: include exit code
    build_json "${EXIT_CODE:-null}" >> "$JSONL_LOG"

    # Write human-readable entry (END phase only)
    TIME_ONLY=$(date +%H:%M)
    if [ "$EXIT_CODE" = "0" ] || [ -z "$EXIT_CODE" ]; then
        STATUS="[OK]"
    else
        STATUS="[!${EXIT_CODE}]"
    fi

    # Format: HH:MM [OK] project (branch) | command
    if [ -n "$BRANCH" ]; then
        printf '%s %-5s %s (%s) | %s\n' "$TIME_ONLY" "$STATUS" "$PROJECT_NAME" "$BRANCH" "$COMMAND" >> "$HUMAN_LOG"
    else
        printf '%s %-5s %s | %s\n' "$TIME_ONLY" "$STATUS" "$PROJECT_NAME" "$COMMAND" >> "$HUMAN_LOG"
    fi
fi