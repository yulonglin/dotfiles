#!/usr/bin/env python3
"""Stop hook: tell the user when a substantive session never consulted the advisor.

WHAT IS OBSERVABLE. The advisor is a server-side tool, and the session
transcript records each call: an assistant content block
`{"type":"server_tool_use","name":"advisor","id":"srvtoolu_..."}` followed by
an `advisor_tool_result` block (measured on Claude Code 2.1.296, 2026-10-12, in
a live session's own JSONL, and in two transcripts from 2026-10-08). Whether
the tool was offered is the `{"type":"advisor_tool","available":true,...}`
attachment. So both "offered" and "called" are read from the transcript; no
PostToolUse marker is involved, and none is needed (whether PostToolUse fires
for a server-side tool was never shown, and nothing here depends on it).

The before-work leg (consult before substantive work) is not policed: no event
can observe it without firing on every trivial session. This hook covers the
completion leg only.

WHEN IT FIRES. At Stop, once per session, only when ALL of:
  * the transcript says the advisor tool was available in this session;
  * the transcript holds no advisor call from the main agent;
  * the session did substantive work: three or more file-modifying operations,
    or a `git commit` plus at least two. A one-line fix and its commit stays
    silent on purpose.

NON-BLOCKING. It prints {"systemMessage": ...}, a warning shown to the user;
Claude stops as normal and does not see it. To hand the reminder to the model
instead, emit {"hookSpecificOutput": {"hookEventName": "Stop",
"additionalContext": MESSAGE}} -- a one-line change, which keeps the
conversation going one more turn as non-error feedback. Use that only once the
reminder has proven accurate in practice. A guard file written before the
message keeps it to once per session.

Fail-quiet everywhere: a missing transcript, an unparseable payload or an
unwritable state directory exits 0 with no output.

Feature flag: nudges.advisor-skipped (features.conf; the nudges family is off,
so the flag has to be on explicitly).
"""

from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path

EDIT_TOOLS = {"Write", "Edit", "MultiEdit", "NotebookEdit"}
# Auto mode tells sessions to edit through Bash rather than Edit/Write, so a
# count of the edit tools alone undercounts the work by a long way.
BASH_EDIT_RE = re.compile(
    r"(^|[;&|]\s*)(sed\s+-i|perl\s+-p?i|tee\s|patch\s|cat\s*>|printf[^|]*>[^|>])"
    r"|>\s*\S+\s*<<"
)
BASH_COMMIT_RE = re.compile(r"(^|[;&|]\s*)git\s+(-C\s+\S+\s+)?commit(\s|$)")
REDIRECT_TO_NULL = re.compile(r">\s*/dev/null")

EDITS_ALONE = 3
EDITS_WITH_COMMIT = 2

MESSAGE = (
    "Advisor skipped: this session changed real files and never called advisor(), "
    "though it was on offer. Ask Claude to call it now if the work needs a second "
    "look before you rely on it. (Shown once per session; nothing was blocked.)"
)


def state_dir() -> Path:
    override = os.environ.get("CLAUDE_ADVISOR_STATE_DIR")
    if override:
        return Path(override)
    return Path.home() / ".cache" / "claude-advisor"


def rows(path: Path):
    try:
        with path.open(encoding="utf-8", errors="replace") as handle:
            for line in handle:
                line = line.strip()
                if not line:
                    continue
                try:
                    row = json.loads(line)
                except Exception:
                    continue
                if isinstance(row, dict):
                    yield row
    except OSError:
        return


def advisor_called(transcript_rows) -> bool:
    """True when the main agent's transcript holds a server_tool_use for the advisor."""
    for row in transcript_rows:
        if row.get("isSidechain"):
            continue
        message = row.get("message")
        if not isinstance(message, dict):
            continue
        content = message.get("content")
        if not isinstance(content, list):
            continue
        for block in content:
            if (isinstance(block, dict) and block.get("type") == "server_tool_use"
                    and block.get("name") == "advisor"):
                return True
    return False


def advisor_available(transcript_rows) -> bool | None:
    """Last word from the availability attachments; None when never mentioned."""
    verdict = None
    for row in transcript_rows:
        attachment = row.get("attachment")
        if not isinstance(attachment, dict):
            continue
        if attachment.get("type") != "advisor_tool":
            continue
        if attachment.get("toolChange") == "remove":
            verdict = False
        else:
            verdict = bool(attachment.get("available", True))
    return verdict


def work_signals(transcript_rows) -> tuple[int, bool]:
    """(count of file-modifying operations, saw a git commit)."""
    edits = 0
    committed = False
    for row in transcript_rows:
        # A subagent's work is not the main agent's own; older Claude Code
        # versions inlined subagent rows here with isSidechain set.
        if row.get("isSidechain"):
            continue
        message = row.get("message")
        if not isinstance(message, dict):
            continue
        content = message.get("content")
        if not isinstance(content, list):
            continue
        for block in content:
            if not isinstance(block, dict) or block.get("type") != "tool_use":
                continue
            name = block.get("name")
            if name in EDIT_TOOLS:
                edits += 1
                continue
            if name != "Bash":
                continue
            command = (block.get("input") or {}).get("command")
            if not isinstance(command, str):
                continue
            if BASH_COMMIT_RE.search(command):
                committed = True
            stripped = REDIRECT_TO_NULL.sub("", command)
            if BASH_EDIT_RE.search(stripped):
                edits += 1
    return edits, committed


def substantive(edits: int, committed: bool) -> bool:
    if edits >= EDITS_ALONE:
        return True
    return committed and edits >= EDITS_WITH_COMMIT


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return 0
    if not isinstance(payload, dict):
        return 0
    if payload.get("stop_hook_active"):
        return 0

    session = payload.get("session_id")
    if not isinstance(session, str) or not session:
        return 0
    session = "".join(ch for ch in session if ch.isalnum() or ch in "-_")
    if not session:
        return 0

    transcript = payload.get("transcript_path")
    if not isinstance(transcript, str) or not transcript:
        return 0
    path = Path(transcript)
    if not path.is_file():
        return 0

    directory = state_dir()
    guard = directory / ("nudged-" + session)
    if guard.exists():
        return 0

    transcript_rows = list(rows(path))
    if advisor_available(transcript_rows) is not True:
        return 0
    if advisor_called(transcript_rows):
        return 0
    edits, committed = work_signals(transcript_rows)
    if not substantive(edits, committed):
        return 0

    # The one-shot promise rests on this file. If it cannot be written the
    # warning would repeat at every stop, so no guard means no warning.
    try:
        directory.mkdir(parents=True, exist_ok=True)
        guard.touch()
    except OSError:
        return 0

    print(json.dumps({"systemMessage": MESSAGE}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
