#!/usr/bin/env zsh
# Tests for guard_bear_mcp_args.sh hook
# Run: zsh ~/.claude/hooks/test_guard_bear_mcp_args.sh

# Resolve the hook NEXT TO this test, not through $HOME (see test_block_email_send.sh).
HOOK="${0:A:h}/guard_bear_mcp_args.sh"
PASS=0
FAIL=0

test_case() {
    local description=$1 input=$2 expected_exit=$3 actual_exit=0
    print -rn -- "$input" | zsh "$HOOK" >/dev/null 2>&1 || actual_exit=$?
    if (( actual_exit == expected_exit )); then
        print "  PASS: $description (exit $actual_exit)"
        (( PASS++ ))
    else
        print "  FAIL: $description (expected exit $expected_exit, got $actual_exit)"
        (( FAIL++ ))
    fi
}

B=mcp__plugin_bear-mcp_bear__

print "=== SHOULD BLOCK (exit 2) ==="

test_case "read_note_content with guessed section= (the 2026-10-08 incident)" \
    '{"tool_name":"'${B}'read_note_content","tool_input":{"id":"X","section":"## TL;DR"}}' 2

test_case "edit_note with guessed section= (would edit the whole note)" \
    '{"tool_name":"'${B}'edit_note","tool_input":{"id":"X","section":"## Tasks","edits":[{"find":"a","replace":"b"}]}}' 2

test_case "search_notes with guessed term= and no limit" \
    '{"tool_name":"'${B}'search_notes","tool_input":{"term":"working with me"}}' 2

test_case "search_notes with no limit" \
    '{"tool_name":"'${B}'search_notes","tool_input":{"query":"research update"}}' 2

test_case "search_notes limit 50" \
    '{"tool_name":"'${B}'search_notes","tool_input":{"query":"x","limit":50}}' 2

test_case "search_notes includeContent with limit 10" \
    '{"tool_name":"'${B}'search_notes","tool_input":{"query":"x","limit":10,"includeContent":true}}' 2

test_case "list_notes with no limit" \
    '{"tool_name":"'${B}'list_notes","tool_input":{"tag":"wen"}}' 2

test_case "overwrite_note with guessed hash= instead of baseHash" \
    '{"tool_name":"'${B}'overwrite_note","tool_input":{"id":"X","hash":"h","content":"# T"}}' 2

test_case "legacy mcp__Bear__ prefix is guarded too" \
    '{"tool_name":"mcp__Bear__read_note_content","tool_input":{"id":"X","section":"## A"}}' 2

print
print "=== SHOULD ALLOW (exit 0) ==="

test_case "read_note_content with address" \
    '{"tool_name":"'${B}'read_note_content","tool_input":{"id":"X","address":"## TL;DR"}}' 0

test_case "read_note_content byte slice" \
    '{"tool_name":"'${B}'read_note_content","tool_input":{"id":"X","offset":0,"limit":4000}}' 0

test_case "read_note_outline by title" \
    '{"tool_name":"'${B}'read_note_outline","tool_input":{"title":"Day List"}}' 0

test_case "get_note metadata" \
    '{"tool_name":"'${B}'get_note","tool_input":{"id":"X"}}' 0

test_case "search_notes @title limit 5" \
    '{"tool_name":"'${B}'search_notes","tool_input":{"query":"@title \"working with\"","limit":5}}' 0

test_case "search_notes count only (limit 0)" \
    '{"tool_name":"'${B}'search_notes","tool_input":{"query":"x","limit":0}}' 0

test_case "search_notes includeContent limit 3" \
    '{"tool_name":"'${B}'search_notes","tool_input":{"query":"x","limit":3,"includeContent":true}}' 0

test_case "list_notes limit 10 by tag" \
    '{"tool_name":"'${B}'list_notes","tool_input":{"tag":"wen","limit":10,"sort":"modified:desc"}}' 0

test_case "edit_note with address and edits" \
    '{"tool_name":"'${B}'edit_note","tool_input":{"id":"X","address":"## Tasks","edits":[{"find":"a","replace":"b","all":true}]}}' 0

test_case "overwrite_note with baseHash" \
    '{"tool_name":"'${B}'overwrite_note","tool_input":{"id":"X","baseHash":"h","content":"# T"}}' 0

test_case "append_to_note with position" \
    '{"tool_name":"'${B}'append_to_note","tool_input":{"id":"X","content":"- [ ] a","position":"end"}}' 0

test_case "create_note" \
    '{"tool_name":"'${B}'create_note","tool_input":{"title":"T","content":"b","tags":["x"]}}' 0

test_case "unlisted Bear tool passes" \
    '{"tool_name":"'${B}'list_tags","tool_input":{"anything":1}}' 0

test_case "non-Bear tool passes" \
    '{"tool_name":"Bash","tool_input":{"command":"ls"}}' 0

test_case "empty input" '' 0

test_case "malformed JSON" 'not json' 0

print
print "Results: $PASS passed, $FAIL failed"
(( FAIL == 0 ))
