#!/bin/bash
set -euo pipefail

# PreToolUse(Bash) hook: nudge agents toward built-in tools and modern CLI.
# BLOCKS: grep/find/cat/head/tail/sed when used as standalone file operations
#         (built-in Grep/Glob/Read/Edit tools are strictly better for files)
# REDIRECTS: "ask"-category commands that have auto-allowed alternatives
#            (blocks with specific suggestion, avoids permission prompt entirely)
# ALLOWS: same commands in pipelines/streams (no built-in equivalent)
# NUDGES: awk, curl (complex), wget (complex), ls, echo/printf redirection (soft suggestions)
# BLOCKS: curl/wget simple GETs (WebFetch is strictly better, no permission prompt)

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
# -exec/-execdir/--exec flags: only block when find or fd is the command using them.
# Avoids false positives on docker exec, kubectl exec, git bisect --exec, etc.
elif (has_cmd find || has_cmd fd) && [[ "$command" =~ [[:space:]](-exec(dir)?|--exec(-batch)?)[[:space:]] ]] && ! is_piped_only find && ! is_piped_only fd; then
    block_reason="**\`-exec\`** flags require confirmation. Use the built-in **Glob** tool + a \`for\` loop, or pipe to \`while IFS= read -r\`."
elif has_cmd find && ! is_piped_only find; then
    block_reason="Use the built-in **Glob** tool instead of \`find\` for finding files. It supports patterns like \`**/*.py\`. For CLI: \`fd\`."
elif has_cmd fd && ! is_piped_only fd && [[ "$command" =~ [[:space:]](-[xX])([[:space:]]|$) ]]; then
    block_reason="**\`fd -x/-X\`** (exec shorthand) requires confirmation. Use \`fd\` piped to \`while IFS= read -r\` instead."
elif has_cmd sed && ! is_piped_only sed; then
    block_reason="Use the built-in **Edit** tool instead of \`sed\` for file modifications. For stream editing: \`sd\`."
elif (has_cmd cat || has_cmd head || has_cmd tail) && ! is_piped_only cat && ! is_piped_only head && ! is_piped_only tail; then
    # Extra check: "cat <<" is heredoc, not file reading — allow it
    if [[ "$command" =~ cat[[:space:]]+\<\< ]]; then
        : # heredoc usage, skip
    else
        block_reason="Use the built-in **Read** tool instead of \`cat\`/\`head\`/\`tail\` for reading files. It supports \`offset\` and \`limit\` for partial reads. For CLI: \`bat\`."
    fi

# REDIRECT: "ask"-category commands with clear auto-allowed alternatives.
# Blocks with a specific suggestion, preventing the permission prompt entirely.
# These would otherwise trigger the "ask" permission list in settings.json.

# python -c is allowed — inline checks are routine for research workflows
# elif [[ "$command" =~ ^(python3?|uv\ run\ python3?)\ -c\  ]] && ! is_piped_only python && ! is_piped_only python3; then
#     block_reason="**\`python -c\`** requires confirmation. Write the code to a temp file with **Write** tool, then run \`python \$TMPDIR/check.py\` (auto-allowed)."
elif [[ "$command" =~ ^node\ -e\  ]]; then
    block_reason="**\`node -e\`** requires confirmation. Write the code to a temp file with **Write** tool, then run \`node \$TMPDIR/check.js\` (auto-allowed)."
elif [[ "$command" =~ ^(perl\ -e|ruby\ -e)\  ]]; then
    block_reason="**Inline eval** requires confirmation. Write the code to a temp file with **Write** tool, then run the file directly (auto-allowed)."
elif [[ "$command" =~ ^timeout\  ]]; then
    block_reason="**\`timeout\`** requires confirmation. Use the Bash tool's \`timeout\` parameter instead (e.g., \`timeout: 30000\` for 30s). It's built-in and auto-allowed."
elif [[ "$command" =~ ^nohup\  ]]; then
    block_reason="**\`nohup\`** requires confirmation. Use the Bash tool's \`run_in_background: true\` parameter instead — it's built-in and auto-allowed."
elif [[ "$command" =~ ^env\  ]] && ! is_piped_only env; then
    block_reason="**\`env\`** requires confirmation. Set environment variables with \`export VAR=val\` then run the command directly, or use \`VAR=val command\` syntax (auto-allowed)."
elif has_cmd xargs && ! is_piped_only xargs; then
    block_reason="**\`xargs\`** requires confirmation. Use a shell \`for\` loop or \`while IFS= read -r\` instead (auto-allowed)."

# NUDGE: soft suggestions for commands with partial alternatives
elif has_cmd awk; then
    nudge="Consider the built-in **Grep** tool (extraction) or \`jq\` (structured data) over \`awk\`."
elif has_cmd curl && ! is_piped_only curl; then
    # Block simple GETs (WebFetch is strictly better), nudge complex usage
    if [[ "$command" =~ curl[[:space:]]+(-s[[:space:]]+|-S[[:space:]]+|-sS[[:space:]]+|-Ss[[:space:]]+)*https?:// ]] \
       && ! [[ "$command" =~ curl.*[[:space:]](-[a-zA-Z]*[oOHdXu]|--output|--header|--data|--request|--user|--upload-file|-fsSL|-LO) ]]; then
        block_reason="Use the built-in **WebFetch** tool instead of \`curl\` for simple GETs — auto-allowed, no permission prompt. Use \`curl\` for downloads (\`-o\`), installs (\`-fsSL\`), or API calls (\`-H\`/\`-d\`)."
    else
        nudge="**\`curl\`** requires confirmation. Prefer **WebFetch** tool when fetching page/API content. curl is fine for binary downloads, installs, and complex requests."
    fi
elif has_cmd wget && ! is_piped_only wget; then
    if [[ "$command" =~ wget[[:space:]]+(-q[[:space:]]+|-nv[[:space:]]+)*https?:// ]] \
       && ! [[ "$command" =~ wget.*[[:space:]](-[a-zA-Z]*[oO]|--output-document|--header|--post-data) ]]; then
        block_reason="Use the built-in **WebFetch** tool instead of \`wget\` for simple GETs — auto-allowed, no permission prompt."
    else
        nudge="**\`wget\`** requires confirmation. Prefer **WebFetch** tool when fetching page/API content."
    fi
elif has_cmd xargs && is_piped_only xargs; then
    nudge="**\`xargs\`** in pipes requires confirmation. Consider \`while IFS= read -r\` as an auto-allowed alternative."
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
        permissionDecision: "deny",
        permissionDecisionReason: $reason
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
