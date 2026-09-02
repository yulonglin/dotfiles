#!/usr/bin/env bash
# Pins claude/hooks/nudge_artifact_index.sh — the PostToolUse nudge that catches
# an Artifact publish whose URL never reached the repo's ARTIFACTS.md.
#
# Both directions are asserted throughout: a nudge that fires on everything is
# as useless as one that fires on nothing, and the silent cases are the ones
# that make it tolerable to leave enabled.
#
# The interesting case is where the URL is read from. The PostToolUse payload
# shape for the Artifact tool is undocumented, so the hook scans the whole
# payload for the URL pattern instead of naming a field; these tests pin that it
# works from tool_response, falls back to tool_input, and prefers the response
# when the two disagree (an in-place update of A must never be logged as B).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Overridable so the hook can be mutation-tested against a modified copy.
HOOK="${HOOK:-$REPO_ROOT/claude/hooks/nudge_artifact_index.sh}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/artifact-index-test.XXXXXX")"
trap 'command rm -rf "$WORK"' EXIT

PASS=0
fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { PASS=$((PASS + 1)); }

URL_A="https://claude.ai/code/artifact/242e3dbb-600d-44b4-87ae-9a688542e132"
URL_B="https://claude.ai/code/artifact/aecdec3a-7fb5-43b3-8841-c4d176de379d"

REPO="$WORK/repo"
mkdir -p "$REPO"
git init -q "$REPO"

# The hook consults features.conf through hook_feature.py. Point it at a conf
# that enables the flag, so the tests exercise the hook and not the flag.
FEATCONF="$WORK/features.conf"
printf 'nudges = off\nnudges.artifact-index = on\n' > "$FEATCONF"

run_hook() {
    # $1 = payload JSON. Echoes stdout; never inherits a stray non-zero exit.
    CLAUDE_HOOK_FEATURES_FILE="$FEATCONF" bash "$HOOK" <<<"$1" 2>/dev/null || true
}

payload() {
    # $1 = action, $2 = response URL ("" for none), $3 = input URL ("" for none)
    python3 - "$1" "$2" "$3" "$REPO" <<'PY'
import json, sys
action, resp_url, in_url, cwd = sys.argv[1:5]
tool_input = {"action": action, "file_path": "page.html"}
if in_url:
    tool_input["url"] = in_url
out = {"tool_name": "Artifact", "cwd": cwd, "tool_input": tool_input}
if resp_url:
    out["tool_response"] = {"url": resp_url, "title": "A page"}
print(json.dumps(out))
PY
}

# --- fires when the URL is absent from the index -----------------------------

printf '# Artifacts\n\nnothing yet\n' > "$REPO/ARTIFACTS.md"
OUT="$(run_hook "$(payload publish "$URL_A" "")")"
grep -q "$URL_A" <<<"$OUT" || fail "no nudge for an unrecorded publish"
grep -q "ARTIFACTS.md" <<<"$OUT" || fail "nudge does not name the index file"
grep -q "additionalContext" <<<"$OUT" || fail "nudge is not PostToolUse additionalContext"
ok

# NOT `grep -qi org`: the static template contains "publishing org" regardless,
# so that assertion passes even if every org mechanism is deleted. Assert the
# thing that would actually change — the hook must NOT shell out to `claude`,
# because the org value it returned was always null and a per-UID cache made a
# WRONG org possible. A stub on PATH that reports being called is the check.
STUBDIR="$WORK/stub"
mkdir -p "$STUBDIR"
printf '#!/bin/sh\ntouch "%s/claude-was-called"\nprintf "{}"\n' "$WORK" > "$STUBDIR/claude"
chmod +x "$STUBDIR/claude"
command rm -f "$WORK/claude-was-called"
OUT="$(PATH="$STUBDIR:$PATH" CLAUDE_HOOK_FEATURES_FILE="$FEATCONF" bash "$HOOK" \
    <<<"$(payload publish "$URL_A" "")" 2>/dev/null || true)"
[ -e "$WORK/claude-was-called" ] && fail "hook shelled out to \`claude\` for the org"
grep -q "$URL_A" <<<"$OUT" || fail "nudge lost its URL once the org lookup went"
ok

# It must still TELL the session to record the org — that instruction is the
# whole point, even though the hook no longer resolves the value itself.
grep -q "publishing org" <<<"$OUT" || fail "nudge no longer asks for the org"
grep -q "artifacts-sync" <<<"$OUT" || fail "nudge does not point at the schema"
ok

# --- a failed publish is not a publish ---------------------------------------

