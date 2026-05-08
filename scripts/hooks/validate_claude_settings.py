#!/usr/bin/env -S uv run --quiet --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["jsonschema>=4.0"]
# ///
"""
Sanity-check a Claude Code settings.json file.

Catches the failure modes we keep hitting after stash/pop, worktree merges,
and concurrent writes by Claude Code itself:

  1. Invalid JSON (broken syntax, truncation)
  2. Unresolved conflict markers (<<<<<<<, =======, >>>>>>>)
  3. Duplicate keys at the same level (botched merge)
  4. Missing required top-level keys (statusLine, hooks, permissions)
  5. Regression to a stub (key counts collapsed)

Exit code 0 = pass, 1 = fail. Prints concise findings only on failure.

Designed to run as a git pre-commit hook AND standalone for ad-hoc validation.

Usage:
  validate_claude_settings.py <file> [<file> ...]
  validate_claude_settings.py --staged   # check staged claude/settings.json files
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

# Strict mode: the dotfiles "source of truth" for ~/.claude/settings.json.
# Lenient mode: per-project .claude/settings.json (small, scoped overrides).
STRICT_REQUIRED_KEYS = ("statusLine", "hooks", "permissions")
STRICT_MIN_TOP_LEVEL_KEYS = 10
STRICT_MIN_PERMISSIONS_ALLOW = 20
STRICT_MIN_HOOK_EVENTS = 3

CONFLICT_RE = re.compile(r"^(<{7}|={7}|>{7})", re.MULTILINE)

SCHEMA_URL = "https://json.schemastore.org/claude-code-settings.json"
SCHEMA_CACHE = Path(__file__).parent / "cache" / "claude-code-settings.schema.json"
SCHEMA_CACHE_MAX_AGE_SECONDS = 7 * 24 * 3600  # refresh weekly
SCHEMA_FETCH_TIMEOUT = 5


def _load_schema() -> dict | None:
    """Return the cached schema, fetching if missing or stale.
    Falls back to (possibly stale) cache if fetch fails. Returns None on full miss."""
    fresh_cache = (
        SCHEMA_CACHE.is_file()
        and time.time() - SCHEMA_CACHE.stat().st_mtime < SCHEMA_CACHE_MAX_AGE_SECONDS
    )
    if fresh_cache:
        try:
            return json.loads(SCHEMA_CACHE.read_text())
        except json.JSONDecodeError:
            pass  # corrupted cache, refetch

    try:
        with urllib.request.urlopen(SCHEMA_URL, timeout=SCHEMA_FETCH_TIMEOUT) as resp:
            data = resp.read().decode()
        SCHEMA_CACHE.parent.mkdir(parents=True, exist_ok=True)
        SCHEMA_CACHE.write_text(data)
        return json.loads(data)
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, OSError):
        if SCHEMA_CACHE.is_file():
            try:
                return json.loads(SCHEMA_CACHE.read_text())
            except json.JSONDecodeError:
                return None
        return None


def _validate_against_schema(data: dict, schema: dict) -> list[str]:
    """Return schema validation errors, capped to avoid spam.
    Silently returns [] if jsonschema isn't installed — schema check is opt-in."""
    try:
        import jsonschema
    except ImportError:
        return []

    validator = jsonschema.Draft7Validator(schema)
    errors: list[str] = []
    for err in validator.iter_errors(data):
        path = ".".join(str(p) for p in err.absolute_path) or "(root)"
        errors.append(f"schema: {path}: {err.message}")
    return errors[:10]


def _is_strict_path(path: Path) -> bool:
    """`claude/settings.json` (global source) → strict.
    `.claude/settings.json` (per-project) → lenient."""
    parts = path.parts
    return len(parts) >= 2 and parts[-2] == "claude" and parts[-1] == "settings.json"


