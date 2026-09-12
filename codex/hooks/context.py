#!/usr/bin/env python3
"""Small, read-only context hooks using the Codex hook JSON protocol."""

import json
import os
from pathlib import Path
import re
import subprocess
import sys


def emit(event, message):
    if message:
        print(json.dumps({"hookSpecificOutput": {
            "hookEventName": event, "additionalContext": message,
        }}))


def modern_tools(command):
    messages = []
    if re.search(r"(?:^|[;&|\n])\s*(?:grep|egrep|fgrep)\b", command):
        messages.append("Prefer rg for text searches when available.")
    if re.search(r"(?:^|[;&|\n])\s*find\b", command):
        messages.append("Prefer rg --files for repository file discovery when appropriate.")
    if re.search(r"(?:^|[;&|\n])\s*sed\s+-[^\s]*i", command):
        messages.append("Prefer apply_patch for scoped file edits when that tool is available.")
    return " ".join(messages)


def dependency_install(command):
    pattern = (
        r"^\s*(?:(?:npm|pnpm|bun)\s+(?:install|i|ci|add)|"
        r"pip3?\s+install|uv\s+(?:pip\s+install|add|sync)|"
        r"python[\d.]*\s+-m\s+pip\s+install)\b"
    )
    if re.search(pattern, command):
        return ("Before adding dependencies, check the package name, provenance, "
                "maintenance, and existing project lockfile. Follow the project's "
                "package manager and dependency policy.")
    return ""


def session_start(payload):
    cwd = payload.get("cwd")
    if not isinstance(cwd, str) or not cwd:
        return ""
    directory = Path(cwd).resolve()
    if not directory.is_dir():
        return ""
    messages = []
    try:
        result = subprocess.run(
            ["git", "-C", str(directory), "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, timeout=2,
        )
        if result.returncode == 0:
            root = Path(result.stdout.strip()).resolve()
            if root != directory:
                messages.append(f"Session cwd is {directory}; repository root is {root}. "
                                "Resolve repository-relative paths from that root.")
    except (OSError, subprocess.TimeoutExpired):
        pass
    expected = directory / ".venv"
    if expected.is_dir():
        active = os.environ.get("VIRTUAL_ENV")
        if active and Path(active).resolve() != expected.resolve():
            messages.append(f"VIRTUAL_ENV points to {active}, but this project's environment "
                            f"is {expected}. Check the environment before running Python.")
        try:
            activation = (expected / "bin" / "activate").read_text()
            match = re.search(r"^\s*(?:export\s+)?VIRTUAL_ENV=(.+)$", activation, re.MULTILINE)
            if match:
                baked = match.group(1).strip().strip("\"'")
                # Ignore shell expressions; only compare literal absolute paths.
                if baked.startswith("/") and Path(baked).resolve() != expected.resolve():
                    messages.append(f"{expected}/bin/activate contains stale path {baked}. "
                                    "Recreate the environment with the project's existing "
                                    "dependency workflow before using it.")
        except OSError:
            pass
    notes = directory / "NOTES.md"
    try:
        if notes.is_file():
            with notes.open("rb") as handle:
                handle.seek(0, os.SEEK_END)
                handle.seek(max(0, handle.tell() - 16_384))
                recent = handle.read(16_384).decode("utf-8", errors="replace")
            recent = "\n".join(recent.splitlines()[-120:])
            if recent:
                messages.append("=== RECENT EXPERIMENT LOG (NOTES.md; last 120 lines, "
                                "up to 16 KiB; file content) ===\n" + recent + "\n=== END LOG ===")
    except OSError:
        pass
    return "\n".join(messages)


def main():
    try:
        payload = json.load(sys.stdin)
    except (ValueError, OSError):
        return
    if not isinstance(payload, dict):
        return
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    if mode == "session-start":
        emit("SessionStart", session_start(payload))
        return
    tool_input = payload.get("tool_input")
    if not isinstance(tool_input, dict):
        return
    command = tool_input.get("command", "")
    if not isinstance(command, str):
        return
    if mode == "modern-tools":
        emit("PreToolUse", modern_tools(command))
    elif mode == "dependency-install":
        emit("PreToolUse", dependency_install(command))


if __name__ == "__main__":
    main()
