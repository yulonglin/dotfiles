"""Protected content for the always-loaded context tier, plus this repo's CLAUDE.md budget.

The always-on tier is what every session pays for before it does any work:
`claude/rules/*.md` + `claude/CLAUDE.md` + the active output style. Two kinds of
assertion:

- **Protected content** — passages that must survive a trim byte-for-byte, so
  that "we moved it into a skill" cannot quietly mean "we deleted it".
- **Repo CLAUDE.md budget** — one ceiling for this repo's own `CLAUDE.md`.

The total-bytes ceiling on the global tier was removed on 2026-11-03. It sat red
in CI for 19 days at 36,080 bytes against 35,300, and the published guidance
(code.claude.com/docs/en/memory) sets a soft 200-line target per file and has
Claude Code itself warn at startup when one file or the combined set grows past
its limit. Size is left to that warning; what this file keeps is the content no
trim may lose. Prune the tier by content: what a newer model no longer needs,
and procedure that belongs in a skill or checklist.

Repointed 2026-08-28 for the restructure in 5873a70, which cut 24 rule files to
9 and moved activity-scoped procedure into skills.

Run: pytest tests/test_memory_tier_budget.py
"""

import subprocess
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[1]
TAG = "pretrim-memory-2026-07-29"

# Loaded on top of the always-on tier, for sessions in this repo only, so it gets
# its own budget rather than sharing the global one -- a different blast radius
# deserves a different number. Emptied on 2026-09-15 (45,981 -> 9,728) when the
# Learnings section became transient machine state only.
REPO_CLAUDE_MD = "CLAUDE.md"
REPO_CLAUDE_MD_CEILING = 11100

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


def test_repo_claude_md_total() -> None:
    """This repo's own file, budgeted separately: it loads only here."""
    total = size(REPO_CLAUDE_MD)
    assert total <= REPO_CLAUDE_MD_CEILING, (
        f"{REPO_CLAUDE_MD} is {total} bytes, over the {REPO_CLAUDE_MD_CEILING} "
        f"ceiling by {total - REPO_CLAUDE_MD_CEILING}. The `## Learnings` section "
        f"takes transient machine state only; anything durable moves to the file "
        f"that owns the topic, and anything a test or the code records is dropped."
    )


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


EVIDENCE_WAS = "claude/rules/evidence.md"
EVIDENCE_WAS_AT = "031db2c3"  # last commit with the rule always-on
EVIDENCE_HOME = "claude/skills/evidence-packs/SKILL.md"


def test_evidence_rule_survived_move_byte_identical() -> None:
    """evidence.md left the always-on tier on 2026-10-03; every byte came along."""
    old = subprocess.run(
        ["git", "-C", str(REPO), "show", f"{EVIDENCE_WAS_AT}:{EVIDENCE_WAS}"],
        capture_output=True,
        check=True,
    ).stdout.decode()
    assert old.strip() in (REPO / EVIDENCE_HOME).read_text()


def test_rules_still_point_at_evidence_packs() -> None:
    """Moving content out of the always-on tier is only safe if it stays findable."""
    assert "`evidence-packs`" in (REPO / "claude/rules/communication.md").read_text()


def test_rules_still_point_at_the_moved_sandbox_table() -> None:
    """Moving content out of the always-on tier is only safe if it stays findable."""
    safety = (REPO / "claude/rules/safety.md").read_text()
    assert "jobs" in safety and "sandbox" in safety.lower(), (
        "safety.md no longer points at the jobs skill for sandbox failure modes"
    )
