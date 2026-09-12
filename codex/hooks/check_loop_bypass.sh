#!/bin/bash
# PreToolUse hook: Inspect for/while loop bodies for denied command patterns.
#
# Prevents bypass of deny rules via: for x in 1; do DENIED_CMD; done
# Exit 0 = allow, exit 2 = block (stderr shown to user)

set -euo pipefail

command=$(jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[[ -z "$command" ]] && exit 0

# Only inspect commands starting with for/while loops
if [[ ! "$command" =~ ^(for|while)[[:space:]] ]]; then
  exit 0
fi

# Inspect everything after the first standalone `do`, including multiline bodies.
# Retain the original literal-pattern policy, including quoted command text.
loop_body_pattern='(^|[[:space:];])do([[:space:];]|$)(.*)'
if [[ "$command" =~ $loop_body_pattern ]]; then
  body=${BASH_REMATCH[3]}
else
  exit 0
fi

[[ -z "$body" ]] && exit 0

# Denied patterns — must stay in sync with settings.json deny list
denied_patterns=(
  "bash -c "
  "sh -c "
  "zsh -c "
  "eval "
  "exec "
  "rm -rf "
  "rm -r "
  "sudo "
  "dd "
  "git push --force"
  "git push -f "
  "git push --force-with-lease"
  "git reset --hard"
  "git clean "
  "git checkout -- "
  "git branch -D "
  "mkfs "
  "fdisk "
  "wipefs "
  "shutdown "
  "reboot "
  "halt "
  "shred "
  "truncate "
  "chmod -R 777"
  "chmod 000"
  "chown -R "
  "xargs sh "
  "xargs bash "
)

for pattern in "${denied_patterns[@]}"; do
  if printf '%s' "$body" | grep -qF "$pattern"; then
    echo "BLOCKED: Loop body contains denied pattern: '${pattern}'" >&2
    echo "Command: ${command:0:200}" >&2
    exit 2
  fi
done

exit 0
