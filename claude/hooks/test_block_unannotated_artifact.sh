#!/usr/bin/env bash
# Tests for block_unannotated_artifact.sh
# Run: bash ~/.claude/hooks/test_block_unannotated_artifact.sh

set -euo pipefail

# Resolve the hook NEXT TO this test, not through $HOME, so a worktree copy of
# the suite exercises the hook it ships with rather than the deployed one.
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HOOK_DIR/block_unannotated_artifact.sh"
ANNOTATE="$HOOK_DIR/../../custom_bins/annotate-html"
PASS=0
FAIL=0

WORK=$(mktemp -d "${TMPDIR:-/tmp}/annot-hook.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

BARE="$WORK/bare.html"
printf '<title>Bare</title>\n<p>no layer here</p>\n' > "$BARE"
LAYERED="$WORK/layered.html"
cp "$BARE" "$LAYERED"
python3 "$ANNOTATE" "$LAYERED" >/dev/null
OLDPORT="$WORK/oldport.html"
printf '<title>Old</title>\n<p>x</p>\n<!-- annotation-layer -->\n<script>1</script>\n' > "$OLDPORT"
cp "$BARE" "$WORK/UP.HTML"
MD="$WORK/notes.md"
printf '# notes\n' > "$MD"

test_case() {
    local description="$1" input="$2" expected_exit="$3"
    local actual_exit=0
    printf '%s' "$input" | bash "$HOOK" >/dev/null 2>&1 || actual_exit=$?
    if [ "$actual_exit" -eq "$expected_exit" ]; then
        printf '  PASS: %s (exit %d)\n' "$description" "$actual_exit"
        PASS=$((PASS + 1))
    else
        printf '  FAIL: %s (expected exit %d, got %d)\n' "$description" "$expected_exit" "$actual_exit"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== SHOULD BLOCK (exit 2) ==="
test_case "publish (action omitted) of html without layer" \
    "{\"tool_name\":\"Artifact\",\"tool_input\":{\"file_path\":\"$BARE\",\"favicon\":\"x\"}}" 2
test_case "publish (action explicit) of html without layer" \
    "{\"tool_name\":\"Artifact\",\"tool_input\":{\"action\":\"publish\",\"file_path\":\"$BARE\"}}" 2
test_case "publish of .HTML (uppercase) without layer" \
    "{\"tool_input\":{\"file_path\":\"$WORK/UP.HTML\"}}" 2

echo "=== SHOULD ALLOW (exit 0) ==="
test_case "publish of html with layer" \
    "{\"tool_name\":\"Artifact\",\"tool_input\":{\"file_path\":\"$LAYERED\"}}" 0
test_case "publish of html with the older hand-ported marker" \
    "{\"tool_name\":\"Artifact\",\"tool_input\":{\"file_path\":\"$OLDPORT\"}}" 0
test_case "publish of markdown" \
    "{\"tool_name\":\"Artifact\",\"tool_input\":{\"file_path\":\"$MD\"}}" 0
test_case "action=read" \
    "{\"tool_name\":\"Artifact\",\"tool_input\":{\"action\":\"read\",\"url\":\"https://x\"}}" 0
test_case "action=comments" \
    "{\"tool_name\":\"Artifact\",\"tool_input\":{\"action\":\"comments\",\"url\":\"https://x\"}}" 0
test_case "action=upload_asset with an html-looking file_path" \
    "{\"tool_name\":\"Artifact\",\"tool_input\":{\"action\":\"upload_asset\",\"file_path\":\"$BARE\"}}" 0
test_case "file that does not exist yet (publish fails on its own)" \
    "{\"tool_name\":\"Artifact\",\"tool_input\":{\"file_path\":\"$WORK/absent.html\"}}" 0
test_case "different tool name" \
    "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$BARE\"}}" 0
test_case "unparseable payload" "not json" 0
test_case "empty payload" "" 0

echo "=== BLOCK MESSAGE ==="
MSG=$(printf '%s' "{\"tool_input\":{\"file_path\":\"$BARE\"}}" | bash "$HOOK" 2>&1 >/dev/null || true)
if printf '%s' "$MSG" | grep -q "annotate-html $BARE"; then
    printf '  PASS: block message names the fix command\n'; PASS=$((PASS + 1))
else
    printf '  FAIL: block message missing fix command: %s\n' "$MSG"; FAIL=$((FAIL + 1))
fi

echo
echo "Passed: $PASS  Failed: $FAIL"
[ "$FAIL" -eq 0 ]
