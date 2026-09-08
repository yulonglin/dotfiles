#!/usr/bin/env python3
"""Repair known Claude plugin hook imports in Codex; dry-run unless --apply.

Only four hook enablement settings and missing Codex manifests for core/workflow
are owned here. Plugin skills, native manifests, and trust hashes are preserved.
"""

import argparse
import json
import os
import re
import stat
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

DISABLED_KEYS = (
    "codex@codex-plugin-cc:hooks/hooks.json:session_start:0:0",
    "codex@codex-plugin-cc:hooks/hooks.json:session_start:1:0",
    "codex@codex-plugin-cc:hooks/hooks.json:session_end:0:0",
    "ralph-loop@claude-plugins-official:hooks/hooks.json:stop:0:0",
)
HEADER = re.compile(r"(?m)^[ \t]*\[([^\r\n]+)\][ \t]*(?:#[^\r\n]*)?(?=\r?$)")
ENABLED = re.compile(r"(?m)^([ \t]*enabled[ \t]*=[ \t]*)(true|false)([ \t]*(?:#[^\r\n]*)?)(\r?)$")
EVENTS = {"PreToolUse", "PostToolUse", "SessionStart"}


def repair_config(data):
    """Change exact enablement values without serializing unrelated TOML."""
    text = data.decode("utf-8")
    if chr(34) * 3 in text or chr(39) * 3 in text:
        raise ValueError("multiline TOML strings require parser-based adaptation")
    newline = "\r\n" if "\r\n" in text else "\n"
    for key in DISABLED_KEYS:
        headings = list(HEADER.finditer(text))
        candidates = []
        for index, heading in enumerate(headings):
            name = heading.group(1).strip()
            if name in ('hooks.state.' + json.dumps(key), "hooks.state.'" + key + "'"):
                end = headings[index + 1].start() if index + 1 < len(headings) else len(text)
                candidates.append((heading.end(), end))
        if len(candidates) > 1:
            raise ValueError("duplicate hook state table: " + key)
        if candidates:
            start, end = candidates[0]
            body = text[start:end]
            values = list(ENABLED.finditer(body))
            if len(values) > 1:
                raise ValueError("duplicate enabled setting: " + key)
            if values:
                value = values[0]
                body = body[:value.start(2)] + "false" + body[value.end(2):]
            else:
                if re.search(r"(?m)^\s*(?:enabled|[\"']enabled[\"'])\s*=", body):
                    raise ValueError("unsupported enabled setting: " + key)
                body = newline + "enabled = false" + body
            text = text[:start] + body + text[end:]
        else:
            # Inline state tables cannot be extended using ordinary TOML tables.
            if re.search(r"(?m)^\s*(?:hooks|state)\s*=\s*\{", text):
                raise ValueError("inline hooks/state table requires manual adaptation")
            if text and not text.endswith("\n"):
                text += newline
            text += newline + '[hooks.state.' + json.dumps(key) + ']' + newline
            text += "enabled = false" + newline
    return text.encode("utf-8")


def ensure_within_target(path, target):
    try:
        path.resolve().relative_to(target.resolve())
    except ValueError:
        raise ValueError("path escapes Codex target: " + str(path))


def plan_changes(target):
    config = target / "config.toml"
    before = config.read_bytes() if config.exists() else None
    after = repair_config(before or b"")
    changes = [(config, before, after)] if after != before else []
    cache = target / "plugins/cache/ai-safety-plugins"
    for name in ("core", "workflow"):
        for legacy in sorted((cache / name).glob("*/.claude-plugin/plugin.json")):
            native = legacy.parent.parent / ".codex-plugin/plugin.json"
            if native.exists() or native.is_symlink():
                continue
            manifest = json.loads(legacy.read_text())
            hooks = manifest.get("hooks")
            # Only the known malformed bare-event shape is ours to repair.
            if not isinstance(hooks, dict) or not hooks or not set(hooks) <= EVENTS:
                continue
            ensure_within_target(native, target)
            manifest["hooks"] = {}
            changes.append((native, None, (json.dumps(manifest, indent=2) + "\n").encode()))
    return changes


def atomic_write(path, expected, contents, target=None):
    """Back up existing bytes, refuse stale input, then atomically replace."""
    if target is not None:
        ensure_within_target(path, target)
    if path.is_symlink():
        raise ValueError("refusing to replace symlink: " + str(path))
    current = path.read_bytes() if path.exists() else None
    if current != expected:
        raise ValueError("file changed since planning: " + str(path))
    path.parent.mkdir(parents=True, exist_ok=True)
    mode = stat.S_IMODE(path.stat().st_mode) if expected is not None else 0o600
    backup = None
    if expected is not None:
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
        backup = path.with_name(path.name + ".bak.codex-hooks-" + stamp)
        with backup.open("xb") as handle:
            os.chmod(backup, mode)
            handle.write(expected)
            handle.flush()
            os.fsync(handle.fileno())
    fd, temporary = tempfile.mkstemp(prefix="." + path.name + ".", dir=str(path.parent))
    try:
        with os.fdopen(fd, "wb") as handle:
            os.fchmod(handle.fileno(), mode)
            handle.write(contents)
            handle.flush()
            os.fsync(handle.fileno())
        if target is not None:
            ensure_within_target(path, target)
        if path.is_symlink() or (path.read_bytes() if path.exists() else None) != expected:
            raise ValueError("file changed during write: " + str(path))
        if expected is None:
            # Atomic create without overwriting a concurrently created manifest.
            os.link(temporary, path)
        else:
            os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    if path.read_bytes() != contents:
        raise ValueError("verification failed: " + str(path))
    return backup


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", type=Path, default=Path(os.environ.get("CODEX_HOME") or str(Path.home() / ".codex")))
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args(argv)
    try:
        changes = plan_changes(args.target.expanduser())
        for path, before, after in changes:
            print(("Repair " if args.apply else "Would repair ") + str(path))
            if args.apply:
                backup = atomic_write(path, before, after, args.target.expanduser())
                if backup:
                    print("Backup: " + str(backup))
        print("{} file(s) {}".format(len(changes), "repaired" if args.apply else "planned; pass --apply to write"))
        return 0
    except (OSError, ValueError) as error:
        print("Error: " + str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
