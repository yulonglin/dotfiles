#!/usr/bin/env python3
"""Stop hook: warn when this session's computer use is still swallowing Esc.

Claude Code's computer use installs a blocking key-down event tap (its
Esc-to-abort hotkey) for as long as the computer-use MCP stays connected. A
session that stops to wait for the user keeps that tap, so Esc does nothing in
any app until the session disconnects computer-use via /mcp or ends; a
background job held it for five hours on 2026-11-21.

The lock file alone is not evidence: it outlived the tap after a /mcp
disconnect. So the hook asks `keytaps --computer-use` whether the tap is live
and fires only when the lock names this session. Never blocks; emits a
systemMessage each turn the tap is live. Flag: nudges.computer-use-esc.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path


def find_keytaps() -> str | None:
    env = os.environ.get("KEYTAPS_BIN")
    if env:
        return env
    found = shutil.which("keytaps")
    if found:
        return found
    # Hooks may run with a minimal PATH; fall back to the repo that owns this hook.
    here = Path(__file__).resolve().parent
    for cand in (here.parent.parent / "custom_bins" / "keytaps",):
        if cand.is_file():
            return str(cand)
    return None


def main() -> int:
    if sys.platform != "darwin":
        return 0
    try:
        session = json.load(sys.stdin).get("session_id", "")
    except (ValueError, AttributeError):
        return 0
    if not session:
        return 0
    keytaps = find_keytaps()
    if not keytaps:
        return 0
    try:
        out = subprocess.run(
            [sys.executable, keytaps, "--computer-use"],
            check=False,
            capture_output=True,
            text=True,
            timeout=5,
        )
    except (OSError, subprocess.TimeoutExpired):
        return 0
    if out.returncode != 0:
        return 0
    try:
        hit = json.loads(out.stdout)
    except ValueError:
        return 0
    if hit.get("computer_use", {}).get("sessionId") != session:
        return 0
    msg = (
        "⚠️ This session still holds computer use, and its Esc-to-stop hook swallows the Esc key "
        "in every app on this Mac. When computer use is finished, disconnect computer-use via /mcp "
        "(or end the session) to give Esc back."
    )
    print(json.dumps({"systemMessage": msg}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
