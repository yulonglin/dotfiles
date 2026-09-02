#!/usr/bin/env python3
"""Repair Ralph Loop 1.0.0 Stop-hook success output to valid JSON.

Claude Code parses every nonempty, successful Stop-hook stdout as JSON. Ralph
Loop 1.0.0 emits plain text when it reaches its iteration cap or completion
promise, so those otherwise-successful stops surface as invalid-hook errors.
"""

from __future__ import annotations

import argparse
import json
import os
import stat
import subprocess
import sys
import tempfile
from pathlib import Path


PLUGIN_ID = "ralph-loop@claude-plugins-official"
ORIGINAL_MAX = 'echo "🛑 Ralph loop: Max iterations ($MAX_ITERATIONS) reached."'
PATCHED_MAX = (
    'jq -n --arg msg "🛑 Ralph loop: Max iterations '
    '($MAX_ITERATIONS) reached." \'{systemMessage: $msg}\''
)
ORIGINAL_PROMISE = (
    'echo "✅ Ralph loop: Detected <promise>$COMPLETION_PROMISE</promise>"'
)
PATCHED_PROMISE = (
    'jq -n --arg msg "✅ Ralph loop: Detected '
    '<promise>$COMPLETION_PROMISE</promise>" \'{systemMessage: $msg}\''
)
REPLACEMENTS = (
    (ORIGINAL_MAX, PATCHED_MAX),
    (ORIGINAL_PROMISE, PATCHED_PROMISE),
)


class RepairError(RuntimeError):
    """The installed hook cannot be repaired without guessing."""


def _under(path: Path, parent: Path) -> bool:
    try:
        path.relative_to(parent)
    except ValueError:
        return False
    return True


def _registry_targets(registry: Path) -> list[Path]:
    if not registry.exists():
        return []
    try:
        data = json.loads(registry.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise RepairError(f"cannot read plugin registry {registry}: {exc}") from exc

    entries = data.get("plugins", {}).get(PLUGIN_ID, [])
    if not isinstance(entries, list):
        raise RepairError(f"unsupported {PLUGIN_ID} registry entry")

    cache_root = (
        registry.parent / "cache" / "claude-plugins-official" / "ralph-loop"
    ).resolve()
    targets: list[Path] = []
    for entry in entries:
        install_path = entry.get("installPath") if isinstance(entry, dict) else None
        if not isinstance(install_path, str):
            raise RepairError(f"unsupported {PLUGIN_ID} install record")
        target = Path(install_path).expanduser() / "hooks" / "stop-hook.sh"
        if target.is_symlink():
            raise RepairError(f"refusing symlinked Ralph hook: {target}")
        try:
            resolved = target.resolve(strict=True)
        except OSError as exc:
            raise RepairError(f"cannot resolve Ralph hook {target}: {exc}") from exc
        if not _under(resolved, cache_root) or resolved.name != "stop-hook.sh":
            raise RepairError(f"Ralph hook escaped its cache root: {resolved}")
        if not stat.S_ISREG(resolved.stat().st_mode):
            raise RepairError(f"Ralph hook is not a regular file: {resolved}")
        targets.append(resolved)
    return targets


def _classify(source: str, path: Path) -> str:
    originals = [source.count(original) for original, _ in REPLACEMENTS]
    patched = [source.count(replacement) for _, replacement in REPLACEMENTS]
    if originals == [1, 1] and patched == [0, 0]:
        return "original"
    if originals == [0, 0] and patched == [1, 1]:
        return "patched"
    raise RepairError(
        f"unsupported Ralph Stop-hook drift in {path}; refusing a partial repair"
    )


def _render(source: str) -> str:
    for original, replacement in REPLACEMENTS:
        source = source.replace(original, replacement, 1)
    return source


def _atomic_write(path: Path, original: str, repaired: str) -> None:
    mode = stat.S_IMODE(path.stat().st_mode)
    fd, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temporary = Path(temporary_name)
    try:
        os.fchmod(fd, mode)
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as handle:
            handle.write(repaired)
            handle.flush()
            os.fsync(handle.fileno())
        syntax = subprocess.run(
            ["bash", "-n", str(temporary)],
            capture_output=True,
            text=True,
            check=False,
        )
        if syntax.returncode:
            raise RepairError(
                f"repaired Ralph hook failed bash -n: {syntax.stderr.strip()}"
            )
        if path.read_text(encoding="utf-8") != original:
            raise RepairError(f"Ralph hook changed while repairing it: {path}")
        os.replace(temporary, path)
    finally:
        try:
            temporary.unlink()
        except FileNotFoundError:
            pass


def repair(targets: list[Path]) -> None:
    pending: list[tuple[Path, str, str]] = []
    for path in targets:
        try:
            source = path.read_text(encoding="utf-8")
        except (OSError, UnicodeError) as exc:
            raise RepairError(f"cannot read Ralph hook {path}: {exc}") from exc
        if _classify(source, path) == "original":
            pending.append((path, source, _render(source)))

    # Preflight every installation before changing any of them.
    for path, original, repaired in pending:
        _atomic_write(path, original, repaired)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--path",
        action="append",
        type=Path,
        help="repair this explicit hook path (repeatable; intended for tests)",
    )
    args = parser.parse_args()

    try:
        targets = args.path or _registry_targets(
            Path.home() / ".claude" / "plugins" / "installed_plugins.json"
        )
        repair([path.resolve() for path in targets])
    except RepairError as exc:
        print(f"patch_ralph_loop_stop_hook: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
