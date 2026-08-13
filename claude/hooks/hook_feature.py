#!/usr/bin/env python3
"""Gate Claude hook commands behind hierarchical feature flags."""

from __future__ import annotations

import os
import sys
from pathlib import Path

DEFAULT_CONFIG = Path(__file__).with_name("features.conf")
TRUE_VALUES = {"1", "on", "true", "yes"}
FALSE_VALUES = {"0", "off", "false", "no"}


def load_flags(path: Path) -> dict[str, bool]:
    try:
        lines = path.read_text().splitlines()
    except OSError:
        return {}

    flags: dict[str, bool] = {}
    for raw_line in lines:
        line = raw_line.split("#", 1)[0].strip()
        if "=" not in line:
            continue
        key, raw_value = (part.strip() for part in line.split("=", 1))
        value = raw_value.lower()
        if not key:
            continue
        if value in TRUE_VALUES:
            flags[key] = True
        elif value in FALSE_VALUES:
            flags[key] = False
    return flags


def feature_enabled(feature: str, flags: dict[str, bool]) -> bool:
    key = feature
    while key:
        if key in flags:
            return flags[key]
        key = key.rpartition(".")[0]
    return True


def usage() -> int:
    print(
        "usage: hook_feature.py enabled FEATURE | "
        "hook_feature.py run FEATURE -- COMMAND [ARG ...]",
        file=sys.stderr,
    )
    return 2


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        return usage()

    config = Path(os.environ.get("CLAUDE_HOOK_FEATURES_FILE", DEFAULT_CONFIG))
    action, feature = argv[0], argv[1]
    enabled = feature_enabled(feature, load_flags(config))

    if action == "enabled" and len(argv) == 2:
        return 0 if enabled else 1

    if action == "run" and len(argv) >= 4 and argv[2] == "--":
        if not enabled:
            sys.stdin.buffer.read()
            return 0
        os.execvp(argv[3], argv[3:])

    return usage()


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
