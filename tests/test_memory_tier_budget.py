"""Byte budget for the always-loaded context tier, plus the content it protects.

The always-on tier is what every session pays for before it does any work:
`claude/rules/*.md` + `claude/CLAUDE.md` + the active output style. This file is
the guard that stops it re-growing. Two kinds of assertion:

- **Budget** — one total for the global tier and one for this repo's own
  `CLAUDE.md`, because a session pays a sum, not a row. The set is globbed from
  disk rather than listed, and per-file ceilings are gone: they were eleven
  guesses to maintain, and a list is what let two rule files sit in every
  session's context while outside the number the gate enforced.
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

# For scale: the tier measured 76,512 bytes before the 2026-08-28 rules-to-skills
# restructure (at f605dcd, the parent of 5873a70), and 26,632 just after it. The
# ceiling below is what stops it walking back.

# The tier is DERIVED FROM DISK, never listed. A hand-maintained list is how this
# guard came to under-count by 3,674 bytes: vault-deliverables.md and
# sensitive-content.md sat in claude/rules/, loaded into every session, and
# outside the set the aggregate summed -- so the number enforced was not the
# number a session paid, and no assertion could notice. Globbing makes that
# failure mode unreachable: a new rule file is counted the moment it exists.
def always_on_files() -> list[Path]:
    files = sorted((REPO / "claude/rules").glob("*.md"))
    files.append(REPO / "claude/CLAUDE.md")
    files += sorted((REPO / "claude/output-styles").glob("*.md"))
    return files


def breakdown(files: list[Path]) -> str:
    """Biggest first -- a total that fails should say where the weight is."""
    rows = sorted(((f.stat().st_size, f) for f in files), reverse=True)
    return "\n".join(
        f"  {n:6d}  {f.relative_to(REPO)}" for n, f in rows
    )


# ONE number gates the global tier, because one number is what a session pays.
# Per-file ceilings were dropped on 2026-09-15: they were eleven separate
# guesses to maintain, being 200 bytes over one of them cost nothing real, and
# eight of them failing at once said nothing a reader could act on. Where the
# weight sits is a diagnostic, printed on failure, not an assertion.
#
# Set to the measured total rounded up, so the gate blocks growth rather than
# being red on arrival. It only ever goes DOWN: lower it whenever the tier
# shrinks -- 35,500 on 2026-09-15, 35,300 on 2026-09-20 after the rules were
# cut back to what the checklists do not already own. Rounded up rather than
# set to the measured total, because a gate with 20 bytes of headroom fires on
# the next clause anyone adds to any rule, which teaches people to raise it.
# The standing target is 29,900, which is where it was set when the tier
# measured 26,632; the gap between that and today is the backlog this gate
# stops from widening.
ALWAYS_ON_TARGET = 29900
ALWAYS_ON_CEILING = 35300

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


def test_always_on_tier_total() -> None:
    """What every session pays before it does any work, in one number."""
    files = always_on_files()
    total = sum(f.stat().st_size for f in files)
    assert total <= ALWAYS_ON_CEILING, (
        f"always-on tier is {total} bytes, over the {ALWAYS_ON_CEILING} ceiling "
        f"by {total - ALWAYS_ON_CEILING} (standing target {ALWAYS_ON_TARGET}). "
        f"These files load in EVERY repo, so a byte here costs more than a byte "
        f"in a project CLAUDE.md. Where the weight is:\n{breakdown(files)}"
    )


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


def test_rules_still_point_at_the_moved_sandbox_table() -> None:
    """Moving content out of the always-on tier is only safe if it stays findable."""
    safety = (REPO / "claude/rules/safety.md").read_text()
    assert "jobs" in safety and "sandbox" in safety.lower(), (
        "safety.md no longer points at the jobs skill for sandbox failure modes"
    )
