#!/usr/bin/env bash
# Tests for block_gws_delete.sh
set -euo pipefail

HOOK="$(cd "$(dirname "$0")" && pwd)/block_gws_delete.sh"
PASS=0
FAIL=0

run_test() {
    local desc="$1" cmd="$2" expect="$3"
    local input
    # Use python to safely JSON-encode the command (handles all special chars)
    input=$(python3 -c "
import json, sys
print(json.dumps({'tool_input': {'command': sys.argv[1]}}))" "$cmd")

    local rc=0
    printf '%s' "$input" | bash "$HOOK" >/dev/null 2>&1 || rc=$?

    if [ "$expect" = "block" ] && [ "$rc" -eq 2 ]; then
        PASS=$((PASS + 1))
    elif [ "$expect" = "allow" ] && [ "$rc" -eq 0 ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        printf 'FAIL: %s (expected %s, got exit %d)\n' "$desc" "$expect" "$rc"
    fi
}

echo "=== SHOULD BLOCK: Gmail permanent deletions ==="
run_test "gmail messages delete" "gws gmail users messages delete --params '{\"userId\":\"me\",\"id\":\"abc\"}'" "block"
run_test "gmail threads delete" "gws gmail users threads delete --params '{\"userId\":\"me\",\"id\":\"abc\"}'" "block"
run_test "gmail batchDelete" "gws gmail users messages batchDelete --params '{\"userId\":\"me\"}'" "block"

echo "=== SHOULD BLOCK: Drive permanent deletions ==="
run_test "drive files delete" "gws drive files delete --params '{\"fileId\":\"abc\"}'" "block"
run_test "drive files emptyTrash" "gws drive files emptyTrash" "block"
run_test "drive comments delete" "gws drive comments delete --params '{\"fileId\":\"a\",\"commentId\":\"b\"}'" "block"
run_test "drive drives delete" "gws drive drives delete --params '{\"driveId\":\"abc\"}'" "block"
run_test "drive permissions delete" "gws drive permissions delete --params '{\"fileId\":\"a\",\"permissionId\":\"b\"}'" "block"
run_test "drive replies delete" "gws drive replies delete --params '{\"fileId\":\"a\",\"commentId\":\"b\",\"replyId\":\"c\"}'" "block"
run_test "drive revisions delete" "gws drive revisions delete --params '{\"fileId\":\"a\",\"revisionId\":\"b\"}'" "block"
run_test "drive teamdrives delete" "gws drive teamdrives delete --params '{\"teamDriveId\":\"abc\"}'" "block"

echo "=== SHOULD BLOCK: Calendar deletions ==="
run_test "calendar events delete" "gws calendar events delete --params '{\"calendarId\":\"primary\",\"eventId\":\"abc\"}'" "block"
run_test "calendar calendars delete" "gws calendar calendars delete --params '{\"calendarId\":\"abc\"}'" "block"
run_test "calendar calendars clear" "gws calendar calendars clear --params '{\"calendarId\":\"primary\"}'" "block"
run_test "calendar acl delete" "gws calendar acl delete --params '{\"calendarId\":\"primary\",\"ruleId\":\"abc\"}'" "block"
run_test "calendar calendarList delete" "gws calendar calendarList delete --params '{\"calendarId\":\"abc\"}'" "block"

echo "=== SHOULD BLOCK: Tasks deletions ==="
run_test "tasks tasklists delete" "gws tasks tasklists delete --params '{\"tasklist\":\"abc\"}'" "block"
run_test "tasks tasks delete" "gws tasks tasks delete --params '{\"tasklist\":\"a\",\"task\":\"b\"}'" "block"

echo "=== SHOULD BLOCK: Other services ==="
run_test "generic delete" "gws slides presentations delete --params '{\"presentationId\":\"abc\"}'" "block"

echo "=== SHOULD BLOCK: bash -c wrappers ==="
run_test "wrapped gmail delete" "bash -c 'gws gmail users messages delete --params ...'" "block"
run_test "wrapped drive delete" "sh -c 'gws drive files delete --params ...'" "block"

echo "=== SHOULD ALLOW: trash/archive ==="
run_test "gmail messages trash" "gws gmail users messages trash --params '{\"userId\":\"me\",\"id\":\"abc\"}'" "allow"
run_test "gmail threads trash" "gws gmail users threads trash --params '{\"userId\":\"me\",\"id\":\"abc\"}'" "allow"
run_test "gmail messages untrash" "gws gmail users messages untrash --params '{\"userId\":\"me\",\"id\":\"abc\"}'" "allow"
run_test "gmail messages modify" "gws gmail users messages modify --params '{\"userId\":\"me\",\"id\":\"abc\"}'" "allow"

echo "=== SHOULD ALLOW: read/list/get ==="
run_test "gmail list" "gws gmail users messages list --params '{\"userId\":\"me\"}'" "allow"
run_test "drive files list" "gws drive files list --params '{\"pageSize\":10}'" "allow"
run_test "drive files get" "gws drive files get --params '{\"fileId\":\"abc\"}'" "allow"
run_test "calendar events list" "gws calendar events list --params '{\"calendarId\":\"primary\"}'" "allow"
run_test "calendar events get" "gws calendar events get --params '{\"calendarId\":\"primary\",\"eventId\":\"abc\"}'" "allow"

echo "=== SHOULD ALLOW: create/update ==="
run_test "calendar events insert" "gws calendar events insert --params '{\"calendarId\":\"primary\"}'" "allow"
run_test "drive files create" "gws drive files create --params '{\"name\":\"test\"}'" "allow"
run_test "gmail +send --draft" "gws gmail +send --draft --params '{\"to\":\"a@b.com\"}'" "allow"

echo "=== SHOULD ALLOW: --dry-run ==="
run_test "delete with --dry-run" "gws gmail users messages delete --dry-run --params '{\"userId\":\"me\",\"id\":\"abc\"}'" "allow"
run_test "drive delete --dry-run" "gws drive files delete --dry-run" "allow"

echo "=== SHOULD ALLOW: --help ==="
run_test "delete with --help" "gws gmail users messages delete --help" "allow"

echo "=== SHOULD ALLOW: non-gws commands ==="
run_test "regular rm" "rm -rf /tmp/test" "allow"
run_test "git command" "git log --oneline" "allow"

echo ""
echo "Results: $PASS passed, $FAIL failed (total $((PASS + FAIL)))"
[ "$FAIL" -eq 0 ] && echo "All tests passed!" || exit 1
