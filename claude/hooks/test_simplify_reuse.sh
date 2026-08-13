#!/usr/bin/env bash
# Tests for the scratch-script reuse nudge: simplify_track_reuse.py (counts
# repeat runs) and simplify_nudge.sh (turns the tally into a promotion nudge).
#
# Same contract as test_convention_nudges.sh: each hook must (a) fire a
# systemMessage on a positive case, (b) stay silent on negatives, and
# (c) NEVER exit non-zero.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
PASS=0
FAIL=0

TMP=""
for cand in "${TMPDIR:-}" /tmp/claude /tmp .; do
    [ -n "$cand" ] || continue
    if mkdir -p "$cand/simplify-reuse-tests.$$" 2>/dev/null; then
        TMP="$cand/simplify-reuse-tests.$$"
        break
    fi
done
[ -n "$TMP" ] || { echo "no writable temp dir found" >&2; exit 1; }
trap 'rm -rf "$TMP"' EXIT

# Hooks keep their state under TMPDIR — point them at the sandbox.
export TMPDIR="$TMP"
STATE_DIR="$TMP/claude-simplify-$(id -u)"
state_file() { printf '%s/reuse-%s.json' "$STATE_DIR" "$1"; }

ok()   { PASS=$((PASS + 1)); }
bad()  { FAIL=$((FAIL + 1)); printf 'FAIL: %s\n' "$1"; }

# bash_event <session> <cwd> <command>
bash_event() {
    python3 -c "
import json, sys
session, cwd, command = sys.argv[1:4]
print(json.dumps({'session_id': session, 'cwd': cwd, 'tool_name': 'Bash',
                  'tool_input': {'command': command}}))
" "$1" "$2" "$3"
}

# track <session> <cwd> <command> — one run through the PostToolUse tracker.
track() {
    local rc=0
    bash_event "$1" "$2" "$3" | python3 "$DIR/simplify_track_reuse.py" >/dev/null 2>&1 || rc=$?
    [ "$rc" -eq 0 ] || bad "tracker exited $rc on: $3"
}

# nudge <session> — run the Stop hook, echo its stdout.
nudge() {
    local rc=0 out
    out=$(printf '{"session_id":"%s"}' "$1" | bash "$DIR/simplify_nudge.sh" 2>/dev/null) || rc=$?
    [ "$rc" -eq 0 ] || bad "nudge hook exited $rc"
    printf '%s' "$out"
}

# expect <desc> <output> <fire|silent> [needle]
expect() {
    local desc="$1" out="$2" want="$3" needle="${4:-}"
    local got=silent
    case "$out" in *systemMessage*) got=fire ;; esac
    if [ "$got" != "$want" ]; then
        bad "$desc (expected $want, got $got)"
        return
    fi
    # Half the output contract is that stdout is a single valid JSON object
    # with a systemMessage key — a substring check alone would miss a message
    # broken by a quote or newline in a script path.
    if [ "$got" = fire ] && ! printf '%s' "$out" | jq -e '.systemMessage | strings' >/dev/null 2>&1; then
        bad "$desc (stdout is not a JSON object with a string systemMessage)"
        return
    fi
    if [ -n "$needle" ] && [[ "$out" != *"$needle"* ]]; then
        bad "$desc (missing '$needle' in message)"
        return
    fi
    ok
}

runs() { local n=$1; shift; while [ "$n" -gt 0 ]; do track "$@"; n=$((n - 1)); done; }

# --- tracker: what counts as a run of a scratch script ----------------------
echo "=== reuse tracking ==="

mkdir -p "$TMP/scratch" "$TMP/bin" "$TMP/node_modules/pkg/tmp"
printf 'print("hi")\n' > "$TMP/scratch/probe.py"
printf 'echo hi\n'     > "$TMP/scratch/probe.sh"
printf 'echo hi\n'     > "$TMP/bin/deploy.sh"
printf 'x = 1\n'       > "$TMP/tmp_backfill.py"
printf 'x = 1\n'       > "$TMP/node_modules/pkg/tmp/setup.py"

S=count-py
runs 3 "$S" "$TMP" "python3 $TMP/scratch/probe.py --limit 3"
expect "3 runs of a scratch script fires" "$(nudge "$S")" fire "probe.py"

S=count-uv
runs 3 "$S" "$TMP" "uv run $TMP/scratch/probe.py"
expect "uv run counts as execution" "$(nudge "$S")" fire "probe.py"

S=count-direct
runs 3 "$S" "$TMP" "$TMP/scratch/probe.sh"
expect "direct invocation counts" "$(nudge "$S")" fire "probe.sh"

S=count-relative
runs 3 "$S" "$TMP" "bash scratch/probe.sh"
expect "relative path resolves against cwd" "$(nudge "$S")" fire "$TMP/scratch/probe.sh"

S=count-name
runs 3 "$S" "$TMP" "python3 $TMP/tmp_backfill.py"
expect "tmp_-prefixed name counts as scratch" "$(nudge "$S")" fire "tmp_backfill.py"

