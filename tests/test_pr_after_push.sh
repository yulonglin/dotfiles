#!/usr/bin/env bash
# Pins claude/hooks/pr_after_push.sh — the PostToolUse(Bash) hook that opens a
# draft PR after a successful push of a non-default branch and injects the
# review-then-merge-if-simple instruction.
#
# `gh` is stubbed on PATH: the stub records every invocation and answers
# `pr list` from a file the test controls, so both the "PR exists" and the
# "create one" branches are exercised without a network. Both directions are
# asserted: a hook that fires on every git command is as useless as one that
# never fires.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="${HOOK:-$REPO_ROOT/claude/hooks/pr_after_push.sh}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/pr-after-push-test.XXXXXX")"
ROUTER_PID=""
# A failed assertion must not leave the fake router behind: it would outlive
# the suite and hold the runner's pipes open.
# `kill 0` would signal the whole process group, so an unset PID must not reach
# kill at all: an early failure would otherwise take the test runner with it.
trap '[ -z "$ROUTER_PID" ] || kill "$ROUTER_PID" 2>/dev/null || true; command rm -rf "$WORK"' EXIT

PASS=0
fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { PASS=$((PASS + 1)); }

# A repo on a feature branch with a GitHub remote.
REPO="$WORK/repo"
mkdir -p "$REPO"
git init -q -b main "$REPO"
git -C "$REPO" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git -C "$REPO" remote add origin git@github.com:someone/repo.git
git -C "$REPO" checkout -q -b feature-x

FEATCONF="$WORK/features.conf"
printf 'git.pr-after-push = on\n' > "$FEATCONF"

# gh stub: logs args; `pr list` prints $WORK/pr-list; `pr create` prints a URL.
STUB="$WORK/stub"
mkdir -p "$STUB"
cat > "$STUB/gh" <<'SH'
#!/bin/sh
echo "$*" >> "$GH_LOG"
case "$1 $2" in
  "pr list") cat "$GH_PR_LIST" 2>/dev/null ;;
  "pr create")
    # Keep whatever body was handed over, so the model-body path can be
    # asserted on its content and not merely on the flag.
    prev=""
    for arg in "$@"; do
      [ "$prev" = "--body-file" ] && cat "$arg" > "$GH_BODY" 2>/dev/null
      prev="$arg"
    done
    echo "https://github.com/someone/repo/pull/42"
    ;;
esac
SH
chmod +x "$STUB/gh"
export GH_LOG="$WORK/gh.log" GH_PR_LIST="$WORK/pr-list" GH_BODY="$WORK/gh-body.md"

run_hook() {
    # $1 = command, $2 = tool response text, $3 = transcript path (optional)
    command rm -f "$GH_LOG" "$GH_BODY"
    python3 - "$1" "$2" "$REPO" "${3:-}" <<'PY' | PATH="$STUB:$PATH" \
        CLAUDE_HOOK_FEATURES_FILE="$FEATCONF" \
        CLAUDE_PR_BODY_TOKEN_FILE="${PR_BODY_TOKEN_FILE:-$WORK/absent-token}" \
        CLAUDE_PR_BODY_BASE_URL="${PR_BODY_BASE_URL:-}" \
        CLAUDE_PR_BODY_TIMEOUT="${PR_BODY_TIMEOUT:-20}" \
        bash "$HOOK" 2>/dev/null || true
import json, sys
cmd, resp, cwd, transcript = sys.argv[1:5]
payload = {"tool_name": "Bash", "cwd": cwd,
           "tool_input": {"command": cmd},
           "tool_response": {"stdout": resp, "stderr": ""}}
if transcript:
    payload["transcript_path"] = transcript
print(json.dumps(payload))
PY
}

