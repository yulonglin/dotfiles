#!/usr/bin/env python3
"""Pins scripts/build_artifacts_index.py — the builder that turned the ARTIFACTS.md
table from a hand-edited block into one file per row.

The point of the change is that two artifact publishes stop conflicting, so the
conflict case is tested directly: two rows added on two branches from two different
files must both survive, which is the property the old single-table layout lacked.

The rest pins what the builder must refuse. An invented status, a missing summary, a
duplicate URL and a raw pipe all produce a silently wrong index rather than an error
if nobody checks, and a silently wrong index is exactly what this file exists to stop.
"""

import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
BUILDER = REPO / "scripts" / "build_artifacts_index.py"

BEGIN = "[//]: # (BEGIN GENERATED ARTIFACTS TABLE)"
END = "[//]: # (END GENERATED ARTIFACTS TABLE)"

INDEX_SKELETON = f"""# Artifacts

Hand-written prose above the table.

{BEGIN}
{END}

Hand-written prose below the table.
"""

ROW_A = """\
title: Page A
url: https://claude.ai/code/artifact/11111111-1111-1111-1111-111111111111
org: Example Org
status: live
last_updated: 2026-09-01
public: no
summary: what page A established
"""

ROW_B = """\
title: Page B
url: https://claude.ai/code/artifact/22222222-2222-2222-2222-222222222222
org: Example Org
status: done
last_updated: 2026-09-02
public: no
summary: what page B established
"""


def run(root: Path, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(BUILDER), "--repo-root", str(root), *args],
        capture_output=True,
        text=True,
    )


class BuilderTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        (self.root / "artifacts" / "index-rows").mkdir(parents=True)
        (self.root / "ARTIFACTS.md").write_text(INDEX_SKELETON, encoding="utf-8")
        self.addCleanup(self.tmp.cleanup)

    def index_row(self, name: str, body: str) -> None:
        (self.root / "artifacts" / "index-rows" / f"{name}.yml").write_text(
            body, encoding="utf-8"
        )

    def artifact(self, slug: str, body: str) -> None:
        d = self.root / "artifacts" / slug
        d.mkdir(parents=True, exist_ok=True)
        (d / "meta.yml").write_text(body, encoding="utf-8")

    def table(self) -> str:
        text = (self.root / "ARTIFACTS.md").read_text(encoding="utf-8")
        return text.split(BEGIN, 1)[1].split(END, 1)[0]

    # --- what it builds ---------------------------------------------------

    def test_rows_come_from_both_locations_newest_first(self):
        self.index_row("a", ROW_A)
        self.artifact("page-b", ROW_B)
        self.assertEqual(run(self.root).returncode, 0)
        table = self.table()
        self.assertIn("[Page A](https://claude.ai/code/artifact/1111", table)
        self.assertIn("[Page B](https://claude.ai/code/artifact/2222", table)
        self.assertLess(table.index("Page B"), table.index("Page A"))

    def test_source_cell_defaults_per_location(self):
        self.index_row("a", ROW_A)
        self.artifact("page-b", ROW_B)
        run(self.root)
        rows = {
            line.split("](")[0].lstrip("| ["): line
            for line in self.table().splitlines()
            if line.startswith("| [")
        }
        self.assertIn("| — |", rows["Page A"])
        self.assertIn("| `artifacts/page-b/` |", rows["Page B"])

    def test_prose_outside_the_markers_survives(self):
        self.index_row("a", ROW_A)
        run(self.root)
        text = (self.root / "ARTIFACTS.md").read_text(encoding="utf-8")
        self.assertIn("Hand-written prose above the table.", text)
        self.assertIn("Hand-written prose below the table.", text)

    def test_tally_line_counts_each_status(self):
        self.index_row("a", ROW_A)
        self.artifact("page-b", ROW_B)
        run(self.root)
        self.assertIn("2 rows: 1 live, 1 done.", self.table())

    def test_unpublished_artifact_gets_no_row_and_is_reported(self):
        self.artifact("draft", "title: Draft\nurl: unpublished\nstatus: live\n")
        self.index_row("a", ROW_A)
        result = run(self.root)
        self.assertEqual(result.returncode, 0)
        self.assertNotIn("Draft", self.table())
        self.assertIn("not published yet", result.stdout)

    def test_every_supported_placeholder_round_trips(self):
        """The three forms the schema designates as "no URL yet" — the two
        sentinels documented in artifacts/index-rows/README.md, plus an
        absent/empty field — must still be skipped, not rejected."""
        self.artifact("draft-a", "title: Draft A\nurl: unpublished\nstatus: live\n")
        self.artifact(
            "draft-b", "title: Draft B\nurl: pending-first-publish\nstatus: live\n"
        )
        self.artifact("draft-c", "title: Draft C\nurl: ''\nstatus: live\n")
        self.artifact("draft-d", "title: Draft D\nstatus: live\n")
        self.index_row("a", ROW_A)
        result = run(self.root)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("1 rows: 1 live.", self.table())
        for name in ("Draft A", "Draft B", "Draft C", "Draft D"):
            self.assertNotIn(name, self.table())
        self.assertEqual(result.stdout.count("not published yet"), 4, result.stdout)

    # --- the conflict this change exists to remove ------------------------

    def test_two_rows_added_on_two_branches_both_survive_a_merge(self):
        """The old layout put both inserts on the same table line. Now each is its
        own file, so git merges them cleanly and a rebuild carries both."""
        # core.hooksPath=/dev/null keeps this machine's global pre-commit hooks
        # (gitleaks here) out of a test about merge behaviour.
        git = ["git", "-c", "user.email=t@t", "-c", "user.name=t",
               "-c", "core.hooksPath=/dev/null"]
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)
        self.index_row("base", ROW_A)
        run(self.root)
        subprocess.run([*git, "-C", str(self.root), "add", "-A"], check=True)
        subprocess.run([*git, "-C", str(self.root), "commit", "-qm", "base"], check=True)
        base = subprocess.run(
            ["git", "-C", str(self.root), "rev-parse", "HEAD"],
            capture_output=True, text=True, check=True,
        ).stdout.strip()

        # Branch one publishes Page B.
        subprocess.run([*git, "-C", str(self.root), "checkout", "-q", "-b", "one"], check=True)
        self.artifact("page-b", ROW_B)
        run(self.root)
        subprocess.run([*git, "-C", str(self.root), "add", "-A"], check=True)
        subprocess.run([*git, "-C", str(self.root), "commit", "-qm", "b"], check=True)

        # Branch two, from the same base, publishes Page C.
        subprocess.run([*git, "-C", str(self.root), "checkout", "-q", base], check=True)
        subprocess.run([*git, "-C", str(self.root), "checkout", "-q", "-b", "two"], check=True)
        self.artifact("page-c", ROW_B.replace("Page B", "Page C")
                      .replace("22222222-2222-2222-2222-222222222222",
                               "33333333-3333-3333-3333-333333333333")
                      .replace("2026-09-02", "2026-09-03"))
        run(self.root)
        subprocess.run([*git, "-C", str(self.root), "add", "-A"], check=True)
        subprocess.run([*git, "-C", str(self.root), "commit", "-qm", "c"], check=True)

        merge = subprocess.run(
            [*git, "-C", str(self.root), "merge", "--no-edit", "one"],
            capture_output=True, text=True,
        )
        # ARTIFACTS.md may conflict; the YAML files must not, and rebuilding
        # after taking either side must produce a table holding all three rows.
        conflicts = subprocess.run(
            ["git", "-C", str(self.root), "diff", "--name-only", "--diff-filter=U"],
            capture_output=True, text=True, check=True,
        ).stdout.split()
        self.assertNotIn("artifacts/page-b/meta.yml", conflicts, merge.stdout)
        self.assertNotIn("artifacts/page-c/meta.yml", conflicts, merge.stdout)
        if conflicts:
            subprocess.run(
                [*git, "-C", str(self.root), "checkout", "--ours", "ARTIFACTS.md"],
                check=True,
            )
        self.assertEqual(run(self.root).returncode, 0)
        table = self.table()
        for name in ("Page A", "Page B", "Page C"):
            self.assertIn(name, table)

    # --- what it refuses --------------------------------------------------

    def test_check_mode_fails_on_a_stale_table(self):
        self.index_row("a", ROW_A)
        self.assertEqual(run(self.root).returncode, 0)
        self.index_row("b", ROW_B)
        result = run(self.root, "--check")
        self.assertEqual(result.returncode, 1)
        self.assertIn("Page B", result.stdout)

    def test_check_mode_passes_on_a_current_table(self):
        self.index_row("a", ROW_A)
        run(self.root)
        self.assertEqual(run(self.root, "--check").returncode, 0)

    def test_malformed_url_on_a_published_record_is_rejected_not_dropped(self):
        """A typo in an already-published URL used to delete that row from the
        table with exit 0. ARTIFACTS.md is the only index of published pages, so
        an unparseable URL is invalid metadata and must fail the build."""
        self.index_row("a", ROW_A)
        self.index_row("b", ROW_B)
        self.assertEqual(run(self.root).returncode, 0)
        self.assertIn("2 rows", self.table())
        before = (self.root / "ARTIFACTS.md").read_text(encoding="utf-8")

        bad = ROW_B.replace(
            "222222222222\n", "222222222222/\n"
        )  # one trailing slash
        self.index_row("b", bad)
        result = run(self.root)

        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertIn("b.yml", result.stderr)
        self.assertIn(
            "https://claude.ai/code/artifact/22222222-2222-2222-2222-222222222222/",
            result.stderr,
        )
        self.assertNotIn("not published yet", result.stdout)
        self.assertEqual(
            (self.root / "ARTIFACTS.md").read_text(encoding="utf-8"),
            before,
            "a rejected build must not rewrite the index",
        )

    def test_check_mode_fails_on_a_malformed_url(self):
        """--check exiting 0 while a row is dropped is how CI approved an index
        that had quietly lost a publication."""
        self.index_row("a", ROW_A)
        self.index_row("b", ROW_B)
        self.assertEqual(run(self.root).returncode, 0)
        self.index_row("b", ROW_B.replace("222222222222\n", "222222222222/\n"))
        result = run(self.root, "--check")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("b.yml", result.stderr)

    def test_url_that_is_not_an_artifact_address_is_rejected(self):
        self.index_row("a", ROW_A.replace(
            "https://claude.ai/code/artifact/11111111-1111-1111-1111-111111111111",
            "https://example.com/some-page",
        ))
        result = run(self.root)
        self.assertEqual(result.returncode, 2)
        self.assertIn("https://example.com/some-page", result.stderr)

    def test_invented_status_is_rejected(self):
        self.index_row("a", ROW_A.replace("status: live", "status: shipped"))
        result = run(self.root)
        self.assertEqual(result.returncode, 2)
        self.assertIn("shipped", result.stderr)

    def test_superseded_without_a_link_is_rejected(self):
        self.index_row(
            "a",
            ROW_A.replace("status: live", "status: superseded\nstatus_note: gone"),
        )
        result = run(self.root)
        self.assertEqual(result.returncode, 2)
        self.assertIn("superseded", result.stderr)

    def test_missing_summary_is_rejected(self):
        self.index_row("a", ROW_A.replace("summary: what page A established\n", ""))
        result = run(self.root)
        self.assertEqual(result.returncode, 2)
        self.assertIn("summary", result.stderr)

    def test_duplicate_url_is_rejected(self):
        self.index_row("a", ROW_A)
        self.index_row("a-again", ROW_A.replace("Page A", "Page A copy"))
        result = run(self.root)
        self.assertEqual(result.returncode, 2)
        self.assertIn("duplicate url", result.stderr)

    def test_unescaped_pipe_is_rejected(self):
        self.index_row("a", ROW_A.replace("what page A established", "curl | sh"))
        result = run(self.root)
        self.assertEqual(result.returncode, 2)
        self.assertIn("'|'", result.stderr)

    def test_escaped_pipe_passes_through(self):
        self.index_row("a", ROW_A.replace("what page A established", r"curl \| sh"))
        self.assertEqual(run(self.root).returncode, 0)
        self.assertIn(r"curl \| sh", self.table())

    def test_missing_markers_are_rejected(self):
        (self.root / "ARTIFACTS.md").write_text("# Artifacts\n", encoding="utf-8")
        self.index_row("a", ROW_A)
        result = run(self.root)
        self.assertEqual(result.returncode, 2)
        self.assertIn("marker", result.stderr)


class RealRepoTest(unittest.TestCase):
    """The committed ARTIFACTS.md must match its own YAML files."""

    def test_committed_index_is_current(self):
        result = run(REPO, "--check")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_real_tree_row_count_is_unchanged(self):
        """Pins the count the fix must not move: every published meta.yml in the
        repo still produces exactly one row."""
        published = sum(
            1
            for p in [*REPO.glob("artifacts/*/meta.yml"),
                      *REPO.glob("artifacts/index-rows/*.yml")]
            if p.read_text(encoding="utf-8").count("url: https://claude.ai/code/artifact/")
        )
        result = run(REPO, "--check")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(f"({published} rows)", result.stdout)
        self.assertIn(f"{published} rows:",
                      (REPO / "ARTIFACTS.md").read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