S=below
runs 2 "$S" "$TMP" "python3 $TMP/scratch/probe.py"
expect "2 runs stays below threshold" "$(nudge "$S")" silent

S=permanent
runs 5 "$S" "$TMP" "bash $TMP/bin/deploy.sh"
expect "script in a permanent home ignored" "$(nudge "$S")" silent

S=vendored
runs 5 "$S" "$TMP" "python3 $TMP/node_modules/pkg/tmp/setup.py"
expect "vendored tmp/ path ignored" "$(nudge "$S")" silent

S=notrun
runs 5 "$S" "$TMP" "cat $TMP/scratch/probe.py"
expect "reading a script is not running it" "$(nudge "$S")" silent

S=redirect
runs 5 "$S" "$TMP" "echo 'print(1)' > $TMP/scratch/probe.py"
expect "writing a script is not running it" "$(nudge "$S")" silent

# Edit-run-edit-run debugging: every run sees a different mtime, so no run is
# "stable" and the script never reaches promotion.
S=churn
for i in 1 2 3 4; do
    printf 'print(%d)\n' "$i" > "$TMP/scratch/churn.py"
    touch -t "0101010${i}00" "$TMP/scratch/churn.py"
    track "$S" "$TMP" "python3 $TMP/scratch/churn.py"
done
expect "edited between every run stays silent" "$(nudge "$S")" silent

# --- scratch-ness is judged relative to the enclosing repo ------------------
# Repos and worktrees get checked out under /tmp; without this, running a test
# file three times would nudge you to "promote" your test suite.
echo "=== repo-relative detection ==="

mkdir -p "$TMP/myrepo/.git" "$TMP/myrepo/tests" "$TMP/myrepo/src" "$TMP/myrepo/tmp"
printf 'x = 1\n' > "$TMP/myrepo/tests/test_auth.py"
printf 'x = 1\n' > "$TMP/myrepo/src/utils.py"
printf 'x = 1\n' > "$TMP/myrepo/tmp/probe.py"

S=repo-tests
runs 3 "$S" "$TMP" "pytest $TMP/myrepo/tests/test_auth.py -x"
expect "test file in a repo under /tmp ignored" "$(nudge "$S")" silent

S=repo-src
runs 3 "$S" "$TMP" "python3 $TMP/myrepo/src/utils.py"
expect "source file in a repo under /tmp ignored" "$(nudge "$S")" silent

S=repo-tmp
runs 3 "$S" "$TMP" "python3 $TMP/myrepo/tmp/probe.py"
expect "repo-local tmp/ is still scratch" "$(nudge "$S")" fire "myrepo/tmp/probe.py"

# --- path resolution: never nudge about a file that isn't there -------------
echo "=== path resolution ==="

S=cd-prefix
runs 3 "$S" "/home/user" "cd $TMP && bash scratch/probe.sh"
OUT=$(nudge "$S")
expect "cd prefix resolves the real path" "$OUT" fire "$TMP/scratch/probe.sh"
case "$OUT" in *"/home/user/scratch/probe.sh"*) bad "cd prefix leaked the pre-cd cwd" ;; *) ok ;; esac

S=ghost
runs 4 "$S" "$TMP" "python3 $TMP/scratch/ghost.py"
expect "nonexistent script never goes stable" "$(nudge "$S")" silent

S=unexpanded
runs 4 "$S" "$TMP" 'python3 $TMPDIR/tmp_probe.py'
expect "unexpanded variable is not a path" "$(nudge "$S")" silent

S=redirect-target
printf 'x = 1\n' > "$TMP/bin/gen.py"
runs 3 "$S" "$TMP" "python3 $TMP/bin/gen.py > $TMP/scratch/out.py"
expect "redirect target is written, not run" "$(nudge "$S")" silent

# --- command shapes that must still count ----------------------------------
echo "=== command shapes ==="

S=glued
runs 3 "$S" "$TMP" "python3 $TMP/scratch/probe.py; echo done"
expect "glued semicolon still counts" "$(nudge "$S")" fire "probe.py"

S=loop
runs 3 "$S" "$TMP" "for i in 1 2; do python3 $TMP/scratch/probe.py; done"
expect "for-loop body still counts" "$(nudge "$S")" fire "probe.py"

S=flags
runs 3 "$S" "$TMP" "python3 -u $TMP/scratch/probe.py"
expect "interpreter flags don't hide the script" "$(nudge "$S")" fire "probe.py"

S=uv-with
runs 3 "$S" "$TMP" "uv run --with requests $TMP/scratch/probe.py"
expect "uv run with flag arguments counts" "$(nudge "$S")" fire "probe.py"

S=bare
runs 3 "$S" "$TMP/scratch" "python3 probe.py"
expect "bare name inside a scratch cwd counts" "$(nudge "$S")" fire "$TMP/scratch/probe.py"

S=hash
printf 'x = 1\n' > "$TMP/scratch/tmp_v#1.py"
runs 3 "$S" "$TMP" "python3 $TMP/scratch/tmp_v#1.py"
expect "# in a filename is not a comment" "$(nudge "$S")" fire 'tmp_v#1.py'

