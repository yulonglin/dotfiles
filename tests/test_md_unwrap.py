"""Regression tests for custom_bins/md-unwrap.

The checker rewrites documentation in place, so the tests that matter most are
the ones proving what it must NOT touch: fenced and indented code, tables, YAML
frontmatter, list markers, link reference definitions, HTML blocks, explicit
hard breaks, and single-line paragraphs. Those come first.

Run: python3 -m unittest tests.test_md_unwrap   (or pytest tests/test_md_unwrap.py)
"""

from __future__ import annotations

import importlib.util
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
SCRIPT = REPO_ROOT / "custom_bins" / "md-unwrap"

_spec = importlib.util.spec_from_loader(
    "md_unwrap", importlib.machinery.SourceFileLoader("md_unwrap", str(SCRIPT))
)
md_unwrap = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(md_unwrap)


def doc(text: str) -> str:
    return textwrap.dedent(text).lstrip("\n")


def fix(text: str) -> str:
    return md_unwrap.unwrap(text)[0]


def violations(text: str) -> list[int]:
    return md_unwrap.unwrap(text)[1]


class TestLeavesStructureAlone(unittest.TestCase):
    """Everything that is not flowing prose must survive byte-identical."""

    def assert_untouched(self, text: str) -> None:
        fixed, merged, _ = md_unwrap.unwrap(text)
        self.assertEqual([], merged)
        self.assertEqual(text, fixed)

    def test_fenced_code_block_keeps_its_line_breaks(self):
        self.assert_untouched(doc("""
            Intro line.

            ```python
            def f():
                return (1
                        + 2)
            ```
            """))

    def test_tilde_fence_and_nested_backticks_survive(self):
        self.assert_untouched(doc("""
            ~~~
            one
            two
            ```
            still fenced
            ~~~
            """))

    def test_indented_code_block_survives(self):
        self.assert_untouched(doc("""
            Prose paragraph.

                indented code
                more code
            """))

    def test_table_rows_are_never_joined(self):
        self.assert_untouched(doc("""
            | Want to | Command |
            |---|---|
            | commit | `/commit` |
            | push | `git push` |
            """))

    def test_yaml_frontmatter_survives(self):
        self.assert_untouched(doc("""
            ---
            name: thing
            description: a long description
              that the YAML parser folds
            ---

            Body line.
            """))

    def test_link_reference_definitions_stay_on_their_own_lines(self):
        self.assert_untouched(doc("""
            [one]: https://example.com/one
            [two]: https://example.com/two
            """))

    def test_html_block_lines_are_untouched(self):
        self.assert_untouched(doc("""
            <details>
            <summary>Click</summary>
            body text
            </details>
            """))

    def test_html_comment_block_is_untouched(self):
        self.assert_untouched(doc("""
            <!-- a comment
            spanning lines -->
            """))

    def test_single_line_paragraphs_are_not_violations(self):
        self.assert_untouched(doc("""
            # Heading

            A short line.

            Another short line.

            - a bullet
            - another bullet
            """))

    def test_explicit_hard_break_is_respected(self):
        self.assert_untouched("line one with a break  \nline two\n")
        self.assert_untouched("line one with a backslash\\\nline two\n")

    def test_bolded_label_lines_stay_one_point_per_line(self):
        self.assert_untouched(doc("""
            **What it is**: a horizontal chain of stages.
            **When to use**: showing data flow.
            """))

    def test_underscore_bolded_label_lines_stay_put(self):
        self.assert_untouched(doc("""
            __Key styles__: bluebox, lavbox
            __Complexity__: low
            """))

    def test_setext_heading_underline_is_not_joined(self):
        self.assert_untouched(doc("""
            Title
            =====

            Subtitle
            --------
            """))

    def test_blockquotes_are_left_alone(self):
        self.assert_untouched(doc("""
            > quoted line one
            > quoted line two
            """))

    def test_thematic_break_is_not_joined(self):
        self.assert_untouched(doc("""
            Paragraph.

            ---

            Next paragraph.
            """))


