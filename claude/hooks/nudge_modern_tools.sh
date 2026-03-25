#!/bin/bash
set -euo pipefail

# PreToolUse(Bash) hook: nudge agents toward built-in tools and modern CLI.
# BLOCKS: grep/find/cat/head/tail/sed when used as standalone file operations
#         (built-in Grep/Glob/Read/Edit tools are strictly better for files)
# ALLOWS: same commands in pipelines/streams (no built-in equivalent)
# NUDGES: awk, curl, wget, ls, echo/printf redirection (soft suggestions)

input=$(cat)
command=$(echo "$input" | jq -r '.tool_input.command // ""')

# Quick exit if empty
[[ -z "$command" ]] && exit 0

block_reason=""
nudge=""

# Detect if a command appears as a standalone file operation vs pipeline usage.
# "grep pattern file" → block (use Grep tool)
# "git log | grep feat" → allow (stream filtering, no built-in equivalent)
# "find . -name foo" → block (use Glob tool)
# "cmd && find . -name foo" → block (still a file operation)

# Check if cmd appears ONLY after a pipe (stream usage = allow)
is_piped_only() {
    local cmd="$1"
    # Remove everything before pipes, check if cmd appears in non-piped positions
    # Strategy: split on | and check if cmd appears in the first segment or after && / ;
    local first_segment="${command%%|*}"
    # If command has no pipe at all, it's not piped
    [[ "$command" != *"|"* ]] && return 1
    # If cmd appears in the first segment (before any pipe), it's not pipe-only
    [[ "$first_segment" =~ (^|[&;[:space:]])$cmd([[:space:]]|$) ]] && return 1
    # cmd only appears after a pipe
    return 0
}

# Check if command word appears anywhere in the full command
has_cmd() {
    [[ "$command" =~ (^|[&|;[:space:]])$1([[:space:]]|$) ]]
}

# BLOCK: standalone file operations where built-in tools are strictly better.
# Skip if the command only appears after a pipe (stream processing).

if has_cmd grep && ! is_piped_only grep; then
    block_reason="Use the built-in **Grep** tool instead of \`grep\` for searching files. It's ripgrep-based, faster, and respects sandbox. For CLI: \`rg\`."
elif has_cmd find && ! is_piped_only find; then
    block_reason="Use the built-in **Glob** tool instead of \`find\` for finding files. It supports patterns like \`**/*.py\`. For CLI: \`fd\`."
elif has_cmd sed && ! is_piped_only sed; then
    block_reason="Use the built-in **Edit** tool instead of \`sed\` for file modifications. For stream editing: \`sd\`."
elif (has_cmd cat || has_cmd head || has_cmd tail) && ! is_piped_only cat && ! is_piped_only head && ! is_piped_only tail; then
    # Extra check: "cat <<" is heredoc, not file reading — allow it
    if [[ "$command" =~ cat[[:space:]]+\<\< ]]; then
        : # heredoc usage, skip
    else
        block_reason="Use the built-in **Read** tool instead of \`cat\`/\`head\`/\`tail\` for reading files. It supports \`offset\` and \`limit\` for partial reads. For CLI: \`bat\`."
    fi

# NUDGE: soft suggestions for commands with partial alternatives
elif has_cmd awk; then
    nudge="Consider the built-in **Grep** tool (extraction) or \`jq\` (structured data) over \`awk\`."
elif has_cmd curl; then
    nudge="Prefer **WebFetch** over \`curl\` — domain-gated, auditable, doesn't need Bash."
elif has_cmd wget; then
    nudge="Prefer **WebFetch** over \`wget\` — domain-gated, auditable, doesn't need Bash."
elif has_cmd ls; then
    nudge="Prefer \`eza\` over \`ls\` — better defaults, git integration, tree view (\`eza --tree\`)."
elif [[ "$command" =~ (echo|printf).*\>[^\&] ]]; then
    nudge="Prefer the built-in **Write** tool over shell redirection — auditable and handles encoding correctly."
fi

# Block: reject the tool call and force the agent to use the built-in
if [[ -n "$block_reason" ]]; then
    jq -n --arg reason "$block_reason" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        decision: "block",
        reason: $reason
      }
    }'
    exit 0
fi

# Nudge: informational message, doesn't block
if [[ -n "$nudge" ]]; then
    jq -n --arg msg "$nudge" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        message: $msg
      }
    }'
    exit 0
fi
