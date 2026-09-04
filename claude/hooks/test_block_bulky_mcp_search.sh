#!/usr/bin/env bash
# Tests for block_bulky_mcp_search.sh hook
# Run: bash ~/.claude/hooks/test_block_bulky_mcp_search.sh

set -euo pipefail

# Resolve the hook NEXT TO this test, not through $HOME (see test_block_email_send.sh).
HOOK="$(cd "$(dirname "$0")" && pwd)/block_bulky_mcp_search.sh"
PASS=0
FAIL=0

test_case() {
    local description="$1"
    local input="$2"
    local expected_exit="$3"

    actual_exit=0
    printf '%s' "$input" | bash "$HOOK" >/dev/null 2>&1 || actual_exit=$?

    if [ "$actual_exit" -eq "$expected_exit" ]; then
        printf '  PASS: %s (exit %d)\n' "$description" "$actual_exit"
        PASS=$((PASS + 1))
    else
        printf '  FAIL: %s (expected exit %d, got %d)\n' "$description" "$expected_exit" "$actual_exit"
        FAIL=$((FAIL + 1))
    fi
}

GMAIL=mcp__claude_ai_Gmail__search_threads
SLACK=mcp__claude_ai_Slack__slack_search_public_and_private
SLACKPUB=mcp__claude_ai_Slack__slack_search_public
DRIVE=mcp__claude_ai_Google_Drive__search_files

echo "=== SHOULD BLOCK (exit 2) ==="

test_case "gmail search_threads with no pageSize (defaults to 20)" \
    '{"tool_name":"'"$GMAIL"'","tool_input":{"query":"from:x"}}' 2

test_case "gmail search_threads pageSize 50" \
    '{"tool_name":"'"$GMAIL"'","tool_input":{"query":"from:x","pageSize":50}}' 2

test_case "gmail search_threads pageSize 11 (just over cap)" \
    '{"tool_name":"'"$GMAIL"'","tool_input":{"query":"from:x","pageSize":11}}' 2

test_case "gmail search_threads pageSize 0" \
    '{"tool_name":"'"$GMAIL"'","tool_input":{"query":"from:x","pageSize":0}}' 2

test_case "slack search with limit 10 but include_context unset" \
    '{"tool_name":"'"$SLACK"'","tool_input":{"query":"offer letter","limit":10}}' 2

test_case "slack search with include_context false but no limit" \
    '{"tool_name":"'"$SLACK"'","tool_input":{"query":"offer letter","include_context":false}}' 2

test_case "slack search with include_context true and limit 5" \
    '{"tool_name":"'"$SLACK"'","tool_input":{"query":"x","limit":5,"include_context":true}}' 2

test_case "slack public search with nothing set" \
    '{"tool_name":"'"$SLACKPUB"'","tool_input":{"query":"x"}}' 2

test_case "drive search_files with no pageSize" \
    '{"tool_name":"'"$DRIVE"'","tool_input":{"query":"title contains '"'"'x'"'"'"}}' 2

echo
echo "=== SHOULD ALLOW (exit 0) ==="

test_case "gmail search_threads pageSize 10 (at cap)" \
    '{"tool_name":"'"$GMAIL"'","tool_input":{"query":"from:x","pageSize":10}}' 0

test_case "gmail search_threads pageSize 3" \
    '{"tool_name":"'"$GMAIL"'","tool_input":{"query":"from:x","pageSize":3}}' 0

test_case "gmail search_threads pageSize as numeric string" \
    '{"tool_name":"'"$GMAIL"'","tool_input":{"query":"from:x","pageSize":"5"}}' 0

test_case "slack search limit 10 and include_context false" \
    '{"tool_name":"'"$SLACK"'","tool_input":{"query":"x","limit":10,"include_context":false}}' 0

test_case "drive search_files pageSize 10" \
    '{"tool_name":"'"$DRIVE"'","tool_input":{"query":"x","pageSize":10}}' 0

test_case "gmail get_thread is not a search" \
    '{"tool_name":"mcp__claude_ai_Gmail__get_thread","tool_input":{"threadId":"abc"}}' 0

test_case "slack read_thread is not a search" \
    '{"tool_name":"mcp__claude_ai_Slack__slack_read_thread","tool_input":{"channel_id":"C1","message_ts":"1.2","limit":1000}}' 0

test_case "Bash tool passes through" \
    '{"tool_name":"Bash","tool_input":{"command":"ls"}}' 0

test_case "empty input" '' 0

test_case "malformed JSON" 'not json' 0

echo
printf 'Results: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