# A single huge token is the shape that makes shlex.split quadratic — the hook
# must bail out, not burn its whole timeout on every large Bash call.
S=huge
python3 - "$TMP" > "$TMP/huge.json" <<'PY'
import json, sys
# One 400 KB token — an inline program or base64 blob — with a .py mention so
# the cheap pre-filter doesn't skip it for the wrong reason.
command = "python3 -c 'x = \"" + "a" * 400_000 + "\"  # probe.py'"
print(json.dumps({"session_id": "huge", "cwd": sys.argv[1], "tool_name": "Bash",
                  "tool_input": {"command": command}}))
PY
START=$SECONDS
rc=0
python3 "$DIR/simplify_track_reuse.py" < "$TMP/huge.json" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 0 ] || bad "tracker exited $rc on a huge command"
ELAPSED=$((SECONDS - START))
if [ "$ELAPSED" -lt 3 ]; then ok; else bad "huge command took ${ELAPSED}s (must bail out fast)"; fi
expect "huge command tracked nothing" "$(nudge "$S")" silent

# --- nudge: message composition and repeat suppression ----------------------
echo "=== nudge behaviour ==="

S=once
runs 3 "$S" "$TMP" "python3 $TMP/scratch/probe.py"
expect "first stop nudges" "$(nudge "$S")" fire "probe.py"
expect "second stop stays quiet" "$(nudge "$S")" silent
track "$S" "$TMP" "python3 $TMP/scratch/probe.py"
expect "already-promoted script stays quiet" "$(nudge "$S")" silent

S=dirty
touch "$TMP/claude-simplify-dirty-${S}"
expect "dirty marker alone still nudges" "$(nudge "$S")" fire "/simplify"

S=both
touch "$TMP/claude-simplify-dirty-${S}"
runs 3 "$S" "$TMP" "python3 $TMP/scratch/probe.py"
OUT=$(nudge "$S")
expect "both signals: simplify" "$OUT" fire "/simplify"
expect "both signals: promotion"    "$OUT" fire "probe.py"

expect "clean session silent" "$(nudge no-such-session)" silent

# --- robustness: hooks must never fail the tool call ------------------------
echo "=== robustness ==="

for payload in '' 'not json' '[]' '{}' '{"session_id":"x"}' \
               '{"session_id":"x","tool_input":{"command":"python3 \"unbalanced}'; do
    rc=0
    printf '%s' "$payload" | python3 "$DIR/simplify_track_reuse.py" >/dev/null 2>&1 || rc=$?
    [ "$rc" -eq 0 ] && ok || bad "tracker exited $rc on payload: $payload"
    rc=0
    printf '%s' "$payload" | bash "$DIR/simplify_nudge.sh" >/dev/null 2>&1 || rc=$?
    [ "$rc" -eq 0 ] && ok || bad "nudge exited $rc on payload: $payload"
done

# A corrupt state file must degrade to "no candidates", not to an error.
S=corrupt
mkdir -p "$STATE_DIR" && chmod 700 "$STATE_DIR"
printf 'not json at all' > "$(state_file "$S")"
expect "corrupt state file silent" "$(nudge "$S")" silent
track "$S" "$TMP" "python3 $TMP/scratch/probe.py"
ok  # tracker survived a corrupt state file (bad() already fired if it didn't)

# One hostile entry must not suppress the valid candidates beside it, and must
# not freeze tracking for the rest of the session.
S=hostile
runs 3 "$S" "$TMP" "python3 $TMP/scratch/probe.py"
python3 - "$(state_file "$S")" <<'PY'
import json, sys
path = sys.argv[1]
state = json.load(open(path))
state["/tmp/scratch/tampered.py"] = 7
state["/tmp/scratch/typed.py"] = {"runs": "abc", "stable": None}
json.dump(state, open(path, "w"))
PY
expect "hostile state entries don't suppress candidates" "$(nudge "$S")" fire "probe.py"
track "$S" "$TMP" "python3 $TMP/scratch/probe.py"
if jq -e '."/tmp/scratch/probe.py"' "$(state_file "$S")" >/dev/null 2>&1 ||
   jq -e 'to_entries | map(select(.value | type == "object")) | length >= 1' \
        "$(state_file "$S")" >/dev/null 2>&1; then ok
else bad "tracking froze after a hostile state entry"; fi

# Session ids are used to build a filename — a traversal attempt is dropped.
S="../../escape"
rc=0
bash_event "$S" "$TMP" "python3 $TMP/scratch/probe.py" |
    python3 "$DIR/simplify_track_reuse.py" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 0 ] && [ ! -e "$TMP/../../escape" ] && ok || bad "session id traversal not rejected"

echo
TOTAL=$((PASS + FAIL))
echo "Results: $PASS passed, $FAIL failed (total $TOTAL)"
[ "$FAIL" -eq 0 ] && echo "All tests passed!"
[ "$FAIL" -eq 0 ]
