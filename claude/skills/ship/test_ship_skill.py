#!/usr/bin/env python3
"""Structural checks for the concise ship workflow skill."""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SKILL = ROOT / "claude" / "skills" / "ship" / "SKILL.md"
CATALOG = ROOT / "claude" / "skills" / "catalog" / "SKILL.md"

text = SKILL.read_text()
catalog = CATALOG.read_text()
required = {
    "natural trigger": "ship this",
    "scope boundary": "original task files",
    "review cap": "two review-fix rounds",
    "large merge PR": "large or structural",
    "parent checkout": "parent checkout",
    "parent branch": "named parent branch",
    "merged tests": "Run the relevant tests again in the merged parent checkout",
    "remote conflict policy": "remote-sync conflict",
    "worktree conflict policy": "worktree-merge conflict",
    "different model on rereview": "different model family",
    "shipped delta": "Report the final shipped file list",
    "explicit local path": "## Local-Merge Path",
    "explicit PR path": "## Pull-Request Path",
    "PR parent guard": "Do not merge or push the parent branch",
    "branch fallback": "merge the branch manually from the parent checkout",
}
missing = [label for label, phrase in required.items() if phrase not in text]
if "| `ship` |" not in catalog:
    missing.append("catalog registration")
if "finishing-a-development-branch" not in text:
    missing.append("branch-menu supersession cross-reference")
if missing:
    raise SystemExit("missing ship contracts: " + ", ".join(missing))
print("ship skill structural contract: PASS")
