#!/usr/bin/env bash
# PostToolUse hook (matcher: Artifact): after a successful publish, nudge Claude
# to record the page in the repo's ARTIFACTS.md.
#
# `rules/artifact-index.md`: the row is written at publish time or not at all —
# the gallery carries no repo attribution and no publishing org, so attribution
# reconstructed later is guesswork. This hook is the backstop for a turn that
# publishes and then forgets.
#
# Advisory only. Emits hookSpecificOutput.additionalContext and always exits 0;
# a PostToolUse hook cannot un-publish anything, so blocking here would buy
# nothing and a broken nudge must never break a publish.
#
# Quiet when there is nothing to say: a non-publish action, a publish whose URL
# already appears in ARTIFACTS.md, or a cwd outside a git repo all exit silently.
#
# The URL is found by scanning the whole hook payload for the artifact URL
# pattern rather than by reading a named field. The PostToolUse payload shape
# for the Artifact tool is not documented, so a field-name dependency would fail
# silently the day it changes; the URL pattern is the stable part.
#
# Feature flag: nudges.artifact-index (features.conf). Note features.conf sets
# `nudges = off` wholesale, so this flag must be listed explicitly to run.
set -uo pipefail

INPUT=$(cat)

HOOK_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 0
if [ -r "$HOOK_DIR/hook_feature.py" ] && \
   ! python3 "$HOOK_DIR/hook_feature.py" enabled nudges.artifact-index 2>/dev/null; then
    exit 0
fi

# "<url>\t<cwd>" for a publish worth nudging on; empty first field otherwise.
# shellcheck disable=SC2016  # single quotes protect the Python source, deliberately
PARSED=$(printf '%s' "$INPUT" | python3 -c '
import json, re, sys

URL_RE = re.compile(r"https://claude\.ai/code/artifact/[0-9a-fA-F-]{36}")

def bail():
    print("\t")
    sys.exit(0)

try:
    payload = json.load(sys.stdin)
    if not isinstance(payload, dict):
        bail()
except Exception:
    bail()

name = payload.get("tool_name")
if name is not None and name != "Artifact":
    bail()

tool_input = payload.get("tool_input")
if not isinstance(tool_input, dict):
    tool_input = {}
# Only a publish creates or moves a URL. Every read-only action (list, read,
# comments, status, ...) leaves the index correct as it stands.
if (tool_input.get("action") or "publish") != "publish":
    bail()

# The response half of the payload is where a fresh URL appears; the input half
# carries one only on an in-place update (the `url` parameter). Scanning the
# response first means an update to artifact A is never mistaken for B.
response = payload.get("tool_response")
found = URL_RE.search(json.dumps(response)) if response is not None else None
if not found:
    found = URL_RE.search(json.dumps(tool_input))
if not found:
    bail()

cwd = payload.get("cwd") or ""
print(found.group(0) + "\t" + (cwd if isinstance(cwd, str) else ""))
' 2>/dev/null) || exit 0

URL="${PARSED%%$'\t'*}"
CWD="${PARSED#*$'\t'}"
[ -n "$URL" ] || exit 0

[ -n "$CWD" ] && [ -d "$CWD" ] || CWD="$PWD"
ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -n "$ROOT" ] || exit 0

INDEX="$ROOT/ARTIFACTS.md"

# Already recorded — the turn did its job, so say nothing.
if [ -f "$INDEX" ] && grep -qF "$URL" "$INDEX" 2>/dev/null; then
    exit 0
fi

# The publishing org cannot be recovered after the fact, so hand it over now.
# Cached per session: `claude auth status` spawns a process, and a long session
# can republish many times.
ORG=""
CACHE="${TMPDIR:-/tmp}/claude-artifact-org-$(id -u).json"
if [ ! -s "$CACHE" ] || [ -n "$(find "$CACHE" -mmin +60 2>/dev/null)" ]; then
    claude auth status >"$CACHE" 2>/dev/null || true
fi
if [ -s "$CACHE" ]; then
    ORG=$(python3 -c '
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    print(d.get("orgName") or d.get("email") or "")
except Exception:
    print("")
' "$CACHE" 2>/dev/null)
fi
[ -n "$ORG" ] || ORG="unknown — run \`claude auth status\` and record orgName"

REL="${INDEX#"$ROOT"/}"
if [ -f "$INDEX" ]; then
    WHAT="Add a row to $REL for it"
else
    WHAT="Create $REL (see ~/.claude/rules/artifact-index.md for the row schema) and add it"
fi

MSG="Published $URL but it is not in $REL yet. $WHAT, recording org \"$ORG\" — the publishing org is not recoverable later, and the gallery listing carries no repo attribution. Republish the index page in the same pass so the Markdown and the artifact stay in sync."

python3 -c '
import json, sys
print(json.dumps({"hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": sys.stdin.read().strip(),
}}))' <<< "$MSG"
exit 0
