#!/usr/bin/env zsh
# Checks nudge_context_review.zsh in its three states -- no report (silent), an
# unacknowledged report (one line), an overdue run (one line) -- plus the two
# quiet cases that carry the design: an acknowledged report is silent, and an
# ack older than a re-run does not silence the new report.
#
# This hook runs at EVERY session start, so every degraded input (missing
# state dir, malformed summary) must be silent AND exit 0.
#
# The hook is executed by path, not `zsh <path>`, so its shebang and exec bit
# are exercised the way hook_feature.py's execvp runs it.
#
# Run: zsh tests/test_nudge_context_review.zsh

emulate -L zsh
setopt no_unset pipe_fail

HOOK=${0:A:h:h}/claude/hooks/nudge_context_review.zsh
WORK=$(mktemp -d "${TMPDIR:-/tmp}/nudge-cr.XXXXXX") || { print "cannot make a temp dir"; exit 1 }
trap 'rm -rf -- $WORK' EXIT

print 'nudges.context-review = on' > $WORK/features.conf
export CLAUDE_HOOK_FEATURES_FILE=$WORK/features.conf
export CONTEXT_REVIEW_STATE_DIR=$WORK/state
export CONTEXT_REVIEW_TODAY=2026-12-05

fails=0

# A run directory: $1 date, $2 generated_at, $3 always-on delta (or null).
write_run() {
    mkdir -p $WORK/state/$1
    print -r -- "{\"date\": \"$1\", \"generated_at\": \"$2\", \"vault_copy\": {\"status\": \"ok\"},
 \"nudge\": {\"unused\": 7, \"always_on_delta_bytes\": $3, \"stale_handoffs\": 2, \"stale_learnings\": 0}}" \
        > $WORK/state/$1/summary.json
}

# $1 label, $2 expected substring ("" means silent).
check() {
    local out st
    out=$($HOOK </dev/null 2>/dev/null)
    st=$?
    if (( st != 0 )); then
        print "FAIL  $1: exit $st, a nudge must always exit 0"; (( fails++ )); return
    fi
    if [[ -z $2 ]]; then
        if [[ -n $out ]]; then print "FAIL  $1: expected silence, got: $out"; (( fails++ ))
        else print "ok    $1: silent"; fi
        return
    fi
    if [[ $out != *$2* ]]; then
        print "FAIL  $1: expected '$2' in: $out"; (( fails++ )); return
    fi
    local ctx
    ctx=$(print -r -- $out | python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])')
    if [[ $ctx == *$'\n'* ]]; then
        print "FAIL  $1: more than one line: $ctx"; (( fails++ )); return
    fi
    print "ok    $1: $ctx"
}

check "no state dir" ""
mkdir -p $WORK/state
check "empty state dir" ""

write_run 2026-12-01 2026-12-01T09:30:00Z 120
check "unacknowledged report" "Context review 2026-12-01: 7 unused skills/agents, always-on +120 B, 2 stale handoffs -- run /context-review"

print '{"acked_at": "2026-12-02T10:00:00Z", "note": ""}' > $WORK/state/2026-12-01/acknowledged.json
check "acknowledged report" ""

# A same-day re-run regenerates the report after the ack: it is unreviewed again.
write_run 2026-12-01 2026-12-03T09:30:00Z null
check "ack older than re-run" "always-on: first run, no baseline"

CONTEXT_REVIEW_TODAY=2027-01-20 check "overdue (50 days)" "Context review last ran 2026-12-01 (50 days ago)"
print '{"acked_at": "2026-12-04T10:00:00Z"}' > $WORK/state/2026-12-01/acknowledged.json
CONTEXT_REVIEW_TODAY=2027-01-20 check "overdue even when acknowledged" "the timer is not firing"

print 'not json' > $WORK/state/2026-12-01/summary.json
check "malformed summary" ""

print 'nudges.context-review = off' > $WORK/features.conf
write_run 2026-12-01 2026-12-01T09:30:00Z 5
check "feature flag off" ""

if (( fails )); then
    print "$fails failure(s)"
    exit 1
fi
print "all nudge_context_review checks passed"
