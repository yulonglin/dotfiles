#!/bin/bash
# PreToolUse:Bash hook — supply chain warning on package install commands
set -euo pipefail

command=$(jq -r '.tool_input.command // ""')
[[ -z "$command" ]] && exit 0

case "$command" in
    npm\ install*|npm\ i\ *|pnpm\ install*|pnpm\ add*|bun\ add*|bun\ install*) ;;
    pip\ install*|pip3\ install*|uv\ pip\ install*|uv\ add*|python*\ -m\ pip\ install*) ;;
    *) exit 0 ;;
esac

jq -n '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    message: "[Supply Chain] Check package age, downloads, and maintainer count before installing. See rules/supply-chain-security.md for quarantine override syntax."
  }
}'