class TestJoinsWrappedProse(unittest.TestCase):
    def test_wrapped_paragraph_becomes_one_line(self):
        self.assertEqual(
            "This is a paragraph that someone hard wrapped at eighty columns.\n",
            fix("This is a paragraph that someone\nhard wrapped at eighty columns.\n"),
        )

    def test_list_marker_survives_but_wrapped_body_is_joined(self):
        self.assertEqual(
            doc("""
                - first item body continues here
                - second item
                """),
            fix(doc("""
                - first item
                  body continues here
                - second item
                """)),
        )

    def test_nested_list_marker_is_not_swallowed(self):
        source = doc("""
            - parent item
              - child item
            """)
        self.assertEqual(source, fix(source))

    def test_a_wrapped_label_body_is_still_joined_onto_its_label(self):
        self.assertEqual(
            "**When to use**: showing data flow through a pipeline.\n",
            fix("**When to use**: showing data flow\nthrough a pipeline.\n"),
        )

    def test_paragraph_after_heading_is_joined_but_heading_is_not(self):
        self.assertEqual(
            doc("""
                # A heading
                prose one prose two
                """),
            fix(doc("""
                # A heading
                prose one
                prose two
                """)),
        )

    def test_counts_paragraphs_and_lines(self):
        _, merged, paragraphs = md_unwrap.unwrap(
            "a one\na two\na three\n\nb one\nb two\n"
        )
        self.assertEqual(3, len(merged))
        self.assertEqual(2, paragraphs)

    def test_reported_line_numbers_are_one_based(self):
        self.assertEqual([2], violations("first\nsecond\n"))

    def test_fix_is_idempotent(self):
        once = fix("wrapped one\nwrapped two\n")
        self.assertEqual(once, fix(once))

    def test_crlf_and_missing_trailing_newline_survive(self):
        self.assertEqual("a b\r\n", fix("a\r\nb\r\n"))
        self.assertEqual("a b", fix("a\nb"))

    def test_prose_resumes_after_a_code_fence(self):
        self.assertEqual(
            doc("""
                ```
                code
                ```
                prose one prose two
                """),
            fix(doc("""
                ```
                code
                ```
                prose one
                prose two
                """)),
        )


class TestCommandLine(unittest.TestCase):
    def run_cli(self, *args: str, stdin: str | None = None):
        return subprocess.run(
            [sys.executable, str(SCRIPT), *args],
            capture_output=True, text=True, input=stdin,
        )

    def test_check_exits_one_on_a_violation(self):
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / "bad.md"
            target.write_text("wrapped one\nwrapped two\n", encoding="utf-8")
            result = self.run_cli("--check", str(target))
            self.assertEqual(1, result.returncode)
            self.assertIn("bad.md", result.stdout)

    def test_check_exits_zero_when_clean(self):
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / "good.md"
            target.write_text("one line paragraph.\n", encoding="utf-8")
            self.assertEqual(0, self.run_cli("--check", str(target)).returncode)

    def test_check_is_the_default_mode(self):
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / "bad.md"
            target.write_text("wrapped one\nwrapped two\n", encoding="utf-8")
            self.assertEqual(1, self.run_cli(str(target)).returncode)

    def test_fix_rewrites_the_file_and_exits_zero(self):
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / "bad.md"
            target.write_text("wrapped one\nwrapped two\n", encoding="utf-8")
            result = self.run_cli("--fix", str(target))
            self.assertEqual(0, result.returncode)
            self.assertEqual("wrapped one wrapped two\n", target.read_text(encoding="utf-8"))

    def test_directory_recursion_finds_nested_markdown(self):
        with tempfile.TemporaryDirectory() as tmp:
            nested = Path(tmp) / "a" / "b"
            nested.mkdir(parents=True)
            (nested / "bad.md").write_text("one\ntwo\n", encoding="utf-8")
            (nested / "notes.txt").write_text("one\ntwo\n", encoding="utf-8")
            result = self.run_cli("--check", tmp)
            self.assertEqual(1, result.returncode)
            self.assertIn("bad.md", result.stdout)
            self.assertNotIn("notes.txt", result.stdout)

    def test_exclude_skips_matching_paths(self):
        with tempfile.TemporaryDirectory() as tmp:
            (Path(tmp) / "skipme.md").write_text("one\ntwo\n", encoding="utf-8")
            result = self.run_cli("--check", "--exclude", "skipme", tmp)
            self.assertEqual(0, result.returncode)

    def test_stdin_check_reports_without_writing(self):
        result = self.run_cli("--check", "-", stdin="one\ntwo\n")
        self.assertEqual(1, result.returncode)

    def test_stdin_fix_writes_to_stdout(self):
        result = self.run_cli("--fix", "-", stdin="one\ntwo\n")
        self.assertEqual(0, result.returncode)
        self.assertEqual("one two\n", result.stdout)

    def test_missing_file_exits_two(self):
        self.assertEqual(2, self.run_cli("--check", "/nonexistent/nope.md").returncode)

    def test_help_works(self):
        result = self.run_cli("--help")
        self.assertEqual(0, result.returncode)
        self.assertIn("--fix", result.stdout)


if __name__ == "__main__":
    unittest.main()