def _detect_duplicate_keys(pairs: list[tuple[str, object]]) -> dict:
    seen: dict[str, int] = {}
    dupes: list[str] = []
    for k, _ in pairs:
        if k in seen:
            dupes.append(k)
        seen[k] = seen.get(k, 0) + 1
    if dupes:
        raise ValueError(f"duplicate keys: {sorted(set(dupes))}")
    return dict(pairs)


def validate(path: Path) -> tuple[list[str], list[str]]:
    """Return (errors, warnings). Errors are blocking; warnings are advisory.

    Heuristic checks (parse, conflict markers, duplicate keys, stub regression)
    produce errors. Schema validation produces warnings — the upstream schema
    can lag Anthropic, so a schema mismatch may be legit drift, not a bug."""
    errors: list[str] = []
    warnings: list[str] = []

    if not path.is_file():
        return [f"{path}: file not found"], []

    text = path.read_text()

    if CONFLICT_RE.search(text):
        errors.append("contains unresolved conflict markers (<<<<<<< / ======= / >>>>>>>)")
        return errors, warnings

    try:
        data = json.loads(text, object_pairs_hook=_detect_duplicate_keys)
    except ValueError as e:
        errors.append(f"invalid JSON: {e}")
        return errors, warnings

    if not isinstance(data, dict):
        return [f"top-level value is {type(data).__name__}, expected object"], warnings

    schema = _load_schema()
    if schema is not None:
        warnings.extend(_validate_against_schema(data, schema))

    if not _is_strict_path(path):
        return errors, warnings

    missing = [k for k in STRICT_REQUIRED_KEYS if k not in data]
    if missing:
        errors.append(f"missing required top-level keys: {missing}")

    if len(data) < STRICT_MIN_TOP_LEVEL_KEYS:
        errors.append(
            f"only {len(data)} top-level keys (< {STRICT_MIN_TOP_LEVEL_KEYS}); "
            f"likely a stub regression"
        )

    perms = data.get("permissions")
    if isinstance(perms, dict):
        allow = perms.get("allow")
        if isinstance(allow, list) and len(allow) < STRICT_MIN_PERMISSIONS_ALLOW:
            errors.append(
                f"permissions.allow has {len(allow)} entries "
                f"(< {STRICT_MIN_PERMISSIONS_ALLOW}); likely truncated"
            )

    hooks = data.get("hooks")
    if isinstance(hooks, dict) and len(hooks) < STRICT_MIN_HOOK_EVENTS:
        errors.append(
            f"hooks has {len(hooks)} events (< {STRICT_MIN_HOOK_EVENTS}); likely truncated"
        )

    return errors, warnings


def staged_settings_files() -> list[Path]:
    proc = subprocess.run(
        ["git", "diff", "--cached", "--name-only", "--diff-filter=ACM"],
        capture_output=True,
        text=True,
        check=True,
    )
    candidates = ("claude/settings.json", ".claude/settings.json")
    return [Path(p) for p in proc.stdout.splitlines() if p in candidates and Path(p).is_file()]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("paths", nargs="*", type=Path)
    ap.add_argument("--staged", action="store_true", help="check staged settings files")
    ap.add_argument(
        "--strict-schema",
        action="store_true",
        help="treat schema warnings as errors (default: warnings advisory only)",
    )
    args = ap.parse_args()

    if args.staged:
        paths = staged_settings_files()
        if not paths:
            return 0
    elif args.paths:
        paths = args.paths
    else:
        ap.error("provide at least one path or --staged")

    failed = False
    for p in paths:
        errors, warnings = validate(p)
        if errors:
            failed = True
            print(f"❌ {p}", file=sys.stderr)
            for e in errors:
                print(f"   - {e}", file=sys.stderr)
        if warnings:
            label = "❌" if args.strict_schema else "⚠️"
            print(f"{label} {p} (schema warnings)", file=sys.stderr)
            for w in warnings:
                print(f"   - {w}", file=sys.stderr)
            if args.strict_schema:
                failed = True

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
