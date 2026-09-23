#!/usr/bin/env python3
"""Stop hook: catch a substantive session that never consulted the advisor.

WHAT IS ACTUALLY OBSERVABLE. The advisor is meant to be called before
substantive work and again before declaring a task done. Neither leg can be
watched where you would expect:

  * The transcript does not record advisor calls at all (measured 2026-09-20
    on a live session's JSONL: no tool_use row, no tool_result row). The only
    advisor record there is the availability attachment
    `{"type":"advisor_tool","available":true,...}`. So "was it called" has to
    come from a marker written by a PostToolUse(advisor) hook —
    advisor_seen.py — and this hook reads that marker.
  * The before-work leg cannot be gated by any event without firing on every
    session. A PreToolUse gate on the first Write/Edit fires on trivial turns
    too, and a gate that fires on trivial turns gets switched off within a day,
    which is worse than no gate. So only the completion leg is enforced here;
    the reason text names the before-work leg rather than policing it.

WHEN IT FIRES. At Stop, once per session, only when ALL of:
  * the transcript says the advisor tool was available in this session;
  * no PostToolUse marker says it was called;
  * the session did substantive work: three or more file-modifying operations,
    or a `git commit` plus at least two. A one-line fix and its commit stays
    silent on purpose.

SOFT AND ONE-SHOT. It emits {"decision":"block","reason":...} once and writes
its own guard file first, so the retry always passes and no session can be
trapped. The marker channel is unverified upstream (whether PostToolUse fires
for the advisor tool could not be tested from inside a session), so the reason
tells the model what to do if the call WAS made and this hook could not see it.

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

REASON = """\
You are about to end a session that changed real files and never called advisor().

The advisor sees this whole transcript and is a stronger reviewer than you. It is
meant to be consulted twice: once BEFORE substantive work, so the approach is
checked before it hardens, and once when you believe the task is COMPLETE. This
session did neither, and the completion call is the one that is still possible.

Do this now, in order:

1. Make the deliverable durable first — write the file, save the result, commit
   the change. The advisor call takes time and an unwritten result does not
   survive the session ending.
2. Call advisor(). It takes no arguments.
3. Act on what comes back, or say plainly why you are not.

If you DID call advisor and this gate still fired, it could not see it: the call
leaves no trace in the transcript and the marker file is written by a separate
hook. Say so in one line and stop — do not call it twice to satisfy the hook.

This gate is one-shot. Your next stop goes through whatever you decide."""


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
    if (directory / ("seen-" + session)).exists():
        return 0
    guard = directory / ("nudged-" + session)
    if guard.exists():
        return 0

    transcript_rows = list(rows(path))
    if advisor_available(transcript_rows) is not True:
        return 0
    edits, committed = work_signals(transcript_rows)
    if not substantive(edits, committed):
        return 0

    # The one-shot promise rests on this file. If it cannot be written the block
    # would repeat at every stop and trap the session, so no guard means no block.
    try:
        directory.mkdir(parents=True, exist_ok=True)
        guard.touch()
    except OSError:
        return 0

    print(json.dumps({"decision": "block", "reason": REASON}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
