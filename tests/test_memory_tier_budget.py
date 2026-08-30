"""Byte budget for the always-loaded context tier, plus the content it protects.

The always-on tier is what every session pays for before it does any work:
`claude/rules/*.md` + `claude/CLAUDE.md` + the active output style. This file is
the guard that stops it re-growing. Two kinds of assertion:

- **Budget** — a per-file ceiling and an aggregate ceiling, plus a floor on how
  much the 2026-08-28 rules-to-skills restructure actually removed.
- **Protected content** — passages that must survive a trim byte-for-byte, so
  that "we moved it into a skill" cannot quietly mean "we deleted it".

Repointed 2026-08-28 for the restructure in 5873a70, which cut 24 rule files to
9 and moved activity-scoped procedure into skills.

Run: pytest tests/test_memory_tier_budget.py
"""

import subprocess
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[1]
TAG = "pretrim-memory-2026-07-29"

# The always-loaded tier: every session pays these bytes. Measured at f605dcd
# (parent of 5873a70, the restructure commit) with
#   git ls-tree -r -l f605dcd -- claude/rules claude/CLAUDE.md claude/output-styles
# The repo's own CLAUDE.md is deliberately NOT in this set: it loads only in
# this repo, and it is not in the git baseline above.
PRE_RESTRUCTURE_BYTES = 76512

# Ceilings are current size x ~1.12, with a 150-byte floor so that small files
# get room for a real sentence rather than a fragment (12% of background-jobs.md
# is only 93 bytes), rounded up to the next 50. Tight enough that regrowth trips
# the guard, loose enough that an ordinary edit does not.
ALWAYS_ON = [
    ("claude/rules/background-jobs.md", 950),
    # Raised from the old 1300: this file legitimately grew when it absorbed the
    # scratch-script promotion rules from the deleted
    # reusable-component-promotion.md. The content moved here, it was not added.
    ("claude/rules/coding-conventions.md", 2200),
    ("claude/rules/communication.md", 3100),
    ("claude/rules/delegation.md", 2600),
    ("claude/rules/experiments.md", 3050),
    # pointers.md was deleted on 2026-08-30. Its whole job was indexing skills,
    # and four of the skills it indexed had never been invoked in 4,100 sessions
    # -- the index cost more every session than the things it indexed returned.
    # Its one unique rule ("one topic keeps one link") moved into artifacts-sync.
    # Raised from 2600: research-core absorbed the rule that terminology must
    # match the AI safety and LLM literature, with the reference venues named so
    # "common in the literature" is checkable rather than a matter of taste.
    ("claude/rules/research-core.md", 3000),
    ("claude/rules/safety.md", 2550),
    ("claude/rules/verify-before-instructing.md", 1050),
    ("claude/CLAUDE.md", 4250),
    ("claude/output-styles/effortful-learning.md", 5950),
]

# Loaded on top of the always-on tier for sessions in this repo. Its ceiling
# assumes the Learnings block stays inside its two-week window, with older
# entries moved to docs/tooling-and-packages.md § Past Learnings rather than
# deleted.
REPO_CLAUDE_MD = ("CLAUDE.md", 11100)

FILES = ALWAYS_ON + [REPO_CLAUDE_MD]

AGGREGATE_CEILING = 29900  # always-on tier only, ~12% over its current 26,632

# The sandbox failure-mode table moved out of the rules and into the jobs skill
# during the restructure. It is protected content: costly to re-derive, and the
# kind of thing a trim silently drops.
SANDBOX_MARKER = "## Sandbox failure modes"
SANDBOX_TABLE_HOME = "claude/skills/jobs/SKILL.md"
SANDBOX_TABLE_WAS = "claude/rules/safety-and-git.md"  # at TAG


def tagged(path: str) -> str:
    out = subprocess.run(
        ["git", "-C", str(REPO), "show", f"{TAG}:{path}"],
        capture_output=True,
        check=True,
    )
    return out.stdout.decode()


def size(path: str) -> int:
    return len((REPO / path).read_bytes())


def sandbox_table(text: str, where: str) -> str:
    """The marker heading plus its contiguous table rows, and nothing after it.

    Both homes continue into unrelated prose past the table -- the old one into
    a "More patterns" pointer, the new one into further skill sections -- so
    slicing to end-of-file would compare the surrounding document instead of the
    table. Fails loudly rather than returning an empty block, so that deleting
    the table shows up as a clear failure instead of empty == empty.
    """
    assert SANDBOX_MARKER in text, f"{SANDBOX_MARKER!r} missing from {where}"
    lines = text[text.index(SANDBOX_MARKER) :].splitlines()
    block = [lines[0]]
    for line in lines[1:]:
        if line.startswith("|") or not line.strip():
            block.append(line)
        else:
            break
    while block and not block[-1].strip():
        block.pop()
    rows = [ln for ln in block if ln.startswith("|")]
    # header + separator + 5 documented failure modes
    assert len(rows) >= 7, f"only {len(rows)} table rows in {where}; table gutted?"
    return "\n".join(block)


@pytest.mark.parametrize("path,ceiling", FILES)
def test_per_file_ceiling(path: str, ceiling: int) -> None:
    assert size(path) <= ceiling, f"{path}: {size(path)} > {ceiling}"


def test_aggregate_ceiling() -> None:
    total = sum(size(p) for p, _ in ALWAYS_ON)
    assert total <= AGGREGATE_CEILING, f"{total} > {AGGREGATE_CEILING}"


def test_no_unguarded_rule_files() -> None:
    """Every rule file carries a ceiling.

    Without this, adding claude/rules/foo.md would sail past both the per-file
    and the aggregate ceiling, because both only look at the listed paths.
    """
    on_disk = {f"claude/rules/{p.name}" for p in (REPO / "claude/rules").glob("*.md")}
    guarded = {p for p, _ in ALWAYS_ON if p.startswith("claude/rules/")}
    assert on_disk == guarded, f"unguarded: {on_disk - guarded}, stale: {guarded - on_disk}"


def test_restructure_removed_most_of_the_tier() -> None:
    after = sum(size(p) for p, _ in ALWAYS_ON)
    reduction = (PRE_RESTRUCTURE_BYTES - after) / PRE_RESTRUCTURE_BYTES
    assert reduction >= 0.60, f"only {reduction:.1%} smaller than pre-restructure"


@pytest.mark.parametrize("key", ["IMPORTANT NOTE", "Use existing code"])
def test_protected_line_byte_identical(key: str) -> None:
    """These lines must survive every trim unchanged."""
    old = [ln for ln in tagged("claude/CLAUDE.md").splitlines() if key in ln]
    new = [
        ln for ln in (REPO / "claude/CLAUDE.md").read_text().splitlines() if key in ln
    ]
    assert old, f"{key!r} not found at tag {TAG}"
    assert new, f"{key!r} missing from trimmed file"
    assert old[0] == new[0]


def test_protected_sandbox_table_survived_move_byte_identical() -> None:
    """The table moved rules -> skill; every byte of it came along."""
    old = sandbox_table(tagged(SANDBOX_TABLE_WAS), f"{TAG}:{SANDBOX_TABLE_WAS}")
    new = sandbox_table((REPO / SANDBOX_TABLE_HOME).read_text(), SANDBOX_TABLE_HOME)
    assert old == new


def test_rules_still_point_at_the_moved_sandbox_table() -> None:
    """Moving content out of the always-on tier is only safe if it stays findable."""
    safety = (REPO / "claude/rules/safety.md").read_text()
    assert "jobs" in safety and "sandbox" in safety.lower(), (
        "safety.md no longer points at the jobs skill for sandbox failure modes"
    )
