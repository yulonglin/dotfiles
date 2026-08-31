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

response = payload.get("tool_response")
rendered = json.dumps(response) if response is not None else ""

# A publish that FAILED must not be recorded as one. This matters most for the
# in-place update: its URL sits in tool_input, so without this check a rejected
# republish (org_mismatch, a version conflict) would emit a confident
# "Published <URL>" for a page that never moved. Both the structured flag and
# the known rejection wordings are checked, because the flag is not guaranteed.
def errored():
    for holder in (payload, response):
        if isinstance(holder, dict) and holder.get("is_error"):
            return True
    low = rendered.lower()
    return any(s in low for s in (
        # No apostrophes in this block: it lives inside a single-quoted shell
        # string, so one would end that string and truncate the program.
        "org_mismatch", "does not match owner org", "another of the user",
        "\"error\":", "failed to publish",
    ))

if errored():
    bail()

# The response half is where a fresh URL appears; the input half carries one
# only on an in-place update (the `url` parameter). Scanning the response first
# means an update to artifact A is never mistaken for B.
found = URL_RE.search(rendered) if rendered else None
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
#
# An index that exists but cannot be read is treated as "say nothing" rather
# than "not recorded": grep cannot tell those apart, and guessing "missing"
# would nudge on every publish forever with no way for the session to satisfy
# it. Staying quiet loses one reminder; the alternative is an unstoppable one.
if [ -f "$INDEX" ]; then
    [ -r "$INDEX" ] || exit 0
    grep -qF "$URL" "$INDEX" 2>/dev/null && exit 0
fi

# No org lookup here, deliberately. An earlier version shelled out to
# `claude auth status` and cached the result, which was dead code twice over:
# `orgName` comes back null on a claude.ai login (measured 2026-08-29 on this
# machine, on a session that published successfully), so the value was always
# the fallback string; and the cache was keyed per-UID rather than per-session,
# so two sessions in different orgs would overwrite each other's answer and the
# nudge would name the WRONG org — the one unrecoverable error this feature
# exists to prevent. A wrong org is worse than no org. The `artifacts-sync`
# skill tells Claude how to obtain the org and what to write when it is null;
# the hook's job is only to notice the row is missing.

REL="${INDEX#"$ROOT"/}"
if [ -f "$INDEX" ]; then
    WHAT="Add a row to $REL for it"
else
    WHAT="Create $REL and add it"
fi

MSG="Published $URL but it is not in $REL yet. $WHAT, following the artifacts-sync skill for the row schema — record the publishing org now, because it is not recoverable later and the gallery listing carries no repo attribution. Republish the index page in the same pass so the Markdown and the artifact stay in sync."

python3 -c '
import json, sys
print(json.dumps({"hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": sys.stdin.read().strip(),
}}))' <<< "$MSG"
exit 0