# The in-place update is the dangerous case: its URL lives in tool_input, so a
# REJECTED republish would otherwise be announced as "Published <URL>".
for REJECTION in \
    '{"error":"org_mismatch: caller org does not match owner org"}' \
    '{"message":"This Artifact is in another of the users organizations"}' \
    '{"error":"failed to publish: version conflict"}'; do
    P=$(python3 -c '
import json, sys
print(json.dumps({"tool_name":"Artifact","cwd":sys.argv[1],
 "tool_input":{"action":"publish","file_path":"p.html","url":sys.argv[2]},
 "tool_response":json.loads(sys.argv[3])}))' "$REPO" "$URL_A" "$REJECTION")
    OUT="$(run_hook "$P")"
    [ -z "$OUT" ] || fail "nudged on a REJECTED publish: $REJECTION -> $OUT"
done
ok

# The structured error flag is honoured too, wherever it sits.
P=$(python3 -c '
import json, sys
print(json.dumps({"tool_name":"Artifact","cwd":sys.argv[1],"is_error":True,
 "tool_input":{"action":"publish","url":sys.argv[2]},
 "tool_response":{"url":sys.argv[2]}}))' "$REPO" "$URL_A")
OUT="$(run_hook "$P")"
[ -z "$OUT" ] || fail "nudged despite is_error: $OUT"
ok

# --- payload shapes the fabricated fixtures did not cover --------------------

# tool_response delivered as a bare string rather than an object.
P=$(python3 -c '
import json, sys
print(json.dumps({"tool_name":"Artifact","cwd":sys.argv[1],
 "tool_input":{"action":"publish","file_path":"p.html"},
 "tool_response":"Published "+sys.argv[2]}))' "$REPO" "$URL_A")
OUT="$(run_hook "$P")"
grep -q "$URL_A" <<<"$OUT" || fail "missed a URL in a string-valued tool_response"
ok

# An index that exists but cannot be read must NOT nudge: grep cannot tell
# "absent" from "unreadable", and guessing absent nudges forever.
printf '# Artifacts\n\nnothing yet\n' > "$REPO/ARTIFACTS.md"
chmod 000 "$REPO/ARTIFACTS.md"
if [ -r "$REPO/ARTIFACTS.md" ]; then
    chmod 644 "$REPO/ARTIFACTS.md"   # running as root; the case is untestable
else
    OUT="$(run_hook "$(payload publish "$URL_A" "")")"
    chmod 644 "$REPO/ARTIFACTS.md"
    [ -z "$OUT" ] || fail "nudged on an unreadable index: $OUT"
fi
ok

# --- stays silent when there is nothing to say -------------------------------

printf '# Artifacts\n\n| [x](%s) | live |\n' "$URL_A" > "$REPO/ARTIFACTS.md"
OUT="$(run_hook "$(payload publish "$URL_A" "")")"
[ -z "$OUT" ] || fail "nudged for a URL already in the index: $OUT"
ok

printf '# Artifacts\n\nnothing yet\n' > "$REPO/ARTIFACTS.md"
for ACTION in list read comments watch status upload_asset; do
    OUT="$(run_hook "$(payload "$ACTION" "$URL_A" "")")"
    [ -z "$OUT" ] || fail "nudged on a non-publish action: $ACTION"
done
ok

OUT="$(printf '{"tool_name":"Write","cwd":"%s","tool_input":{"file_path":"x"}}' "$REPO" | \
    CLAUDE_HOOK_FEATURES_FILE="$FEATCONF" bash "$HOOK" 2>/dev/null || true)"
[ -z "$OUT" ] || fail "nudged for a non-Artifact tool"
ok

OUT="$(run_hook 'not json at all')"
[ -z "$OUT" ] || fail "nudged on malformed input"
ok

OUT="$(run_hook "$(payload publish "" "")")"
[ -z "$OUT" ] || fail "nudged on a publish carrying no artifact URL"
ok

# Outside a git repo there is no root to hold an index, so say nothing.
OUTSIDE="$WORK/loose"
mkdir -p "$OUTSIDE"
OUT="$(printf '{"tool_name":"Artifact","cwd":"%s","tool_input":{"action":"publish"},"tool_response":{"url":"%s"}}' \
    "$OUTSIDE" "$URL_A" | CLAUDE_HOOK_FEATURES_FILE="$FEATCONF" bash "$HOOK" 2>/dev/null || true)"
[ -z "$OUT" ] || fail "nudged outside a git repo"
ok

# --- where the URL is read from ----------------------------------------------

# An in-place update carries its URL only in tool_input.
OUT="$(run_hook "$(payload publish "" "$URL_B")")"
grep -q "$URL_B" <<<"$OUT" || fail "did not fall back to tool_input.url"
ok

# When both halves carry a URL, the response is the authority: updating A must
# never be recorded against B. Asserting the operand, not just its presence.
OUT="$(run_hook "$(payload publish "$URL_A" "$URL_B")")"
grep -q "$URL_A" <<<"$OUT" || fail "response URL did not win over tool_input"
if grep -q "$URL_B" <<<"$OUT"; then fail "nudge named the tool_input URL as the published one"; fi
ok

# --- a missing index is a different message than an incomplete one -----------

command rm -f "$REPO/ARTIFACTS.md"
OUT="$(run_hook "$(payload publish "$URL_A" "")")"
grep -q "$URL_A" <<<"$OUT" || fail "no nudge when the index is absent entirely"
grep -qi "create" <<<"$OUT" || fail "absent index should say to create it"
ok

# --- the feature flag actually gates it --------------------------------------

printf 'nudges = off\nnudges.artifact-index = off\n' > "$WORK/off.conf"
printf '# Artifacts\n\nnothing yet\n' > "$REPO/ARTIFACTS.md"
OUT="$(CLAUDE_HOOK_FEATURES_FILE="$WORK/off.conf" bash "$HOOK" \
    <<<"$(payload publish "$URL_A" "")" 2>/dev/null || true)"
[ -z "$OUT" ] || fail "nudged while nudges.artifact-index = off"
ok

# --- never breaks the publish ------------------------------------------------

set +e
CLAUDE_HOOK_FEATURES_FILE="$FEATCONF" bash "$HOOK" <<<"$(payload publish "$URL_A" "")" >/dev/null 2>&1
RC=$?
set -e
[ "$RC" -eq 0 ] || fail "hook exited $RC — a PostToolUse nudge must always exit 0"
ok

echo "PASS: $PASS assertions"