# --- creates a draft PR when none exists ------------------------------------
: > "$GH_PR_LIST"
OUT="$(run_hook "git add x && git commit -m m && git push -u origin feature-x" "branch 'feature-x' set up to track")"
grep -q "pull/42" <<<"$OUT" || fail "no PR url in nudge after push: $OUT"
grep -q "additionalContext" <<<"$OUT" || fail "not PostToolUse additionalContext"
# Assert the flags, not one exact spelling: the argument ORDER is gh's business
# and an exact-string match here broke on 63f71da (#120) the moment --title was
# inserted between --fill and --head.
grep -q "pr create .*--draft" "$GH_LOG" || fail "gh pr create not called as draft: $(cat "$GH_LOG")"
grep -q "pr create .*--fill" "$GH_LOG" || fail "gh pr create not called with --fill: $(cat "$GH_LOG")"
grep -q "pr create .*--head feature-x" "$GH_LOG" || fail "gh pr create not called for the pushed branch: $(cat "$GH_LOG")"
# #120's actual subject, which had no test and so regressed silently: --fill
# takes its title from the commit only when the branch is exactly one commit
# ahead, and humanises the BRANCH NAME otherwise, so the hook passes an explicit
# --title from the last commit subject.
# "init" is the fixture repo's real last commit subject; the tool-call string
# the hook is fed mentions `git commit -m m` but never runs it, so a hook that
# passed "m" would be parsing the command line instead of reading git.
grep -q "pr create .*--title init" "$GH_LOG" || fail "explicit --title from the last commit subject missing: $(cat "$GH_LOG")"
grep -qi "merge it yourself" <<<"$OUT" || fail "review/merge instruction missing"
grep -q "AskUserQuestion" <<<"$OUT" || fail "fallback to asking the user missing"
ok

# --- reports an existing PR instead of creating another ---------------------
echo 7 > "$GH_PR_LIST"
OUT="$(run_hook "git push" "Everything up-to-date")"
grep -q "PR #7" <<<"$OUT" || fail "existing PR not reported: $OUT"
grep -q "pr create" "$GH_LOG" && fail "created a second PR when one was open"
ok

# --- silent cases ------------------------------------------------------------
: > "$GH_PR_LIST"
[ -z "$(run_hook "git status" "")" ] || fail "fired on a non-push"
[ -z "$(run_hook "git push origin --delete feature-x" "")" ] || fail "fired on a branch delete"
[ -z "$(run_hook "git push --tags" "")" ] || fail "fired on a tags-only push"
[ -z "$(run_hook "git push" "! [rejected] feature-x -> feature-x (fetch first)")" ] || fail "fired on a rejected push"
[ -z "$(run_hook "git push" "fatal: could not read from remote repository")" ] || fail "fired on a failed push"
ok

git -C "$REPO" checkout -q main
[ -z "$(run_hook "git push" "main -> main")" ] || fail "fired on a push of main"
git -C "$REPO" checkout -q feature-x
ok

# --- feature flag off is silent ---------------------------------------------
printf 'git.pr-after-push = off\n' > "$FEATCONF"
[ -z "$(run_hook "git push" "ok")" ] || fail "fired with git.pr-after-push = off"
printf 'git.pr-after-push = on\n' > "$FEATCONF"
ok

# ═══════════════════════════════════════════════════════════════════════════
# The model-written body (pr_body_model.py through the model-router gateway).
# A fake router stands in for the gateway: it records the request so the PROMPT
# can be asserted (the model's own wording cannot be), and answers in the
# Anthropic response shape. The failure directions matter more than the happy
# one — the PR must still open when the gateway is absent, refusing or slow.
# ═══════════════════════════════════════════════════════════════════════════

cat > "$WORK/fake_router.py" <<'PY'
import json, sys, time
from http.server import BaseHTTPRequestHandler, HTTPServer

status = int(sys.argv[1])
record = sys.argv[2]
delay = float(sys.argv[3]) if len(sys.argv) > 3 else 0.0

class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("content-length", 0))
        raw = self.rfile.read(length)
        with open(record, "ab") as fh:
            fh.write(raw + b"\n")
        if delay:
            time.sleep(delay)
        if status != 200:
            self.send_response(status)
            self.end_headers()
            self.wfile.write(b'{"error":"cooldown"}')
            return
        body = json.dumps({"content": [{"type": "text", "text": FAKE_BODY}]}).encode()
        self.send_response(200)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass

