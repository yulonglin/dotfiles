#!/usr/bin/env python3
"""Sync curated Antigravity settings and portable Claude Code permissions.

Merges dotfiles-managed defaults (e.g. agentMode="auto") and permissions from:
  1. antigravity/permissions.json (curated Antigravity MCP + CLI rules)
  2. claude/settings.json (portable Bash token-prefix rules)

into Antigravity CLI's settings.json (~/.gemini/antigravity-cli/settings.json)
without clobbering unrelated settings or user-authored rules added via
`/permissions`. Managed entries are tracked in a sibling state file rather than
comment sentinels inside permission arrays so every entry written to
settings.json is a valid `action(target)` rule.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import tempfile
from pathlib import Path
from typing import Any

BUCKETS = ("allow", "ask", "deny")
BASH_RE = re.compile(r"^Bash\((.*)\)$", re.DOTALL)
UNSAFE_INFIX_CHARS = ("*", "?", "|", ">", "<", ";", "&", "`", "$", "(", ")")


def load_json_object(path: Path) -> dict[str, Any]:
    raw = path.read_text(encoding="utf-8").strip()
    if not raw:
        return {}
    data = json.loads(raw)
    if not isinstance(data, dict):
        raise TypeError(f"{path} must contain a JSON object")
    return data


def atomic_write_json(path: Path, data: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    rendered = json.dumps(data, indent=2, ensure_ascii=False) + "\n"
    fd, tmp = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(rendered)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def translate_claude_bash_rule(pattern: str) -> tuple[str | None, str | None]:
    """Translate a Claude `Bash(...)` rule to Antigravity `command(...)`.

    Antigravity `command(prefix)` matches exact leading tokens. Only simple
    token-prefix patterns translate cleanly; infix globs, pipes, and redirects
    are skipped so we never emit misleading rules.
    """
    m = BASH_RE.match(pattern)
    if not m:
        return None, "not a Bash(...) rule"
    inner = m.group(1).strip()
    if not inner:
        return None, "empty Bash pattern"

    # Claude's prefix forms: `Bash(git *)` or `Bash(claude rm:*)`
    stem = inner[:-2].strip() if inner.endswith((" *", ":*")) else inner

    if not stem:
        return None, "empty command stem"
    if any(ch in stem for ch in UNSAFE_INFIX_CHARS):
        return None, "contains infix wildcard or shell metacharacter"

    # Collapse repeated whitespace for clean token prefix matching.
    normalized = " ".join(stem.split())
    return f"command({normalized})", None


def _extract_unmapped_guard_stems(claude_perms: dict[str, Any]) -> set[str]:
    """Find command stems that have unmappable ask/deny refinements in Claude.

    If Claude allows `Bash(claude rm:*)` but asks on
    `Bash(claude rm *--discard-unpushed*)`, we must not allow `command(claude rm)`
    in Antigravity without the matching ask guard.
    """
    guarded_stems: set[str] = set()
    for bucket in ("ask", "deny"):
        for item in claude_perms.get(bucket, []):
            if not isinstance(item, str) or not item.startswith("Bash("):
                continue
            rule, _ = translate_claude_bash_rule(item)
            if rule is not None:
                continue
            m = BASH_RE.match(item)
            if not m:
                continue
            inner = m.group(1).strip()
            # Take leading non-metacharacter tokens as the guarded prefix.
            lead_tokens: list[str] = []
            for tok in inner.split():
                if any(ch in tok for ch in UNSAFE_INFIX_CHARS):
                    break
                lead_tokens.append(tok)
            if lead_tokens:
                guarded_stems.add(" ".join(lead_tokens))
    return guarded_stems


def build_desired_config(
    claude_settings: dict[str, Any],
    antigravity_perms: dict[str, Any],
) -> tuple[dict[str, Any], dict[str, list[str]], list[str]]:
    """Return (defaults, permissions_by_bucket, skipped_descriptions)."""
    defaults: dict[str, Any] = {}
    raw_defaults = antigravity_perms.get("defaults", {})
    if isinstance(raw_defaults, dict):
        defaults.update(raw_defaults)

    desired: dict[str, list[str]] = {b: [] for b in BUCKETS}
    skipped: list[str] = []

    def add_rule(bucket: str, rule: str) -> None:
        if rule not in desired[bucket]:
            desired[bucket].append(rule)

    # 1. Curated Antigravity native permissions first.
    raw_ag_perms = antigravity_perms.get("permissions", {})
    if isinstance(raw_ag_perms, dict):
        for bucket in BUCKETS:
            for item in raw_ag_perms.get(bucket, []):
                if isinstance(item, str) and item.strip():
                    add_rule(bucket, item.strip())

    # 2. Portable Bash token-prefix rules from Claude settings.json.
    claude_perms = claude_settings.get("permissions", {})
    if isinstance(claude_perms, dict):
        guarded_stems = _extract_unmapped_guard_stems(claude_perms)
        for bucket in BUCKETS:
            for item in claude_perms.get(bucket, []):
                if not isinstance(item, str) or not item.startswith("Bash("):
                    continue
                rule, reason = translate_claude_bash_rule(item)
                if rule is None:
                    skipped.append(f"[{bucket}] {item} ({reason})")
                    continue
                if bucket == "allow":
                    stem = rule[len("command(") : -1]
                    if any(
                        stem == g or stem.startswith(g + " ") or g.startswith(stem + " ")
                        for g in guarded_stems
                    ):
                        skipped.append(
                            f"[{bucket}] {item} (skipped: guarded by unmappable ask/deny refinement)"
                        )
                        continue
                add_rule(bucket, rule)

    return defaults, desired, skipped


def merge_settings(
    current_settings: dict[str, Any],
    prev_managed: dict[str, list[str]],
    defaults: dict[str, Any],
    desired_perms: dict[str, list[str]],
) -> dict[str, Any]:
    merged = json.loads(json.dumps(current_settings))

    for key, value in defaults.items():
        merged[key] = value

    perm_obj = merged.get("permissions")
    if not isinstance(perm_obj, dict):
        perm_obj = {}

    for bucket in BUCKETS:
        existing = perm_obj.get(bucket)
        if not isinstance(existing, list):
            existing = []
        prev_set = set(prev_managed.get(bucket, []))
        desired_list = desired_perms.get(bucket, [])
        desired_set = set(desired_list)

        # Keep user-authored rules and managed rules that are still desired;
        # prune stale rules previously added by dotfiles sync.
        kept: list[str] = []
        for entry in existing:
            if not isinstance(entry, str):
                continue
            if entry in prev_set and entry not in desired_set:
                continue
            if entry not in kept:
                kept.append(entry)

        for entry in desired_list:
            if entry not in kept:
                kept.append(entry)

        perm_obj[bucket] = kept

    merged["permissions"] = perm_obj
    return merged


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--claude-settings",
        type=Path,
        required=True,
        help="Path to dotfiles claude/settings.json",
    )
    parser.add_argument(
        "--antigravity-perms",
        type=Path,
        required=True,
        help="Path to dotfiles antigravity/permissions.json",
    )
    parser.add_argument(
        "--target-settings",
        type=Path,
        default=Path.home() / ".gemini" / "antigravity-cli" / "settings.json",
        help="Target Antigravity CLI settings.json path",
    )
    parser.add_argument(
        "--state-file",
        type=Path,
        default=None,
        help="Path to managed-rules state file (default: sibling .dotfiles-synced-perms.json)",
    )
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true", help="Report drift without writing")
    mode.add_argument("--apply", action="store_true", help="Apply updates to target settings.json")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    state_path = (
        args.state_file
        if args.state_file is not None
        else args.target_settings.parent / ".dotfiles-synced-perms.json"
    )

    claude_data = load_json_object(args.claude_settings) if args.claude_settings.exists() else {}
    ag_perms_data = (
        load_json_object(args.antigravity_perms) if args.antigravity_perms.exists() else {}
    )

    try:
        current_settings = (
            load_json_object(args.target_settings) if args.target_settings.exists() else {}
        )
    except (OSError, TypeError, json.JSONDecodeError) as exc:
        print(
            f"  Warning: {args.target_settings} is not valid JSON ({exc}); leaving untouched",
            file=sys.stderr,
        )
        return 1

    prev_managed: dict[str, list[str]] = {b: [] for b in BUCKETS}
    if state_path.exists():
        try:
            loaded_state = load_json_object(state_path)
            raw_prev = loaded_state.get("permissions", {})
            if isinstance(raw_prev, dict):
                for b in BUCKETS:
                    vals = raw_prev.get(b, [])
                    if isinstance(vals, list):
                        prev_managed[b] = [v for v in vals if isinstance(v, str)]
        except (OSError, TypeError, json.JSONDecodeError):
            pass

    defaults, desired_perms, skipped = build_desired_config(claude_data, ag_perms_data)
    updated_settings = merge_settings(current_settings, prev_managed, defaults, desired_perms)

    settings_changed = updated_settings != current_settings or not args.target_settings.exists()
    state_payload = {"permissions": desired_perms}

    counts = ", ".join(f"{b}:{len(desired_perms[b])}" for b in BUCKETS)
    if args.check:
        if settings_changed:
            print(f"Antigravity settings drift: update needed ({counts}, skipped:{len(skipped)})")
            return 1
        print(f"Antigravity settings: up to date ({counts}, skipped:{len(skipped)})")
        return 0

    if settings_changed:
        atomic_write_json(args.target_settings, updated_settings)
        print(
            f"  Settings: updated {args.target_settings} "
            f"(agentMode={updated_settings.get('agentMode')}, {counts}, skipped:{len(skipped)})"
        )
    else:
        print(
            f"  Settings: {args.target_settings} already up to date "
            f"({counts}, skipped:{len(skipped)})"
        )

    atomic_write_json(state_path, state_payload)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
