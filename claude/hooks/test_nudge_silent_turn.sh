#!/usr/bin/env bash
# Tests for nudge_silent_turn.sh.
#
# The load-bearing assertions: (1) a turn with tool activity but no visible
# text after a real human message is blocked ONCE, and the retry for the
# same turn passes — a gate that can trap a session is worse than no gate;
# (2) interactive surfaces (AskUserQuestion, plan mode, SendMessage),
# command/interrupt/shell-mode turns, and reminder-only user messages never
# gate; (3) an isMeta user entry (skill body, cross-session message) is not a
# turn boundary, so text written before it still counts.
#
# Contract: exit 0 always; a fired gate emits {"decision":"block",...}.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="$DIR/nudge_silent_turn.sh"
PASS=0
FAIL=0

TMP=""
for cand in "${TMPDIR:-}" /tmp/claude /tmp .; do
    [ -n "$cand" ] || continue
    if mkdir -p "$cand/silent-tests.$$" 2>/dev/null && [ -w "$cand/silent-tests.$$" ]; then
        TMP="$cand/silent-tests.$$"
        break
    fi
done
[ -n "$TMP" ] || { echo "no writable temp dir found" >&2; exit 1; }
trap 'rm -rf "$TMP"' EXIT

# guard files must land somewhere we control and clean up
export TMPDIR="$TMP"

# transcript <file> <user-text> <mode> [uuid]
#   mode: silent          — tool_use activity, no assistant text
#         text            — assistant replies with visible text
#         ask|plan|send   — exempt interactive tool, no text
#         empty-text      — assistant emits only a whitespace text block
#         no-activity     — no assistant blocks at all after the user message
#         meta-after-text — text, then a Skill call whose isMeta body lands
#                           as a user entry, then tool activity only
#         meta-silent     — as meta-after-text, with no text before the skill
transcript() {
    python3 -c "
import json, sys
path, utext, mode, uuid = sys.argv[1:5]
first = {'type': 'user', 'message': {'content': [{'type': 'text', 'text': utext}]}}
if uuid:
    first['uuid'] = uuid
rows = [first]
def tool(name):
    return {'type': 'assistant', 'message': {'content': [
        {'type': 'tool_use', 'name': name, 'input': {}}]}}
def say(text):
    return {'type': 'assistant', 'message': {'content': [
        {'type': 'text', 'text': text}]}}
if mode != 'no-activity':
    rows.append(tool('Read'))
    rows.append({'type': 'user', 'message': {'content': [
        {'type': 'tool_result', 'content': 'ok'}]}})
if mode == 'text':
    rows.append(say('IB error bars landing in the next render.'))
elif mode == 'empty-text':
    rows.append(say('  \n  '))
elif mode == 'ask':
    rows.append(tool('AskUserQuestion'))
elif mode == 'plan':
    rows.append(tool('ExitPlanMode'))
elif mode == 'send':
    rows.append(tool('SendMessage'))
elif mode in ('meta-after-text', 'meta-silent'):
    if mode == 'meta-after-text':
        rows.append(say('Loading the skill, then fixing it.'))
    rows.append(tool('Skill'))
    rows.append({'type': 'user', 'isMeta': True, 'message': {'content': [
        {'type': 'text', 'text': 'Base directory for this skill: /x'}]}})
    rows.append(tool('Edit'))
with open(path, 'w') as fh:
    for r in rows:
        fh.write(json.dumps(r) + '\n')
" "$1" "$2" "$3" "${4:-}"
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

# run <desc> <session> <user-text> <mode> <expect> [active:true|false] [uuid]
run() {
    local desc="$1" sid="$2" utext="$3" mode="$4" expect="$5" active="${6:-false}" uuid="${7:-}"
    local tfile="$TMP/transcript-$sid-$mode.jsonl"
    local out rc=0

    transcript "$tfile" "$utext" "$mode" "$uuid"
    out=$(stop_input "$sid" "$tfile" "$active" | bash "$HOOK" 2>/dev/null) || rc=$?

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

    if [ "$expect" = gate ] && ! printf '%s' "$out" | grep -q 'user-visible text'; then
        FAIL=$((FAIL + 1))
        printf 'FAIL: %s (gate reason does not explain the silence)\n' "$desc"
        return
    fi

    PASS=$((PASS + 1))
}

Q='pls we need error bars for impossiblebench too! and what are the implicit/explicit for flaky tools??'

echo "=== silent turn after a human question (must gate) ==="
run "tool activity, no text"          s1 "$Q" silent gate
run "whitespace-only text is silent"  s2 "$Q" empty-text gate

echo "=== the one-shot guarantee (the gate must never trap a session) ==="
# s1 already gated above; the retry for the SAME turn must pass
run "second stop on same turn passes" s1 "$Q" silent pass
run "third stop still passes"         s1 "$Q" silent pass
# but a NEW silent turn in the same session gates again
run "new user message gates again"    s1 "different question, still ignored?" silent gate
# identical text under a new message uuid is a new turn (a second "continue")
run "uuid u1 gates"                   s13 continue silent gate false u1
run "uuid u1 retry passes"            s13 continue silent pass false u1
run "same text, new uuid u2, gates"   s13 continue silent gate false u2

echo "=== isMeta entries are not turn boundaries ==="
run "silent turn across a skill load gates" s14 "$Q" meta-silent gate
run "text before a skill load counts"       s15 "$Q" meta-after-text pass

echo "=== must never gate ==="
run "visible text was written"     s3 "$Q" text pass
run "AskUserQuestion surface"      s4 "$Q" ask pass
run "plan-mode surface"            s5 "$Q" plan pass
run "SendMessage surface"          s6 "$Q" send pass
run "no assistant activity at all" s7 "$Q" no-activity pass
run "stop_hook_active"             s8 "$Q" silent pass true
run "slash-command turn"           s9 '<command-name>/clear</command-name>' silent pass
run "interrupted turn"             s10 '[Request interrupted by user]' silent pass
run "reminder-only user message"   s11 '<system-reminder>recalled memory</system-reminder>' silent pass
run "shell-mode carrier"           s16 '<bash-input>git status</bash-input>' silent pass

echo "=== degenerate inputs (fail open) ==="
rc=0
out=$(printf '%s' '{"session_id":"s12","transcript_path":"/nonexistent/x.jsonl"}' \
      | bash "$HOOK" 2>/dev/null) || rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1)); printf 'FAIL: missing transcript fails open (rc=%d)\n' "$rc"
fi

rc=0
out=$(printf '%s' 'not json' | bash "$HOOK" 2>/dev/null) || rc=$?
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
