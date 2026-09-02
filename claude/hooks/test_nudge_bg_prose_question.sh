#!/usr/bin/env bash
# Tests for nudge_bg_prose_question.sh.
#
# The load-bearing assertion is not that a question-shaped background stop is
# blocked — it is that the SECOND stop passes. A gate that can trap an
# unattended session is worse than no gate, so "one-shot" is tested directly
# by calling the hook twice with the same session_id.
#
# Contract: exit 0 always; a fired gate emits {"decision":"block",...}.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="$DIR/nudge_bg_prose_question.sh"
PASS=0
FAIL=0

TMP=""
for cand in /tmp/claude /tmp .; do
    if mkdir -p "$cand/bgq-tests.$$" 2>/dev/null && [ -w "$cand/bgq-tests.$$" ]; then
        TMP="$cand/bgq-tests.$$"
        break
    fi
done
[ -n "$TMP" ] || { echo "no writable temp dir found" >&2; exit 1; }
trap 'rm -rf "$TMP"' EXIT

# guard files must land somewhere we control and clean up
export TMPDIR="$TMP"

# transcript <file> <final-assistant-text> <asked:true|false>
transcript() {
    python3 -c "
import json, sys
path, text, asked = sys.argv[1:4]
rows = [
    {'type': 'user', 'message': {'content': [{'type': 'text', 'text': 'do the thing'}]}},
    {'type': 'assistant', 'message': {'content': [
        {'type': 'tool_use', 'name': 'Read', 'input': {}}]}},
    {'type': 'user', 'message': {'content': [
        {'type': 'tool_result', 'content': 'ok'}]}},
]
if asked == 'true':
    rows.append({'type': 'assistant', 'message': {'content': [
        {'type': 'tool_use', 'name': 'AskUserQuestion', 'input': {}}]}})
rows.append({'type': 'assistant', 'message': {'content': [
    {'type': 'text', 'text': text}]}})
with open(path, 'w') as fh:
    for r in rows:
        fh.write(json.dumps(r) + '\n')
" "$1" "$2" "$3"
}

# stop_input <session_id> <transcript_path> <stop_hook_active>
stop_input() {
    python3 -c "
import json, sys
sid, tp, active = sys.argv[1:4]
print(json.dumps({'session_id': sid, 'transcript_path': tp,
                  'stop_hook_active': active == 'true'}))
" "$1" "$2" "$3"
}

# run <desc> <session> <text> <asked> <expect> [bg:true|false] [active:true|false]
run() {
    local desc="$1" sid="$2" text="$3" asked="$4" expect="$5"
    local bg="${6:-true}" active="${7:-false}"
    local tfile="$TMP/transcript-$sid.jsonl"
    local out rc=0

    transcript "$tfile" "$text" "$asked"

    if [ "$bg" = true ]; then
        out=$(stop_input "$sid" "$tfile" "$active" \
              | CLAUDE_JOB_DIR="$TMP/job" bash "$HOOK" 2>/dev/null) || rc=$?
    else
        out=$(stop_input "$sid" "$tfile" "$active" \
              | env -u CLAUDE_JOB_DIR bash "$HOOK" 2>/dev/null) || rc=$?
    fi

    if [ "$rc" -ne 0 ]; then
        FAIL=$((FAIL + 1))
        printf 'FAIL: %s (exited %d — must always be 0)\n' "$desc" "$rc"
        return
    fi

    local got=pass
    case "$out" in *'"block"'*) got=gate ;; esac

    if [ "$got" != "$expect" ]; then
        FAIL=$((FAIL + 1))
        printf 'FAIL: %s (expected %s, got %s)\n' "$desc" "$expect" "$got"
        return
    fi

    if [ "$expect" = gate ] && ! printf '%s' "$out" | grep -q 'AskUserQuestion'; then
        FAIL=$((FAIL + 1))
        printf 'FAIL: %s (gate reason does not name AskUserQuestion)\n' "$desc"
        return
    fi

    PASS=$((PASS + 1))
}

Q_TRAILING='I have finished the analysis of both approaches.

Which would you prefer, the pipeline or the barrier?'

echo "=== question-shaped background stop (must gate) ==="
run "trailing question mark" s1 "$Q_TRAILING" false gate
run "should I phrasing" s2 'I can take either path here. Should I go ahead and refactor the parser first.' false gate
run "let me know phrasing" s3 'Both options are viable. Let me know which one you want and I will proceed.' false gate

echo "=== the one-shot guarantee (the gate must never trap a session) ==="
# s1 already gated above; the retry with the SAME session id must pass
run "second stop on same session passes" s1 "$Q_TRAILING" false pass
run "third stop still passes"            s1 "$Q_TRAILING" false pass

echo "=== must never gate ==="
run "AskUserQuestion was called" s4 "$Q_TRAILING" true  pass
run "plain statement"            s5 'I refactored the parser and all 35 tests pass.' false pass
run "completed with result:"     s6 'All done.

result: parser refactored, 35 tests green

Want me to also wire the hook?' false pass
run "foreground session"         s7 "$Q_TRAILING" false pass false
run "stop_hook_active"           s8 "$Q_TRAILING" false pass true  true

echo "=== degenerate inputs (fail open) ==="
rc=0
out=$(printf '%s' '{"session_id":"s9","transcript_path":"/nonexistent/x.jsonl"}' \
      | CLAUDE_JOB_DIR="$TMP/job" bash "$HOOK" 2>/dev/null) || rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1)); printf 'FAIL: missing transcript fails open (rc=%d)\n' "$rc"
fi

rc=0
out=$(printf '%s' 'not json' | CLAUDE_JOB_DIR="$TMP/job" bash "$HOOK" 2>/dev/null) || rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1)); printf 'FAIL: malformed stdin fails open (rc=%d)\n' "$rc"
fi

echo
TOTAL=$((PASS + FAIL))
echo "Results: $PASS passed, $FAIL failed (total $TOTAL)"
[ "$FAIL" -eq 0 ] && echo "All tests passed!"
[ "$FAIL" -eq 0 ]
