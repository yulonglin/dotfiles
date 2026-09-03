#!/usr/bin/env bash
# PreToolUse hook for MCP search tools: block a call whose page is uncapped.
#
# One default page of Gmail `search_threads` (20 threads with snippets),
# Slack `slack_search_*` (20 hits with context) or Drive `search_files` has
# spilled 50k+ characters into the calling context. When that happens the
# harness dumps the result to a file the agent must then jq — slower than
# paging, and the context is gone either way.
#
# Contract (same as block_destructive_git.sh): exit 0 = allow; exit 2 = block,
# reason on stderr. Applies to subagents too: a sweep paginates with
# pageToken / cursor; it does not pull one huge page.
#
# Caps (MAX below):
#   Gmail  search_threads                    pageSize <= MAX
#   Drive  search_files                      pageSize <= MAX
#   Slack  slack_search_public[_and_private] limit <= MAX and include_context == false
#
# Everything else (get_thread, get_message, read_thread, list_labels, ...)
# passes untouched: those are bounded by the caller's own choice of ID.

set -uo pipefail

input=$(cat)
command -v jq >/dev/null 2>&1 || exit 0

MAX=10
tool=$(printf '%s' "$input" | jq -r '.tool_name // ""' 2>/dev/null) || exit 0
[ -n "$tool" ] || exit 0

reason=""
case "$tool" in
    mcp__claude_ai_Gmail__search_threads|mcp__claude_ai_Google_Drive__search_files)
        reason=$(printf '%s' "$input" | jq -r --argjson max "$MAX" '
            ((.tool_input.pageSize // null) | tonumber? // 0) as $n
            | if $n >= 1 and $n <= $max then ""
              else "pageSize is \(if $n == 0 then "unset" else ($n|tostring) end); pass pageSize <= \($max) and page with pageToken"
              end' 2>/dev/null) || exit 0
        ;;
    mcp__claude_ai_Slack__slack_search_public|mcp__claude_ai_Slack__slack_search_public_and_private)
        reason=$(printf '%s' "$input" | jq -r --argjson max "$MAX" '
            ((.tool_input.limit // null) | tonumber? // 0) as $n
            | (.tool_input.include_context) as $c
            | [ (if $n >= 1 and $n <= $max then empty
                 else "limit is \(if $n == 0 then "unset" else ($n|tostring) end); pass limit <= \($max) and page with cursor" end),
                (if $c == false then empty
                 else "include_context is \(if $c == null then "unset" else ($c|tostring) end); pass include_context: false" end) ]
            | join("; ")' 2>/dev/null) || exit 0
        ;;
    *)
        exit 0
        ;;
esac

[ -n "$reason" ] || exit 0

cat >&2 <<MSG
Blocked: $tool with an uncapped page ($reason).

A default page of this tool has spilled 50k+ characters into context before. When a result overflows, the harness writes it to a file you then have to jq — slower than paging, and the tokens are spent either way.

Do one of:
- Delegate the sweep to a subagent (rules/delegation.md) and page there under the same caps.
- Inline, narrow the query (sender, date range, subject) and pass the caps above.
MSG
exit 2
