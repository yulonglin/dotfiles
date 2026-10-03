#!/usr/bin/env python3
"""PostToolUse(advisor): record that this session consulted the advisor.

THIS FILE EXISTS BECAUSE THE TRANSCRIPT DOES NOT RECORD THE CALL. Measured
2026-09-20 against a live session's own JSONL: an advisor() call produces no
`tool_use` row, no `tool_result` row, and no attachment — the only advisor
record in a transcript is the availability attachment
`{"type":"advisor_tool","available":true,"model":...}` emitted once when the
tool is offered. So a Stop hook reading the transcript can see WHETHER the
tool was offered but never whether it was used, and the marker this hook
writes is the only channel left.

Marker: <state>/seen-<session_id>, an empty file. Read by
nudge_advisor_skipped.py. The directory is ~/.cache/claude-advisor rather than
TMPDIR so the two hook processes agree on it whatever the session's temp dir.

Always exits 0 and prints nothing: a marker writer that can fail a tool call
would be worse than the skip it guards against.
"""

from __future__ import annotations

import json
import os
import sys
import time
from pathlib import Path

MAX_MARKER_AGE_S = 7 * 24 * 3600


def state_dir() -> Path:
    override = os.environ.get("CLAUDE_ADVISOR_STATE_DIR")
    if override:
        return Path(override)
    return Path.home() / ".cache" / "claude-advisor"


def prune(directory: Path) -> None:
    """Drop markers from sessions that ended days ago; never fail on one."""
    cutoff = time.time() - MAX_MARKER_AGE_S
    try:
        entries = list(directory.iterdir())
    except OSError:
        return
    for entry in entries:
        try:
            if entry.is_file() and entry.stat().st_mtime < cutoff:
                entry.unlink()
        except OSError:
            continue


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return 0
    if not isinstance(payload, dict):
        return 0

    # The matcher in settings.json already selects the advisor tool; this is the
    # belt to that braces, so a broadened matcher cannot silently mark every tool.
    name = payload.get("tool_name")
    if name is not None and name != "advisor":
        return 0

    session = payload.get("session_id")
    if not isinstance(session, str) or not session:
        return 0
    session = "".join(ch for ch in session if ch.isalnum() or ch in "-_")
    if not session:
        return 0

    directory = state_dir()
    try:
        directory.mkdir(parents=True, exist_ok=True)
        (directory / ("seen-" + session)).touch()
    except OSError:
        return 0
    prune(directory)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
