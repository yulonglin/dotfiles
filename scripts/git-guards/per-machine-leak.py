#!/usr/bin/env -S uv run --quiet --script
# /// script
# requires-python = ">=3.11"
# ///
"""Decide whether a blob of a protected file carries a per-machine value.

Usage: per-machine-leak REPO_PATH < blob

Run through the per-machine-leak launcher next to this file, which picks
`uv run --script` (honouring requires-python above: tomllib is 3.11+) and
falls back to a python3 >= 3.11 on PATH.

REPO_PATH is the file's path in the repo; it picks the check. The blob is the
content git would store (for Zed, the post-clean-filter blob).

Exit 0: safe to publish, or REPO_PATH is not a protected file.
Exit 1: unsafe; one line on stdout says why, never quoting the value.
Any other exit (an exception, no Python 3.11 runtime) also means unsafe:
callers treat every non-zero exit as a rejection, so the check fails closed.

Shared by config/git-hooks/pre-commit (Codex trust-table guard) and
custom_bins/dotfiles-sync (hold-back screen and outgoing-commit screen), so
the two cannot drift.
"""

from __future__ import annotations

import json
import re
import sys

TOKENED_LOOPBACK = re.compile(
    r"https?://(?:127\.0\.0\.1|localhost|\[::1\])(?::[0-9]+)?/\S*[0-9a-fA-F]{16,}"
)


def claude_settings(text: str) -> str | None:
    """model-router's gateway endpoint: env.ANTHROPIC_BASE_URL, or any env
    value holding a tokened loopback URL."""
    try:
        env = json.loads(text).get("env") or {}
        found = sorted(
            k for k, v in env.items()
            if k == "ANTHROPIC_BASE_URL" or (isinstance(v, str) and TOKENED_LOOPBACK.search(v))
        )
    except (ValueError, AttributeError):
        # Not a JSON object: match the raw text rather than wave it through.
        found = ["ANTHROPIC_BASE_URL"] if "ANTHROPIC_BASE_URL" in text else []
        if not found and TOKENED_LOOPBACK.search(text):
            found = ["a tokened loopback URL"]
    return f"machine-local gateway endpoint in env ({', '.join(found)})" if found else None


def codex_config(text: str) -> str | None:
    """Codex trust tables: any top-level `projects` key, whatever the TOML
    syntax ([projects."p"], ['projects'], [[projects]], projects = {...},
    projects.p = ...). Parsed, not pattern-matched; unparseable fails closed."""
    try:
        import tomllib
    except ModuleNotFoundError:
        # Only reachable when run directly under an old python3, past the launcher.
        return f"no tomllib in Python {sys.version.split()[0]} (needs 3.11+; run via uv); failing closed"
    try:
        data = tomllib.loads(text)
    except tomllib.TOMLDecodeError as e:
        return f"not valid TOML ({e}); failing closed"
    if "projects" in data:
        return "top-level `projects` key (Codex trust tables)"
    return None


def zed_settings(text: str) -> str | None:
    """Zed's ssh_connections member. A plain key match: a mention inside a
    comment also counts, which errs towards holding the file back."""
    if re.search(r'"ssh_connections"\s*:', text):
        return "ssh_connections block (Zed remote hosts)"
    return None


CHECKS = {
    "claude/settings.json": claude_settings,
    "codex/config.toml": codex_config,
    "config/zed/settings.json": zed_settings,
}


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__.strip().splitlines()[2], file=sys.stderr)
        return 2
    text = sys.stdin.buffer.read().decode("utf-8", errors="replace")
    check = CHECKS.get(sys.argv[1])
    reason = check(text) if check else None
    if reason:
        print(reason)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
