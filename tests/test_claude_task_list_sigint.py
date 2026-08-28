#!/usr/bin/env python3
"""Ctrl-C during a `claude -t <name>` session must not leave its ID in the shell.

The launch is `-t`, not bare: the wrapper no longer auto-generates an ID, so a
bare launch sets nothing and this test would pass without exercising anything.
`-t` is the one path that still binds the variable, and therefore the one that
could still leak.

This needs a real PTY with job control: a manual save/restore after
`command claude` is silently SKIPPED when SIGINT aborts the zsh function, so
the leak reappears in a shell that looks fixed. Only an interactive shell
reproduces it -- a script that sends itself SIGINT does not, because the signal
goes to a different process group.

The wrapper defends against this by binding the ID with `local -x`, which zsh
unwinds on any exit from the function, signals included. There is no restore
code left for a signal to skip.

Run: python3 tests/test_claude_task_list_sigint.py
Exit 0 = pass, 1 = fail, 77 = skipped (no zsh).
"""

from __future__ import annotations

import os
import pty
import re
import select
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
MARKER = "TLID_AFTER_INTERRUPT"


def read_until(fd: int, needle: str, timeout: float = 10.0) -> str:
    """Accumulate PTY output until needle appears or timeout elapses."""
    buf = ""
    deadline = time.time() + timeout
    while time.time() < deadline:
        remaining = deadline - time.time()
        try:
            ready, _, _ = select.select([fd], [], [], min(0.4, remaining))
        except OSError:
            break
        if not ready:
            continue
        try:
            chunk = os.read(fd, 4096)
        except OSError:  # child exited, PTY closed
            break
        if not chunk:
            break
        buf += chunk.decode(errors="replace")
        if needle in buf:
            break
    return buf


def main() -> int:
    if not shutil.which("zsh"):
        print("SKIP: zsh not available")
        return 77

    with tempfile.TemporaryDirectory(dir=REPO / "tmp") as tmp:
        tmpdir = Path(tmp)
        fakebin = tmpdir / "bin"
        fakebin.mkdir()
        # A fake `claude` that blocks, so we can interrupt it mid-session.
        fake = fakebin / "claude"
        fake.write_text("#!/bin/sh\necho FAKE_CLAUDE_RUNNING\nsleep 30\n")
        fake.chmod(0o755)

        # Minimal interactive rc: job control on, wrapper sourced, fake on PATH.
        zdotdir = tmpdir / "zdot"
        zdotdir.mkdir()
        (zdotdir / ".zshrc").write_text(
            f"export PATH={fakebin}:$PATH\n"
            "activate_venv() {{ :; }}\n"
            "unset DOTFILES_TELEGRAM_BOT_SECRET\n"
            "unset CLAUDE_CODE_TASK_LIST_ID\n"
            f"source {REPO}/config/aliases/claude.sh\n"
            "activate_venv() {{ :; }}\n"
            "unset zle_bracketed_paste\n"
            "PS1='READY> '\n".replace("{{", "{").replace("}}", "}")
        )

        env = dict(os.environ)
        env["ZDOTDIR"] = str(zdotdir)
        env.pop("CLAUDE_CODE_TASK_LIST_ID", None)
        env.pop("CLAUDE_CODE_TASK_LIST_PIN", None)

        pid, fd = pty.fork()
        if pid == 0:  # child
            os.chdir(REPO)
            os.execvpe("zsh", ["zsh", "-i"], env)
            os._exit(127)

        try:
            read_until(fd, "READY>")
            # `-t` so there IS an ID to leak: a bare launch sets nothing now,
            # which would make this test pass for the wrong reason.
            os.write(fd, b"claude -t sigintprobe\n")
            if "FAKE_CLAUDE_RUNNING" not in read_until(fd, "FAKE_CLAUDE_RUNNING"):
                print("FAIL: fake claude never started; harness is broken")
                return 1

            time.sleep(0.4)
            os.write(fd, b"\x03")  # Ctrl-C to the foreground process group
            read_until(fd, "READY>", timeout=6.0)

            # Build the marker at runtime so the typed command line does not
            # itself contain it — the PTY echoes what we type, and a needle
            # that matches the echo would return before the real output lands.
            head, tail = MARKER[:4], MARKER[4:]
            os.write(
                fd,
                f"printf '%s%s=[%s]\\n' {head} {tail} "
                '"${CLAUDE_CODE_TASK_LIST_ID-unset}"\n'.encode().decode().encode(),
            )
            out = read_until(fd, MARKER + "=[", timeout=6.0)
        finally:
            try:
                os.write(fd, b"\nexit\n")
            except OSError:
                pass
            os.close(fd)
            try:
                os.waitpid(pid, 0)
            except ChildProcessError:
                pass

    # The echoed command itself appears in the PTY; take the last occurrence,
    # which is the shell's output rather than the typed line.
    matches = re.findall(rf"{MARKER}=\[([^\]]*)\]", out)
    matches = [m for m in matches if "CLAUDE_CODE_TASK_LIST_ID" not in m]
    if not matches:
        print("FAIL: could not read the variable back from the PTY")
        print(f"--- raw output ---\n{out}")
        return 1

    value = matches[-1].strip()
    if value == "unset":
        print("PASS: no task-list ID left in the shell after Ctrl-C")
        return 0
    print(f"FAIL: Ctrl-C leaked a task-list ID into the shell: [{value}]")
    return 1


if __name__ == "__main__":
    sys.exit(main())
