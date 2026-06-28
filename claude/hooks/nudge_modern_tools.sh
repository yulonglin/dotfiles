#!/bin/bash
set -euo pipefail

# PreToolUse(Bash) hook: nudge agents toward built-in tools and modern CLI.
# This hook ONLY emits soft nudges — it never blocks/denies a command. Every
# suggestion is informational; the agent stays free to run the command as-is.
# NUDGES (file ops with better built-ins): grep→Grep, find→Glob, sed→Edit,
#         cat/head/tail→Read — only when used as standalone file operations.
# NUDGES ("ask"-category commands with auto-allowed alternatives): node -e,
#         perl/ruby -e, timeout, nohup, env, xargs, find -exec, fd -x, bare
#         curl/wget GETs — suggests the prompt-free path without blocking.
# NUDGES (modern CLI / built-ins): awk, curl, wget, ls, echo/printf redirection.
# ALLOWS silently: same file-op commands in pipelines/streams (no built-in equivalent).

input=$(cat)
command=$(echo "$input" | jq -r '.tool_input.command // ""')

# Quick exit if empty
[[ -z "$command" ]] && exit 0

LOG_PATH="${HOME}/.cache/claude/nudge-modern.log"
MAX_LOG_BYTES=$((512 * 1024))
log_decision() {
    local decision="$1" reason="$2"
    mkdir -p "$(dirname "$LOG_PATH")" 2>/dev/null || return 0
    if [[ -f "$LOG_PATH" ]]; then
        local size
        size=$(stat -f%z "$LOG_PATH" 2>/dev/null || stat -c%s "$LOG_PATH" 2>/dev/null || echo 0)
        if (( size > MAX_LOG_BYTES )); then
            tail -c $((MAX_LOG_BYTES / 2)) "$LOG_PATH" > "$LOG_PATH.tmp" && mv "$LOG_PATH.tmp" "$LOG_PATH"
        fi
    fi
    local ts cmd_short
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    cmd_short=$(printf '%s' "$command" | tr '\n' ' ' | cut -c1-200)
    printf '%s %s | %s | %s\n' "$ts" "$decision" "$cmd_short" "$reason" >> "$LOG_PATH"
}

nudge=""

# Detect if a command appears as a standalone file operation vs pipeline usage.
# "grep pattern file" → nudge (suggest Grep tool)
# "git log | grep feat" → quiet (stream filtering, no built-in equivalent)
# "find . -name foo" → nudge (suggest Glob tool)
# "cmd && find . -name foo" → nudge (still a file operation)

# Check if cmd appears ONLY after a pipe (stream usage = quiet)
is_piped_only() {
    local cmd="$1"
    # Check if cmd ONLY appears in pipe-receiving positions (after |).
    # Must also check for && / ; in later segments that start a new standalone command.
    [[ "$command" != *"|"* ]] && return 1
    # Split on | and check each segment. First segment is always standalone.
    # Later segments: the part after && or ; is also standalone.
    local IFS='|' seg i=0
    for seg in $command; do
        if (( i == 0 )); then
            # First segment: any match means not pipe-only
            [[ "$seg" =~ (^|[&;[:space:]])$cmd([[:space:]]|$) ]] && return 1
        else
            # Later segments: check for cmd after && or ; (standalone position)
            local after_chain
            # Extract parts after && or ; within this segment
            after_chain=$(echo "$seg" | sed -E 's/^[^&;]*(&&|;)//')
            [[ "$after_chain" != "$seg" && "$after_chain" =~ (^|[[:space:]])$cmd([[:space:]]|$) ]] && return 1
        fi
        ((i++))
    done
    return 0
}

# Check if command word appears anywhere in the full command
has_cmd() {
    [[ "$command" =~ (^|[\&\|\;()])[[:space:]]*$1([[:space:]]|$) ]]
}

# NUDGE: standalone file operations where built-in tools are strictly better.
# Skip if the command only appears after a pipe (stream processing).

if has_cmd grep && ! is_piped_only grep; then
    nudge="Prefer the built-in **Grep** tool over \`grep\` for searching files — ripgrep-based, faster, sandbox-aware. For CLI: \`rg\`."
# -exec/-execdir/--exec flags: only nudge when find or fd is the command using them.
# Avoids false positives on docker exec, kubectl exec, git bisect --exec, etc.
elif (has_cmd find || has_cmd fd) && [[ "$command" =~ [[:space:]](-exec(dir)?|--exec(-batch)?)[[:space:]] ]] && ! is_piped_only find && ! is_piped_only fd; then
    nudge="**\`-exec\`** flags trigger a permission prompt. Consider the built-in **Glob** tool + a \`for\` loop, or pipe to \`while IFS= read -r\` (auto-allowed)."
elif has_cmd find && ! is_piped_only find; then
    nudge="Prefer the built-in **Glob** tool over \`find\` for finding files — supports patterns like \`**/*.py\`. For CLI: \`fd\`."
elif has_cmd fd && ! is_piped_only fd && [[ "$command" =~ [[:space:]](-[xX])([[:space:]]|$) ]]; then
    nudge="**\`fd -x/-X\`** (exec shorthand) triggers a permission prompt. Consider \`fd\` piped to \`while IFS= read -r\` instead (auto-allowed)."