FAKE_BODY = """## Motivation

The hook opened PRs with bodies nobody could review.

## Implementation

`claude/hooks/pr_body_model.py` builds the prompt; `pr_after_push.sh` uses it.

## Tests

$ python3 tests/test_advisor_skipped.py -- passed."""

server = HTTPServer(("127.0.0.1", 0), Handler)
print(server.server_address[1], flush=True)
server.serve_forever()
PY

start_router() {  # $1 = http status to answer with, $2 = seconds to stall first
    command rm -f "$WORK/router-requests"
    # Both streams go to files: a background process still holding the parent's
    # stdout keeps every enclosing $(...) open, which reads exactly like a hang.
    python3 "$WORK/fake_router.py" "$1" "$WORK/router-requests" "${2:-0}" \
        > "$WORK/router-port" 2>/dev/null &
    ROUTER_PID=$!
    for _ in $(seq 1 50); do
        PORT="$(cat "$WORK/router-port" 2>/dev/null)"
        [ -n "$PORT" ] && break
        sleep 0.1
    done
    [ -n "$PORT" ] || fail "fake router did not start"
    echo tok > "$WORK/token"
    export PR_BODY_TOKEN_FILE="$WORK/token"
    export PR_BODY_BASE_URL="http://127.0.0.1:$PORT/t/tok"
}
stop_router() {
    kill "$ROUTER_PID" 2>/dev/null || true
    wait "$ROUTER_PID" 2>/dev/null || true
    unset PR_BODY_TOKEN_FILE PR_BODY_BASE_URL
}

# A transcript holding one test run, which is where the Tests section's facts
# have to come from: git cannot know what was run.
python3 - "$WORK/transcript.jsonl" <<'PY'
import json, sys
rows = [
    {"type": "assistant", "message": {"content": [
        {"type": "tool_use", "id": "t1", "name": "Bash",
         "input": {"command": "python3 tests/test_advisor_skipped.py"}}]}},
    {"type": "user", "message": {"content": [
        {"type": "tool_result", "tool_use_id": "t1",
         "content": "Ran 15 tests in 1.5s\n\nOK"}]}},
    {"type": "assistant", "message": {"content": [
        {"type": "tool_use", "id": "t2", "name": "Bash",
         "input": {"command": "ls -la"}}]}},
]
with open(sys.argv[1], "w") as fh:
    for r in rows:
        fh.write(json.dumps(r) + "\n")
PY

# A real change on the branch, so the prompt has a diff and a symbol to carry.
# It is committed HERE, after the --title assertions above, which depend on the
# fixture's last commit subject being "init".
cat > "$REPO/widget.py" <<'PY'
class Widget:
    def render(self):
        return 1
PY
git -C "$REPO" add widget.py
git -C "$REPO" -c user.name=t -c user.email=t@t commit -q -m "Add the widget"

# --- a reachable gateway writes the body ------------------------------------
: > "$GH_PR_LIST"
start_router 200
OUT="$(run_hook "git push -u origin feature-x" "branch set up" "$WORK/transcript.jsonl")"
grep -q "pr create .*--body-file" "$GH_LOG" || fail "model body not passed to gh: $(cat "$GH_LOG")"
grep -q -- "--fill" "$GH_LOG" && fail "--fill used alongside a model-written body"
grep -q "## Motivation" "$GH_BODY" || fail "body has no motivation section: $(cat "$GH_BODY")"
grep -q "## Implementation" "$GH_BODY" || fail "body has no implementation section"
# The attribution names the model, not the routing alias (rules/communication.md).
grep -q "drafted by GPT-6 Astra" "$GH_BODY" || fail "body does not name the exact model that wrote it: $(tail -2 "$GH_BODY")"
grep -qi "model-written summary" <<<"$OUT" || fail "nudge does not say the body was model-written: $OUT"
# The prompt is ours, so it IS assertable: the four required sections, the
# transcript's test evidence, and the bar on inventing any of it.
REQ="$WORK/router-requests"
grep -q "test_advisor_skipped" "$REQ" || fail "test evidence from the transcript never reached the model"
grep -q "No test runs found in the session transcript" "$REQ" || fail "no instruction for an empty test list"
grep -q "Never invent a test" "$REQ" || fail "nothing forbids inventing test results"
grep -q "Mermaid diagram ONLY when" "$REQ" || fail "diagram is not conditional"
grep -q "widget.py" "$REQ" || fail "the diff never reached the model"
grep -q "Widget" "$REQ" || fail "the changed class never reached the model"
grep -q "Add the widget" "$REQ" || fail "the commit subjects never reached the model"
stop_router
ok

