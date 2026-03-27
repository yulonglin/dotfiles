#!/bin/bash
set -euo pipefail

# PostToolUse(Grep) hook: detect "[Omitted long matching line]" in Grep results
# and instruct Claude to retry with Bash rg + truncation to show actual content.
#
# Problem: Claude Code's built-in Grep tool silently replaces long matching lines
# with "[Omitted long matching line]", making results useless when most lines are long
# (e.g., JSONL files, minified code, task output files).
#
# Solution: When ≥50% of result lines are omitted, send a systemMessage telling
# Claude to retry the search using rg directly with line truncation.

input=$(cat)

tool_result=$(echo "$input" | jq -r '.tool_result // ""')

# Quick exit if no omitted lines
[[ "$tool_result" != *"[Omitted long matching line]"* ]] && exit 0

# Count omitted vs total result lines
omitted=$(echo "$tool_result" | grep -c '\[Omitted long matching line\]' || true)
total=$(echo "$tool_result" | grep -c '.' || true)

# Only trigger when omitted lines are ≥50% of output
(( total == 0 )) && exit 0
ratio=$(( omitted * 100 / total ))
(( ratio < 50 )) && exit 0

# Extract all search parameters in a single jq call (safe quoting via @sh)
eval "$(echo "$input" | jq -r '
  @sh "pattern=\(.tool_input.pattern // "")",
  @sh "path=\(.tool_input.path // ".")",
  @sh "output_mode=\(.tool_input.output_mode // "content")",
  @sh "glob_filter=\(.tool_input.glob // "")",
  @sh "type_filter=\(.tool_input.type // "")",
  @sh "case_insensitive=\(.tool_input["-i"] // false)"
')"

# Build the rg command suggestion (display only, not executed)
rg_cmd="rg"
[[ "$case_insensitive" == "true" ]] && rg_cmd+=" -i"
[[ -n "$glob_filter" ]] && rg_cmd+=" --glob $(printf '%q' "$glob_filter")"
[[ -n "$type_filter" ]] && rg_cmd+=" --type $(printf '%q' "$type_filter")"
[[ "$output_mode" == "content" ]] && rg_cmd+=" -n"
[[ "$output_mode" == "files_with_matches" ]] && rg_cmd+=" -l"
[[ "$output_mode" == "count" ]] && rg_cmd+=" -c"

rg_cmd+=" $(printf '%q' "$pattern") $(printf '%q' "$path")"

# For content mode (default), add truncation to handle the long lines
if [[ "$output_mode" == "content" ]]; then
    rg_cmd+=" | cut -c1-200"
fi

# Output JSON systemMessage on stdout (PostToolUse protocol: stdout + exit 0)
jq -n --arg omitted "$omitted" --arg total "$total" --arg rg_cmd "$rg_cmd" '{
  systemMessage: ("Grep returned " + $omitted + "/" + $total + " lines as \"[Omitted long matching line]\" — the file has lines too long for the built-in Grep tool to display. Retry with Bash to see truncated content:\n\n```bash\n" + $rg_cmd + "\n```\n\nOr use Read with offset/limit on the specific line numbers to see full content.")
}'
exit 0
