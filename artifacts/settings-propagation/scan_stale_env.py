#!/usr/bin/env python3
"""Snapshot which running processes still carry a settings-derived env var.

Reads every readable /proc/<pid>/environ, reports the processes that still
carry VAR, and counts the denominator the page quotes: processes whose
command line mentions "claude" (the scan's own pgrep/grep is excluded).

    python3 scan_stale_env.py [VAR] > scan.json
"""

import json
import os
import re
import subprocess
import sys

VAR = sys.argv[1] if len(sys.argv) > 1 else "CLAUDE_CODE_ATTRIBUTION_HEADER"
SELF = os.getpid()


def read(pid, name):
    with open(f"/proc/{pid}/{name}", "rb") as fh:
        return fh.read().decode("utf-8", "replace")


def started(pid):
    out = subprocess.run(
        ["ps", "-o", "lstart=", "-p", str(pid)], capture_output=True, text=True
    )
    return out.stdout.strip()


def redact(cmdline):
    """Blank out paths to per-session credential files before the scan is committed."""
    return re.sub(r"(--token-file\s+)\S+", r"\1<redacted>", cmdline)


def classify(cmdline):
    head = cmdline.split(" ", 1)[0]
    if head.endswith("socat") and "/tmp/claude/claude-http-" in cmdline:
        return "socat forwarder for a Claude Code HTTP socket"
    if head.endswith("zsh") or head.endswith("bash"):
        return "shell-snapshot wrapper"
    if cmdline.endswith("claude agents") or "/claude agents " in cmdline:
        return "claude agents TUI"
    if "http.server" in cmdline:
        return "python3 -m http.server"
    return "other"


carriers, claude_matching, unreadable = [], [], 0

for entry in sorted(os.listdir("/proc")):
    if not entry.isdigit():
        continue
    pid = int(entry)
    if pid == SELF:
        continue
    try:
        cmdline = read(pid, "cmdline").replace("\0", " ").strip()
    except OSError:
        continue
    if not cmdline:
        continue  # kernel thread
    if "claude" in cmdline.lower():
        claude_matching.append({"pid": pid, "cmdline": redact(cmdline)})
    try:
        environ = read(pid, "environ")
    except OSError:
        unreadable += 1
        continue
    values = [
        line.split("=", 1)[1]
        for line in environ.split("\0")
        if line.startswith(VAR + "=")
    ]
    if values:
        carriers.append(
            {
                "pid": pid,
                "value": values[0],
                "started": started(pid),
                "kind": classify(cmdline),
                "cmdline": redact(cmdline),
            }
        )

for c in carriers:
    c["claude_matching"] = "claude" in c["cmdline"].lower()

by_kind = {}
for c in carriers:
    by_kind[c["kind"]] = by_kind.get(c["kind"], 0) + 1

json.dump(
    {
        "var": VAR,
        "scanned_at": subprocess.run(
            ["date", "-u", "+%Y-%m-%dT%H:%M:%SZ"], capture_output=True, text=True
        ).stdout.strip(),
        "host": os.uname().nodename,
        "carriers_total": len(carriers),
        "carriers_claude_matching": sum(1 for c in carriers if c["claude_matching"]),
        "carriers_by_kind": by_kind,
        "claude_matching_total": len(claude_matching),
        "environ_unreadable": unreadable,
        "carriers": carriers,
        "claude_matching": claude_matching,
    },
    sys.stdout,
    indent=2,
)
print()
