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

import shutil
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


def replace_key(body: str, key: str, literal: str) -> str:
    """Swap one `key: value` line for `literal`, appending it if the key is absent."""
    lines = [line for line in body.splitlines() if not line.startswith(f"{key}:")]
    return "\n".join([*lines, literal]) + "\n"


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

    def test_non_string_url_on_a_published_record_is_rejected_not_dropped(self):
        """A url of `false`, `0`, an empty list or a mapping used to normalise to
        the empty string BEFORE validation, so it was read as the "not published
        yet" placeholder and the published page's row vanished with exit 0. The
        reviewer reproduced it on the real tree: 18 rows became 17, successfully."""
        for label, literal in (
            ("false", "url: false"),
            ("zero", "url: 0"),
            ("empty list", "url: []"),
            ("mapping", "url: {href: https://claude.ai/code/artifact/x}"),
        ):
            with self.subTest(label):
                self.index_row("a", ROW_A)
                self.index_row("b", ROW_B)
                self.assertEqual(run(self.root).returncode, 0)
                self.assertIn("2 rows", self.table())
                before = (self.root / "ARTIFACTS.md").read_text(encoding="utf-8")

                self.index_row(
                    "b",
                    "\n".join(
                        literal if line.startswith("url:") else line
                        for line in ROW_B.splitlines()
                    )
                    + "\n",
                )
                result = run(self.root)

                self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
                self.assertIn("b.yml", result.stderr)
                self.assertNotIn("not published yet", result.stdout)
                self.assertEqual(
                    (self.root / "ARTIFACTS.md").read_text(encoding="utf-8"),
                    before,
                    "a rejected build must not rewrite the index",
                )

    def test_check_mode_fails_on_a_non_string_url(self):
        """--check exiting 0 on a shortened index is how the drop reached CI."""
        for literal in ("url: false", "url: 0", "url: []", "url: {a: b}"):
            with self.subTest(literal):
                self.index_row("a", ROW_A)
                self.index_row("b", ROW_B)
                self.assertEqual(run(self.root).returncode, 0)
                self.index_row(
                    "b",
                    "\n".join(
                        literal if line.startswith("url:") else line
                        for line in ROW_B.splitlines()
                    )
                    + "\n",
                )
                result = run(self.root, "--check")
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertIn("b.yml", result.stderr)

    def test_the_rejection_names_the_original_value(self):
        """The message has to show what is in the file, not the empty string the
        old normalisation turned it into, or nobody can find the typo."""
        self.index_row("a", ROW_A.replace(
            "url: https://claude.ai/code/artifact/11111111-1111-1111-1111-111111111111",
            "url: false",
        ))
        result = run(self.root)
        self.assertEqual(result.returncode, 2)
        self.assertIn("a.yml", result.stderr)
        self.assertIn("False", result.stderr)

    def test_null_and_absent_url_follow_the_documented_empty_field_policy(self):
        """artifacts/README.md: a url that is one of the two placeholders "or
        empty" gets no row and is listed as a reminder. An explicit YAML null and
        an absent key are both that empty field, so they are skipped and reported
        — this is the one skip the schema designates, and it stays."""
        self.artifact("draft-null", "title: Draft Null\nurl: null\nstatus: live\n")
        self.artifact("draft-tilde", "title: Draft Tilde\nurl: ~\nstatus: live\n")
        self.artifact("draft-absent", "title: Draft Absent\nstatus: live\n")
        self.index_row("a", ROW_A)
        result = run(self.root)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("1 rows: 1 live.", self.table())
        for name in ("Draft Null", "Draft Tilde", "Draft Absent"):
            self.assertNotIn(name, self.table())
        self.assertEqual(result.stdout.count("not published yet"), 3, result.stdout)
        self.assertEqual(run(self.root, "--check").returncode, 0)

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


    # --- helpers for the fail-open class ----------------------------------

    def write(self, relpath: str, body: str) -> None:
        p = self.root / relpath
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(body, encoding="utf-8")

    def two_good_rows(self) -> str:
        """Build a healthy two-row index and return it, so a later assertion can
        prove a rejected build left it exactly as it was."""
        self.index_row("a", ROW_A)
        self.index_row("b", ROW_B)
        self.assertEqual(run(self.root).returncode, 0)
        self.assertIn("2 rows", self.table())
        return (self.root / "ARTIFACTS.md").read_text(encoding="utf-8")

    def assert_rejected(self, before: str, *needles: str) -> str:
        """Both entry points must fail: a rewrite that drops a row and a --check
        that blesses the shortened index are the same harm."""
        result = run(self.root)
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        for needle in needles:
            self.assertIn(needle, result.stderr)
        self.assertNotIn("not published yet", result.stdout)
        self.assertEqual(
            (self.root / "ARTIFACTS.md").read_text(encoding="utf-8"),
            before,
            "a rejected build must not rewrite the index",
        )
        check = run(self.root, "--check")
        self.assertNotEqual(check.returncode, 0, check.stdout)
        return result.stderr

    # --- the class: a falsey value normalised before its type is checked ---

    WHOLE_DOCUMENTS = (
        ("false", "false\n"),
        ("zero", "0\n"),
        ("empty string", "''\n"),
        ("empty list", "[]\n"),
        ("empty mapping", "{}\n"),
        ("a bare string", "a sentence someone left here\n"),
        ("an empty file", ""),
        ("a list of rows", "- title: Page B\n  url: x\n"),
        ("a bare null", "~\n"),
    )

    def test_whole_document_of_the_wrong_type_is_rejected_not_emptied(self):
        """`yaml.safe_load(...) or {}` normalised the whole document one line
        above the isinstance check that was supposed to catch it, so a file whose
        entire content was `false`, `0`, `''` or `[]` became an empty mapping,
        read as an absent url, and dropped a published page's row with exit 0.
        Whole-document `true` and a non-empty list were rejected, which is how we
        know the check existed and merely ran in the wrong order."""
        for label, body in self.WHOLE_DOCUMENTS:
            with self.subTest(label):
                before = self.two_good_rows()
                self.index_row("b", body)
                self.assert_rejected(before, "b.yml")

    # Every value the builder reads out of a row file, given a type it must not
    # have. Each was reached through a truthiness fallback or a bare `str()`, so
    # each silently became a default, a blank cell or a stringified Python repr.
    WRONG_TYPED_FIELDS = (
        ("title: false", ("title", "bool", "False")),
        ("title: [Page B]", ("title", "list", "['Page B']")),
        ("org: 0", ("org", "int", "0")),
        ("org: {name: Example}", ("org", "dict", "{'name': 'Example'}")),
        ("status: false", ("status", "bool", "False")),
        ("status: [live]", ("status", "list", "['live']")),
        ("summary: 0", ("summary", "int", "0")),
        ("summary: []", ("summary", "list", "[]")),
        ("last_updated: false", ("last_updated", "bool", "False")),
        ("last_updated: []", ("last_updated", "list", "[]")),
        ("status_note: false", ("status_note", "bool", "False")),
        ("status_note: {}", ("status_note", "dict", "{}")),
        ("index_source: false", ("index_source", "bool", "False")),
        ("index_source: []", ("index_source", "list", "[]")),
        ("public: []", ("public", "list", "[]")),
        ("public: 0", ("public", "int", "0")),
    )

    def test_a_field_of_the_wrong_type_is_rejected_not_defaulted(self):
        """The error has to name the file, the key, the type and the value as
        written — the old messages named the empty string the normalisation had
        already turned it into, or said nothing at all."""
        for literal, needles in self.WRONG_TYPED_FIELDS:
            key = literal.split(":", 1)[0]
            with self.subTest(literal):
                before = self.two_good_rows()
                self.index_row("b", replace_key(ROW_B, key, literal))
                self.assert_rejected(before, "b.yml", *needles)

    def test_a_blank_date_or_status_is_still_reported_as_missing(self):
        """Type-checking first must not lose the plain missing-key message."""
        for literal in ("last_updated: ''", "status: ''", "title: ''"):
            key = literal.split(":", 1)[0]
            with self.subTest(literal):
                before = self.two_good_rows()
                self.index_row("b", replace_key(ROW_B, key, literal))
                self.assert_rejected(before, "b.yml", "missing", key)

    def test_a_date_that_is_not_a_date_is_rejected(self):
        """The table sorts on this value, so a string that is not an ISO date
        silently reorders the log rather than failing."""
        before = self.two_good_rows()
        self.index_row("b", replace_key(ROW_B, "last_updated", "last_updated: last tuesday"))
        self.assert_rejected(before, "b.yml", "last_updated", "last tuesday")

    def test_supported_values_still_round_trip_after_the_type_checks(self):
        """The documented defaults survive: an absent public is `no`, a bool
        public prints yes/no, a public URL prints as written, an absent
        index_source falls back per location, and a date is formatted ISO."""
        self.index_row("a", ROW_A)
        self.artifact("page-b", ROW_B.replace("public: no", "public: yes"))
        self.index_row(
            "c",
            ROW_B.replace("Page B", "Page C")
            .replace("22222222-2222-2222-2222-222222222222",
                     "33333333-3333-3333-3333-333333333333")
            .replace("public: no", "public: https://example.com/mirror")
            + "index_source: '`somewhere/else/`'\nstatus_note: still up\n",
        )
        result = run(self.root)
        self.assertEqual(result.returncode, 0, result.stderr)
        table = self.table()
        self.assertIn("3 rows:", table)
        rows = {
            line.split("](")[0].lstrip("| ["): line
            for line in table.splitlines()
            if line.startswith("| [")
        }
        self.assertIn("| no |", rows["Page A"])
        self.assertIn("| yes |", rows["Page B"])
        self.assertIn("| https://example.com/mirror |", rows["Page C"])
        self.assertIn("| `somewhere/else/` |", rows["Page C"])
        self.assertIn("done — still up", rows["Page C"])
        self.assertIn("| `artifacts/page-b/` |", rows["Page B"])
        self.assertIn("| 2026-09-02 |", rows["Page B"])
        self.assertEqual(run(self.root, "--check").returncode, 0)

    # --- the same fail-open harm, wearing a filename ----------------------
    #
    # "Is this stray file meant to be a row?" cannot be answered from a
    # filename: two detectors that tried were defeated, most recently by a row
    # renamed metadata.txt, which took the real index from 18 rows to 17 with
    # exit 0. "Does this artifact have a row?" is decidable, so that is the
    # question now, and its answer does not depend on the stray file's name.

    RENAMED_ROWS = ("meta.yaml", "META.YML", "metadata.txt", "metadata.json",
                    "metadata", "meta.yml.bak", "row.yml", "sub/meta.yml")

    def test_an_artifact_whose_row_was_renamed_fails_naming_the_directory(self):
        """Whatever the row was renamed to, its artifact has no row file in
        either designated location, so the build stops and names the directory
        instead of printing a table quietly one page short."""
        row = ROW_B.replace("Page B", "Renamed").replace("22222222", "44444444")
        for name in self.RENAMED_ROWS:
            with self.subTest(name):
                before = self.two_good_rows()
                self.write(f"artifacts/page-c/{name}", row)
                try:
                    self.assert_rejected(before, "artifacts/page-c/")
                finally:
                    shutil.rmtree(self.root / "artifacts" / "page-c")

    def test_a_directory_covered_by_an_index_row_passes(self):
        """The second designated location counts as coverage."""
        self.index_row("a", ROW_A)
        self.index_row("page-b", ROW_B)
        self.write("artifacts/page-b/report.html", "<p>published</p>")
        self.assertEqual(run(self.root).returncode, 0)
        self.assertIn("2 rows", self.table())

    def test_the_report_names_every_uncovered_directory_at_once(self):
        before = self.two_good_rows()
        self.write("artifacts/page-c/meta.yaml", ROW_B.replace("22222222", "44444444"))
        self.write("artifacts/page-d/report.html", "<p>published</p>")
        stderr = self.assert_rejected(before, "artifacts/page-c/")
        self.assertIn("artifacts/page-d/", stderr)

    def test_an_empty_leftover_directory_is_not_an_artifact(self):
        """git cannot record one, so failing the build on it would be noise."""
        self.index_row("a", ROW_A)
        (self.root / "artifacts" / "leftover").mkdir()
        self.assertEqual(run(self.root).returncode, 0)
        self.assertIn("1 rows", self.table())

    def test_a_row_misfiled_with_no_directory_is_a_known_gap(self):
        """Pins the limitation rather than implying it is covered: a row for a
        page with no artifact directory has no artifact to be missing from, so
        one meant for index-rows/<slug>.yml and left elsewhere goes undetected.
        Recorded in artifacts/index-rows/README.md."""
        self.index_row("a", ROW_A)
        self.index_row("b", ROW_B)
        self.write("artifacts/stray.yml", ROW_B.replace("22222222", "44444444"))
        self.assertEqual(run(self.root).returncode, 0)
        self.assertIn("2 rows", self.table())

    def test_a_non_row_yaml_beside_an_artifact_source_is_left_alone(self):
        """A page's own data and its gitignored `build/` scratch are not rows."""
        self.index_row("a", ROW_A)
        self.artifact("page-b", ROW_B)
        self.write("artifacts/page-b/chart-data.yml", "series:\n  - [1, 2]\n")
        self.write("artifacts/page-b/build/scratch.yml", ROW_B.replace("B", "S"))
        self.assertEqual(run(self.root).returncode, 0)
        self.assertIn("2 rows", self.table())

    def test_the_index_rows_readme_is_not_mistaken_for_a_row(self):
        self.index_row("a", ROW_A)
        self.write("artifacts/index-rows/README.md", "# how rows work\n")
        self.assertEqual(run(self.root).returncode, 0)
        self.assertIn("1 rows", self.table())

    # --- a duplicate key: a value lost before anything checks it ----------

    def test_a_duplicate_key_is_rejected_rather_than_last_one_winning(self):
        """YAML keeps the last value for a repeated key and discards the first
        without a word, so two `url:` lines index one address and forget the
        other. The message names the file, the key and the line."""
        for second in (
            ("url: https://claude.ai/code/artifact/"
             "44444444-4444-4444-4444-444444444444"),
            "title: Page B, again",
            "status: archived",
            "public: https://example.com/mirror",
        ):
            with self.subTest(second):
                before = self.two_good_rows()
                self.index_row("b", ROW_B + second + "\n")
                self.assert_rejected(before, "b.yml", second.split(":", 1)[0],
                                     "twice", f"line {len(ROW_B.splitlines()) + 1}")

    def test_a_duplicate_key_in_an_artifact_meta_is_rejected_too(self):
        """Both locations load through the same reader."""
        before = self.two_good_rows()
        self.artifact("page-c", ROW_B.replace("22222222", "33333333")
                      + "org: Another Org\n")
        self.assert_rejected(before, "meta.yml", "org")


class RealRepoTest(unittest.TestCase):
    """The committed ARTIFACTS.md must match its own YAML files."""

    def test_committed_index_is_current(self):
        result = run(REPO, "--check")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_real_tree_builds_to_eighteen_rows(self):
        """The literal count the reviewer watched collapse to 17. Pinned as a
        number so any future silent drop shows up here as well as in the
        derived count below."""
        result = run(REPO, "--check")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("(18 rows)", result.stdout)
        self.assertIn("18 rows:", (REPO / "ARTIFACTS.md").read_text(encoding="utf-8"))

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