elif has_cmd sed && ! is_piped_only sed; then
    nudge="Prefer the built-in **Edit** tool over \`sed\` for file modifications. For stream editing: \`sd\`."
elif (has_cmd cat && ! is_piped_only cat) || (has_cmd head && ! is_piped_only head) || (has_cmd tail && ! is_piped_only tail); then
    # Extra check: "cat <<" or "cat > file <<" is heredoc, not file reading — skip it
    if [[ "$command" =~ cat[[:space:]].*\<\< ]]; then
        : # heredoc usage, skip
    else
        nudge="Prefer the built-in **Read** tool over \`cat\`/\`head\`/\`tail\` for reading files — supports \`offset\`/\`limit\` for partial reads. For CLI: \`bat\`."
    fi

# NUDGE: "ask"-category commands with clear auto-allowed alternatives.
# Suggests the prompt-free path; the command still runs (subject to normal permissions).

# python -c is allowed — inline checks are routine for research workflows
# elif [[ "$command" =~ ^(python3?|uv\ run\ python3?)\ -c\  ]] && ! is_piped_only python && ! is_piped_only python3; then
#     nudge="**\`python -c\`** triggers a permission prompt. Consider writing the code to a temp file with **Write**, then run \`python \$TMPDIR/check.py\` (auto-allowed)."
elif [[ "$command" =~ ^node\ -e\  ]]; then
    nudge="**\`node -e\`** triggers a permission prompt. Consider writing the code to a temp file with **Write**, then run \`node \$TMPDIR/check.js\` (auto-allowed)."
elif [[ "$command" =~ ^(perl\ -e|ruby\ -e)\  ]]; then
    nudge="**Inline eval** triggers a permission prompt. Consider writing the code to a temp file with **Write**, then run the file directly (auto-allowed)."
elif [[ "$command" =~ ^timeout\  ]]; then
    nudge="**\`timeout\`** triggers a permission prompt. Consider the Bash tool's \`timeout\` parameter instead (e.g., \`timeout: 30000\` for 30s) — built-in and auto-allowed."
elif [[ "$command" =~ ^nohup\  ]]; then
    nudge="**\`nohup\`** triggers a permission prompt. Consider the Bash tool's \`run_in_background: true\` parameter instead — built-in and auto-allowed."
elif [[ "$command" =~ ^env\  ]] && ! is_piped_only env; then
    nudge="**\`env\`** triggers a permission prompt. Consider \`export VAR=val\` then run the command directly, or use \`VAR=val command\` syntax (auto-allowed)."
elif has_cmd xargs && ! is_piped_only xargs; then
    nudge="**\`xargs\`** triggers a permission prompt. Consider a shell \`for\` loop or \`while IFS= read -r\` instead (auto-allowed)."

# NUDGE: soft suggestions for commands with partial alternatives
elif has_cmd awk; then
    nudge="Consider the built-in **Grep** tool (extraction) or \`jq\` (structured data) over \`awk\`."
elif has_cmd curl && ! is_piped_only curl; then
    # Whitelist approach: nudge harder on bare GETs (URL + optional -s/-S/-sS/-Ss, nothing else).
    # Anything with extra flags gets the lighter nudge — no false positives on complex usage.
    if [[ "$command" =~ ^[[:space:]]*curl[[:space:]]+(-[sSq]+[[:space:]]+)*\"?https?://[^[:space:]]+\"?[[:space:]]*$ ]]; then
        nudge="Consider the built-in **WebFetch** tool over \`curl\` for simple GETs — auto-allowed, no permission prompt. Use \`curl\` for downloads (\`-o\`), installs (\`-fsSL\`), or API calls (\`-H\`/\`-d\`)."
    else
        nudge="**\`curl\`** triggers a permission prompt. Prefer **WebFetch** when fetching page/API content. curl is fine for binary downloads, installs, and complex requests."
    fi
elif has_cmd wget && ! is_piped_only wget; then
    # Same whitelist approach for wget
    if [[ "$command" =~ ^[[:space:]]*wget[[:space:]]+(-[qnv]+[[:space:]]+)*\"?https?://[^[:space:]]+\"?[[:space:]]*$ ]]; then
        nudge="Consider the built-in **WebFetch** tool over \`wget\` for simple GETs — auto-allowed, no permission prompt."
    else
        nudge="**\`wget\`** triggers a permission prompt. Prefer **WebFetch** when fetching page/API content."
    fi
elif has_cmd xargs && is_piped_only xargs; then
    nudge="**\`xargs\`** in pipes triggers a permission prompt. Consider \`while IFS= read -r\` as an auto-allowed alternative."
elif has_cmd ls; then
    nudge="Prefer \`eza\` over \`ls\` — better defaults, git integration, tree view (\`eza --tree\`)."
elif [[ "$command" =~ (echo|printf).*\>[^\&] ]]; then
    nudge="Prefer the built-in **Write** tool over shell redirection — auditable and handles encoding correctly."
fi

# Nudge: informational message only — never blocks the command.
if [[ -n "$nudge" ]]; then
    log_decision "NUDGE" "$nudge"
    jq -n --arg msg "$nudge" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        message: $msg
      }
    }'
    exit 0
fi
