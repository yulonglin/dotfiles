#!/bin/bash
set -euo pipefail

# PostToolUse(Bash) hook: detect failed git pull/rebase/merge and create a marker
# so guard_post_rebase.sh can block regression commits.

input=$(cat)
command=$(echo "$input" | jq -r '.tool_input.command // ""')
exit_code=$(echo "$input" | jq -r '.tool_output.exit_code // "0"')
stdout=$(echo "$input" | jq -r '.tool_output.stdout // ""')
stderr=$(echo "$input" | jq -r '.tool_output.stderr // ""')

[[ -z "$command" ]] && exit 0

# Only trigger on git pull/rebase/merge commands
if ! [[ "$command" =~ (git[[:space:]]+(pull|rebase|merge)) ]]; then
    # Also clean up marker on successful commit (the guard is no longer needed)
    if [[ "$command" =~ (git[[:space:]]+commit) ]] && [[ "$exit_code" == "0" ]]; then
        git_dir=$(git rev-parse --git-dir 2>/dev/null) || exit 0
        rm -f "$git_dir/POST_SYNC_GUARD"
    fi
    exit 0
fi

git_dir=$(git rev-parse --git-dir 2>/dev/null) || exit 0

# Check if the command failed
output="$stdout $stderr"
if [[ "$exit_code" != "0" ]] || \
   [[ "$output" == *"Aborting"* ]] || \
   [[ "$output" == *"CONFLICT"* ]] || \
   [[ "$output" == *"error:"*"would be overwritten"* ]] || \
   [[ "$output" == *"could not apply"* ]] || \
   [[ "$output" == *"merge failed"* ]] || \
   [[ "$output" == *"Cannot rebase"* ]]; then
    date +%s > "$git_dir/POST_SYNC_GUARD"
else
    # Successful sync — clear any previous marker
    rm -f "$git_dir/POST_SYNC_GUARD"
fi

exit 0
