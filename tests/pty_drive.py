#!/usr/bin/env python3
"""Run a command on a real pty whose stdin stays open but silent, and report
whether it drew a full-screen UI, when, and how it exited.

This is the one harness that reproduces "I ran ./install.sh and nothing
happened": a TTY exists, so every `[[ -t 0 ]]` guard is bypassed, yet nobody
types. `</dev/null` cannot reproduce it (every read returns EOF at once) and
util-linux `script` cannot either (it forwards EOF from its own stdin into the
pty). Only a pty nobody writes to behaves like a human who never types.

    pty_drive.py [--deadline S] [--expect REGEX] [--send-on-expect BYTES]
                 [--env K=V ...] -- cmd args...

Prints one JSON object on stdout:
    exit        integer exit status, or null if the deadline fired
    expect_at   seconds until --expect first matched, or null
    elapsed     wall-clock seconds
    output      everything written to the pty (capped at 1 MB), escapes kept

Exit status: 0 if the child exited before the deadline, 124 on deadline.
The caller asserts on the JSON, not on this status, so a stalled child is a
reported fact rather than a crash of the harness.
"""
import argparse
import fcntl
import json
import os
import pty
import re
import select
import signal
import struct
import sys
import termios
import time


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--deadline", type=float, default=60.0)
    ap.add_argument("--expect", default=None, help="regex over the pty output")
    ap.add_argument("--send-on-expect", default=None,
                    help="bytes (python escapes) written to the pty once --expect matches")
    ap.add_argument("--send-delay", type=float, default=0.3,
                    help="seconds between the match and the send, so the UI is ready")
    ap.add_argument("--env", action="append", default=[], metavar="K=V")
    ap.add_argument("cmd", nargs=argparse.REMAINDER)
    args = ap.parse_args()
    cmd = args.cmd[1:] if args.cmd and args.cmd[0] == "--" else args.cmd
    if not cmd:
        ap.error("no command")

    env = dict(os.environ)
    for kv in args.env:
        k, _, v = kv.partition("=")
        env[k] = v
    # A pty with no size makes some TUIs refuse to draw; give it a real one.
    env.setdefault("TERM", "xterm-256color")
    env["COLUMNS"], env["LINES"] = "100", "40"

    expect = re.compile(args.expect.encode()) if args.expect else None
    to_send = (args.send_on_expect.encode().decode("unicode_escape").encode("latin-1")
               if args.send_on_expect else None)

    pid, fd = pty.fork()
    if pid == 0:  # child
        os.execvpe(cmd[0], cmd, env)
    # COLUMNS/LINES only reach shell tools; a TUI asks the kernel for the pty's
    # size, and a fresh pty is 0x0, which makes ratatui render nothing at all.
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 100, 0, 0))

    buf = b""
    t0 = time.monotonic()
    expect_at = None
    send_at = None
    status = None
    while True:
        now = time.monotonic() - t0
        if now > args.deadline:
            break
        r, _, _ = select.select([fd], [], [], 0.05)
        if r:
            try:
                chunk = os.read(fd, 65536)
            except OSError:
                chunk = b""
            if chunk:
                buf += chunk
                if expect and expect_at is None and expect.search(buf):
                    expect_at = time.monotonic() - t0
                    if to_send is not None:
                        send_at = expect_at + args.send_delay
        if send_at is not None and time.monotonic() - t0 >= send_at:
            os.write(fd, to_send)
            send_at = None
        wpid, st = os.waitpid(pid, os.WNOHANG)
        if wpid == pid:
            status = st
            # drain whatever is left in the pty buffer
            while True:
                r, _, _ = select.select([fd], [], [], 0.05)
                if not r:
                    break
                try:
                    chunk = os.read(fd, 65536)
                except OSError:
                    break
                if not chunk:
                    break
                buf += chunk
            break

    if status is None:
        os.kill(pid, signal.SIGKILL)
        os.waitpid(pid, 0)
        code = None
    elif os.WIFEXITED(status):
        code = os.WEXITSTATUS(status)
    else:
        code = 128 + os.WTERMSIG(status)
    os.close(fd)

    # The whole transcript, capped high: callers grep it for a banner printed
    # in the first lines as well as for the completion line at the end.
    output = buf[-1_000_000:].decode("utf-8", "replace")
    print(json.dumps({
        "exit": code,
        "expect_at": None if expect_at is None else round(expect_at, 3),
        "elapsed": round(time.monotonic() - t0, 3),
        "output": output,
    }))
    return 0 if code is not None else 124


if __name__ == "__main__":
    sys.exit(main())