# --- a refusing gateway still opens the PR, with a plainer body -------------
: > "$GH_PR_LIST"
start_router 429
OUT="$(run_hook "git push -u origin feature-x" "branch set up" "$WORK/transcript.jsonl")"
grep -q "pull/42" <<<"$OUT" || fail "no PR opened when the gateway refused: $OUT"
grep -q "pr create .*--fill" "$GH_LOG" || fail "did not fall back to --fill on a 429: $(cat "$GH_LOG")"
grep -q -- "--body-file" "$GH_LOG" && fail "passed an empty body file after a gateway failure"
stop_router
ok

# --- a slow gateway is bounded by the budget, not by the hook's own timeout --
# Two per-attempt timeouts could outlast the 90s hook timeout in settings.json,
# and a hook killed mid-flight opens NO PR. The budget is total, so the whole
# generator gives up inside it and the push still ends in a draft PR.
: > "$GH_PR_LIST"
start_router 200 30
SECONDS=0
OUT="$(PR_BODY_TIMEOUT=8 run_hook "git push -u origin feature-x" "branch set up" "$WORK/transcript.jsonl")"
ELAPSED=$SECONDS
grep -q "pull/42" <<<"$OUT" || fail "no PR opened when the gateway stalled: $OUT"
grep -q "pr create .*--fill" "$GH_LOG" || fail "a stalled gateway did not fall back to --fill"
[ "$ELAPSED" -le 20 ] || fail "the generator ran for ${ELAPSED}s against an 8s budget"
stop_router
ok

# --- no router at all is the same story -------------------------------------
: > "$GH_PR_LIST"
OUT="$(run_hook "git push -u origin feature-x" "branch set up" "$WORK/transcript.jsonl")"
grep -q "pull/42" <<<"$OUT" || fail "no PR opened with no gateway: $OUT"
grep -q "pr create .*--fill" "$GH_LOG" || fail "did not fall back to --fill with no token"
ok

# --- the generator alone: fails closed, never prints half a body ------------
GEN="$REPO_ROOT/claude/hooks/pr_body_model.py"
set +e
GEN_OUT="$(CLAUDE_PR_BODY_TOKEN_FILE=/nonexistent/token CLAUDE_PR_BODY_TIMEOUT=5 \
    python3 "$GEN" --repo "$REPO" --branch feature-x 2>/dev/null)"
GEN_RC=$?
set -e
[ "$GEN_RC" -ne 0 ] || fail "generator exited 0 with no ingress token"
[ -z "$GEN_OUT" ] || fail "generator printed a body it could not have got: $GEN_OUT"
ok

# --- the model-body sub-flag can be switched off without losing the PR ------
: > "$GH_PR_LIST"
printf 'git.pr-after-push = on\ngit.pr-after-push.model-body = off\n' > "$FEATCONF"
start_router 200
OUT="$(run_hook "git push -u origin feature-x" "branch set up" "$WORK/transcript.jsonl")"
grep -q "pr create .*--fill" "$GH_LOG" || fail "sub-flag off did not fall back to --fill"
[ -s "$WORK/router-requests" ] && fail "called the gateway with the sub-flag off"
stop_router
printf 'git.pr-after-push = on\n' > "$FEATCONF"
ok

echo "test_pr_after_push: $PASS groups passed"
