#!/usr/bin/env zsh
# Checks nudge_computer_use_esc.py warns only when keytaps reports a live
# computer-use Esc tap held by this session, and stays quiet otherwise. A stub
# stands in for keytaps so the test needs no real event tap.
set -uo pipefail

HOOK=${0:A:h}/../claude/hooks/nudge_computer_use_esc.py
WORK=$(mktemp -d "${TMPDIR:-/tmp}/cu-esc.XXXXXX") || { print "cannot make a temp dir"; exit 1 }
trap 'rm -rf "$WORK"' EXIT
STUB=$WORK/keytaps
export KEYTAPS_BIN=$STUB
fails=0

stub() {  # stub <exit-code> [json-stdout]
  print -r -- "import sys; print(${(qq)2:-}); sys.exit($1)" > $STUB
}

check() {  # check <label> <session> <expect: fires|quiet>
  local out
  out=$(print -r -- "{\"session_id\":\"$2\"}" | python3 $HOOK)
  if [[ $3 == fires && $out == *systemMessage*Esc* ]] || [[ $3 == quiet && -z $out ]]; then
    print "ok   $1"
  else
    print "FAIL $1 (wanted $3, got: ${out:-<nothing>})"; (( fails++ ))
  fi
}

[[ $OSTYPE == darwin* ]] || { print "skip: macOS only"; exit 0 }

stub 0 '{"pid":1,"blocking":true,"enabled":true,"events":["keyDown"],"computer_use":{"pid":1,"sessionId":"sess-A"}}'
check "live tap, this session"          sess-A fires
check "live tap, another session"       sess-B quiet
stub 1
check "no live tap (lock outlived it)"  sess-A quiet
stub 0 'not json'
check "garbled keytaps output"          sess-A quiet
out=$(print -r -- 'garbage' | python3 $HOOK); rc=$?
[[ $rc == 0 && -z $out ]] && print "ok   garbled stdin" || { print "FAIL garbled stdin"; (( fails++ )) }

(( fails == 0 )) && print "all passed" || { print "$fails failed"; exit 1 }
