#!/bin/bash
set -euo pipefail

# PreToolUse(Bash) hook: nudge agents toward faster Rust-based CLI tools
# Lightweight — only adds a message, never blocks.

input=$(cat)
command=$(echo "$input" | jq -r '.tool_input.command // ""')

# Quick exit if empty
[[ -z "$command" ]] && exit 0

nudge=""

# Extract the first word (the command being run)
first_word="${command%% *}"

# Check for slow tools with faster alternatives
case "$first_word" in
    grep)   nudge="Prefer \`rg\` (ripgrep) over \`grep\` — faster and better defaults." ;;
    find)   nudge="Prefer \`fd\` over \`find\` — faster, simpler syntax (e.g., \`fd -t f pattern\`)." ;;
    cat)    nudge="Prefer \`bat\` over \`cat\` for viewing files — syntax highlighting included." ;;
    sed)    nudge="Prefer \`sd\` over \`sed\` — simpler regex syntax (e.g., \`sd 'old' 'new' file\`)." ;;
esac

# No nudge needed
[[ -z "$nudge" ]] && exit 0

# Emit nudge as a message (doesn't block the tool call)
jq -n --arg msg "$nudge" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    message: $msg
  }
}'
