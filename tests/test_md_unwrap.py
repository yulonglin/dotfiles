"""Regression tests for custom_bins/md-unwrap.

The checker rewrites documentation in place, so the tests that matter most are
the ones proving what it must NOT touch: fenced and indented code, tables, YAML
frontmatter, list markers, link reference definitions, HTML blocks, explicit
hard breaks, and single-line paragraphs. Those come first.

Run: python3 -m unittest tests.test_md_unwrap   (or pytest tests/test_md_unwrap.py)
"""

from __future__ import annotations

import importlib.util
import re
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


def render_markdown(text: str) -> str:
    """Render with python-markdown, pulled through uv when it is not importable."""
    try:
        import markdown  # noqa: PLC0415
    except ImportError:
        pass
    else:
        return markdown.markdown(text)
    probe = subprocess.run(
        ["uv", "run", "--no-project", "--with", "markdown", "python", "-c",
         "import sys,markdown;sys.stdout.write(markdown.markdown(sys.stdin.read()))"],
        capture_output=True, text=True, input=text,
    )
    if probe.returncode != 0:
        raise unittest.SkipTest("no markdown renderer available: " + probe.stderr[-200:])
    return probe.stdout


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


class TestRawHtmlBlocksSurvive(unittest.TestCase):
    """<pre>, <script>, <style> and <textarea> are protected to their closing tag.

    A blank line inside such a block does not end it (CommonMark HTML block type
    1 runs to the closing tag), so joining must not resume part-way through: the
    rendered page would change, and inside a script the code would change meaning.
    """

    RAW_TAGS = ("pre", "script", "style", "textarea")

    def test_raw_block_with_an_internal_blank_line_is_byte_identical(self):
        for tag in self.RAW_TAGS:
            with self.subTest(tag=tag):
                source = (
                    "Intro paragraph.\n"
                    "\n"
                    f"<{tag}>\n"
                    "first inner line\n"
                    "\n"
                    "second inner line\n"
                    "third inner line\n"
                    f"</{tag}>\n"
                    "\n"
                    "Closing paragraph.\n"
                )
                fixed, merged, _ = md_unwrap.unwrap(source)
                self.assertEqual([], merged, f"joined inside a <{tag}> block")
                self.assertEqual(source, fixed)

    def test_raw_block_with_attributes_and_mixed_case_is_protected(self):
        source = doc("""
            <PRE class="sample">
            one

            two
            three
            </PRE>
            """)
        self.assertEqual(source, fix(source))

    def test_raw_block_protects_to_the_closing_tag_not_the_next_blank_line(self):
        source = doc("""
            <pre>
            alpha

            beta
            gamma
            </pre>
            """)
        self.assertNotIn("beta gamma", fix(source))

    def test_opening_and_closing_tag_on_one_line_ends_the_block(self):
        # The block ends on its own line, so the prose after it is ordinary
        # prose and is joined; protection must not run to the end of file.
        self.assertEqual(
            doc("""
                <pre>inline sample</pre>
                prose one prose two
                """),
            fix(doc("""
                <pre>inline sample</pre>
                prose one
                prose two
                """)),
        )

    def test_a_later_raw_block_is_still_protected_after_a_one_line_block(self):
        source = doc("""
            <pre>inline</pre>

            <pre>
            alpha

            beta
            gamma
            </pre>
            """)
        self.assertEqual(source, fix(source))


class TestPipeOnAnHtmlBlockOpeningLine(unittest.TestCase):
    """A pipe on the opening line must not cancel HTML-block protection.

    The pipe-and-table exclusion is a heuristic ("any line carrying a pipe might
    be a table row"); an HTML block start is a real block-level construct that
    installs protection state. While the heuristic ran first, an opening tag
    carrying a pipe — in an attribute value, or in content on the same line —
    was taken by the heuristic and returned early, so the protection was never
    installed at all and every following line was treated as ordinary prose.
    Inside <pre> that changes what the page renders; inside <script> it changes
    what the code does.
    """

    RAW_TAGS = ("pre", "script", "style", "textarea")

    def assert_untouched(self, source: str, message: str = "") -> None:
        fixed, merged, _ = md_unwrap.unwrap(source)
        self.assertEqual([], merged, message)
        self.assertEqual(source, fixed, message)

    def block(self, opening: str, tag: str) -> str:
        return (
            "Intro paragraph.\n"
            "\n"
            f"{opening}\n"
            "\n"
            "first inner line\n"
            "second inner line\n"
            f"</{tag}>\n"
            "\n"
            "Closing paragraph.\n"
        )

    def test_pipe_in_an_attribute_value_still_protects_the_block(self):
        for tag in self.RAW_TAGS:
            with self.subTest(tag=tag):
                source = self.block(f'<{tag} class="col-a|col-b">', tag)
                self.assert_untouched(source, f"joined inside a <{tag}> opened with a piped attribute")

    def test_pipe_in_the_opening_lines_content_still_protects_the_block(self):
        for tag in self.RAW_TAGS:
            with self.subTest(tag=tag):
                source = self.block(f"<{tag}>alpha | beta", tag)
                self.assert_untouched(source, f"joined inside a <{tag}> whose opening line content has a pipe")

    def test_the_rendered_preformatted_content_does_not_change(self):
        source = (
            '<pre class="a|b">\n'
            "\n"
            "first inner line\n"
            "second inner line\n"
            "</pre>\n"
        )
        self.assertEqual(render_markdown(source), render_markdown(fix(source)))

    def test_html_comment_with_a_pipe_is_protected_to_its_terminator(self):
        self.assert_untouched("<!-- columns | rows\ncomment line one\ncomment line two\n-->\n")

    def test_generic_html_block_with_a_pipe_is_protected_to_the_blank_line(self):
        self.assert_untouched('<div data-cols="a|b">\nline one\nline two\n</div>\n')

    def test_a_genuine_markdown_table_is_still_excluded(self):
        # The guard that moved must still do its job: without it the first table
        # row would be joined onto the prose line above it.
        self.assert_untouched(doc("""
            Intro prose line.
            | Want to | Command |
            |---|---|
            | commit | `/commit` |
            | push | `git push` |
            """))

    def test_pipe_heavy_prose_is_still_left_alone(self):
        self.assert_untouched("a | b | c\nd | e | f\n")


class TestNoJoinInsideAProtectedRegion(unittest.TestCase):
    """A property check over constructed documents, not the repo's own Markdown.

    The repo contains no HTML block whose opening line carries a pipe, so a
    corpus sweep stays green however badly the guards are ordered — which is how
    the pipe-before-HTML defect survived the previous fix and its sweep. This
    builds the documents instead: every state-installing construct, opened with
    every decoration that could plausibly hijack its opening line, and asserts
    that no line inside the resulting block is ever joined.

    The region scanner below is deliberately independent of merge_indices — it
    is the ground truth the fixer is checked against, not a copy of its logic.
    """

    RAW_TAGS = ("pre", "script", "style", "textarea")
    DECORATIONS = ("", ' class="a|b"', ">alpha | beta", ">   ", " data-x='a|b'")
    BODIES = (
        ("one", "", "two", "three"),
        ("a | b", "c", "", "d"),
        ("x", "  y  ", "z"),
    )
    PREFIXES = ((), ("Lead prose line.",), ("Lead prose.", ""))

    def protected_lines(self, lines: list[str]) -> set[int]:
        """Indices strictly inside a fence or a raw/comment HTML block."""
        inside: str | None = None
        protected: set[int] = set()
        for index, line in enumerate(lines):
            stripped = line.strip().lower()
            if inside is None:
                if stripped.startswith(("```", "~~~")):
                    inside = "fence"
                elif stripped.startswith("<!--") and "-->" not in stripped:
                    inside = "-->"
                else:
                    for tag in self.RAW_TAGS:
                        if stripped.startswith("<" + tag) and f"</{tag}>" not in stripped:
                            inside = f"</{tag}>"
                            break
            elif inside == "fence":
                if stripped.startswith(("```", "~~~")):
                    inside = None
            elif inside in stripped:
                inside = None
            else:
                protected.add(index)
        return protected

    def documents(self):
        openers = {}
        for tag in self.RAW_TAGS:
            for decoration in self.DECORATIONS:
                opener = f"<{tag}{decoration}" if decoration.startswith(">") else f"<{tag}{decoration}>"
                openers[opener] = f"</{tag}>"
        openers["<!-- note | here"] = "-->"
        openers["```python"] = "```"
        openers["~~~"] = "~~~"
        for opener, closer in openers.items():
            for body in self.BODIES:
                for prefix in self.PREFIXES:
                    lines = [*prefix, opener, *body, closer, "", "trailing one", "trailing two"]
                    yield opener, lines

    def test_no_constructed_document_is_joined_inside_its_block(self):
        checked = 0
        for opener, lines in self.documents():
            checked += 1
            clash = set(md_unwrap.merge_indices(lines)) & self.protected_lines(lines)
            self.assertEqual(
                set(), clash,
                f"joined inside the block opened by {opener!r}: lines {sorted(clash)}",
            )
        self.assertGreater(checked, 150, "the construction matrix shrank")


class TestHardBreaksSurviveJoining(unittest.TestCase):
    """Two trailing spaces are a hard line break and must not be stripped."""

    SOURCE = "alpha one\nalpha two  \nalpha three\n"

    def test_a_hard_break_on_a_joined_line_is_preserved(self):
        self.assertEqual("alpha one alpha two  \nalpha three\n", fix(self.SOURCE))

    def test_the_rendered_line_break_survives(self):
        before = render_markdown(self.SOURCE)
        after = render_markdown(fix(self.SOURCE))
        self.assertIn("<br", before)
        self.assertIn("<br", after)

    def test_a_backslash_hard_break_on_a_joined_line_is_preserved(self):
        self.assertEqual(
            "alpha one alpha two\\\nalpha three\n",
            fix("alpha one\nalpha two\\\nalpha three\n"),
        )

    def test_joining_a_paragraph_with_a_hard_break_is_idempotent(self):
        once = fix(self.SOURCE)
        self.assertEqual(once, fix(once))

    def test_incidental_single_trailing_space_is_still_tidied(self):
        self.assertEqual("alpha one alpha two\n", fix("alpha one\nalpha two \n"))


def render_commonmark(text: str) -> str:
    """Render with a strict CommonMark implementation, pulled through uv if needed."""
    try:
        from markdown_it import MarkdownIt
    except ImportError:
        pass
    else:
        return MarkdownIt("commonmark").render(text)
    probe = subprocess.run(
        ["uv", "run", "--no-project", "--with", "markdown-it-py", "python", "-c",
         ("import sys;from markdown_it import MarkdownIt;"
          "sys.stdout.write(MarkdownIt('commonmark').render(sys.stdin.read()))")],
        capture_output=True, text=True, input=text,
    )
    if probe.returncode != 0:
        raise unittest.SkipTest("no CommonMark renderer available: " + probe.stderr[-200:])
    return probe.stdout


class TestBlocksNestedInsideContainers(unittest.TestCase):
    """A block start is measured from its CONTAINER's column, not from column zero.

    Round two moved the HTML-block guard above the pipe heuristic, on the rule
    that a guard installing protection STATE must beat a guard that skips one
    line. The rule was right and the reading of it was too narrow: a guard that
    is never REACHED is as absent as one that runs too late. A fence or a raw
    HTML element written directly after a list marker was taken by the list-item
    guard, which skips exactly one line; the block was never entered, and every
    line of it was joined onto the opening fence's info string. A two-line code
    block came out rendering as an empty one.

    So the recogniser now runs against the line with its container prefixes
    removed, at every column CommonMark allows: column zero, an item's content
    column, and inside a blockquote. Indented code still wins at four columns
    past the container, which is the line CommonMark draws.
    """

    MARKERS = ("-", "*", "+", "1.", "2)")
    FENCES = ("```", "~~~")
    LANGS = ("", "python")
    RAW_TAGS = ("pre", "script", "style", "textarea")

    def assert_untouched(self, source: str, message: str = "") -> None:
        fixed, merged, _ = md_unwrap.unwrap(source)
        self.assertEqual([], merged, message or source)
        self.assertEqual(source, fixed, message or source)
        self.assertEqual(render_commonmark(source), render_commonmark(fixed), message or source)

    def test_a_fence_opened_on_the_list_marker_line_is_a_code_block(self):
        for marker in self.MARKERS:
            for fence in self.FENCES:
                for lang in self.LANGS:
                    with self.subTest(marker=marker, fence=fence, lang=lang):
                        pad = " " * (len(marker) + 1)
                        source = (f"{marker} {fence}{lang}\n"
                                  f"{pad}x = 1\n{pad}y = 2\n{pad}{fence}\n")
                        self.assert_untouched(source)

    def test_a_fence_on_its_own_line_at_the_items_content_column(self):
        for marker in self.MARKERS:
            for fence in self.FENCES:
                with self.subTest(marker=marker, fence=fence):
                    pad = " " * (len(marker) + 1)
                    source = (f"{marker} item body\n\n"
                              f"{pad}{fence}sh\n{pad}x = 1\n{pad}y = 2\n{pad}{fence}\n")
                    self.assert_untouched(source)

    def test_a_raw_html_block_opened_on_the_list_marker_line(self):
        for marker in self.MARKERS:
            for tag in self.RAW_TAGS:
                with self.subTest(marker=marker, tag=tag):
                    pad = " " * (len(marker) + 1)
                    source = (f"{marker} <{tag}>\n"
                              f"{pad}first inner line\n\n{pad}second inner line\n"
                              f"{pad}</{tag}>\n")
                    self.assert_untouched(source)

    def test_a_generic_html_block_opened_on_the_list_marker_line(self):
        self.assert_untouched('- <div class="a|b">\n  line one\n  line two\n  </div>\n')

    def test_content_dedented_out_of_the_item_is_prose_again(self):
        # An HTML block is not lazy, so unindented lines leave the item and are
        # an ordinary paragraph — joining them is the right answer, and the
        # rendered code block above them is unaffected.
        source = '- <div class="a|b">\nline one\nline two\n</div>\n'
        self.assertEqual('- <div class="a|b">\nline one line two\n</div>\n', fix(source))

    def test_an_html_comment_opened_on_the_list_marker_line(self):
        self.assert_untouched("- <!-- columns | rows\n  comment one\n  comment two\n  -->\n")

    def test_a_fence_inside_a_blockquote(self):
        for fence in self.FENCES:
            with self.subTest(fence=fence):
                self.assert_untouched(f"> {fence}py\n> x = 1\n> y = 2\n> {fence}\n")

    def test_a_raw_html_block_inside_a_blockquote(self):
        self.assert_untouched("> <pre>\n> first inner line\n> second inner line\n> </pre>\n")

    def test_a_fence_inside_a_list_inside_a_blockquote(self):
        for fence in self.FENCES:
            with self.subTest(fence=fence):
                self.assert_untouched(f"> - {fence}py\n>   x = 1\n>   y = 2\n>   {fence}\n")

    def test_a_fence_two_list_levels_deep(self):
        self.assert_untouched("- outer\n  - inner\n\n    ```py\n    x = 1\n    y = 2\n    ```\n")

    def test_a_block_leaving_its_blockquote_does_not_protect_the_prose_after_it(self):
        # <pre> is not lazy, so the unquoted lines are a plain paragraph and
        # joining them is the right answer.
        self.assertEqual(
            "> <pre>\nprose one prose two\n",
            fix("> <pre>\nprose one\nprose two\n"),
        )


class TestClosingDelimiterIndentation(unittest.TestCase):
    """The closing fence is measured against the container column too.

    CommonMark lets the closing fence sit up to three spaces past its
    container's content column, and ends the block with the container when a
    line dedents out of it. Matching the closer against column zero alone either
    reopens the document mid-code-block or freezes the rest of the file.
    """

    def test_a_closer_three_columns_past_the_container_still_closes(self):
        source = "- ```py\n  x = 1\n     ```\nprose one\nprose two\n"
        self.assertEqual(
            "- ```py\n  x = 1\n     ```\nprose one prose two\n",
            fix(source),
        )
        self.assertIn("<code", render_commonmark(fix(source)))

    def test_a_closer_four_columns_past_the_container_stays_inside_the_block(self):
        source = "- ```py\n  x = 1\n      ```\nprose one\nprose two\n"
        self.assertEqual("- ```py\n  x = 1\n      ```\nprose one prose two\n", fix(source))

    def test_an_item_ending_closes_the_fence_it_opened(self):
        source = "- ```py\n  x = 1\n\nprose one\nprose two\n"
        self.assertEqual("- ```py\n  x = 1\n\nprose one prose two\n", fix(source))

    def test_a_construct_indented_under_a_paragraph_continuation_is_left_alone(self):
        # Four spaces after a paragraph line is a lazy continuation, not a
        # fence. The tool does not join it — under-fixing, never corrupting.
        for construct in ("```", "~~~", "<pre>"):
            with self.subTest(construct=construct):
                source = f"prose line\n    {construct}\nstill prose\n"
                self.assertEqual(source, fix(source))


class TestRefusesDocumentsItCannotFollow(unittest.TestCase):
    """Out of its depth is reported, never silently rewritten."""

    def test_an_unterminated_fence_leaves_the_whole_document_alone(self):
        source = "```py\nx = 1\nprose one\nprose two\n"
        fixed, merged, _, refusal = md_unwrap.analyse(source)
        self.assertEqual(source, fixed)
        self.assertEqual([], merged)
        self.assertIn("unterminated code fence", refusal)

    def test_an_unterminated_raw_html_block_leaves_the_whole_document_alone(self):
        source = "<pre>\na\nprose one\nprose two\n"
        _, merged, _, refusal = md_unwrap.analyse(source)
        self.assertEqual([], merged)
        self.assertIn("unterminated", refusal)

    def test_the_cli_reports_the_refusal_and_writes_nothing(self):
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / "unterminated.md"
            source = "```py\nx = 1\nprose one\nprose two\n"
            target.write_text(source, encoding="utf-8")
            result = subprocess.run(
                [sys.executable, str(SCRIPT), "--fix", str(target)],
                capture_output=True, text=True,
            )
            self.assertEqual(source, target.read_text(encoding="utf-8"))
            self.assertIn("left unchanged", result.stderr)
            self.assertIn("unterminated code fence opened at line 1", result.stderr)


class TestNoJoinInsideANestedProtectedRegion(unittest.TestCase):
    """The property check of the round-two fix, run again inside every container.

    The flat matrix stayed green through this defect: nothing in it was indented
    under anything. Each document is rebuilt inside a list item, a blockquote and
    a list inside a blockquote, and the ground truth reads the same documents
    with the container prefix removed.
    """

    CONTAINERS = (
        ("- ", "  "),
        ("* ", "  "),
        ("+ ", "  "),
        ("1. ", "   "),
        ("10) ", "    "),
        ("> ", "> "),
        ("> - ", ">   "),
    )

    def wrap(self, lines: list[str], first: str, rest: str) -> list[str]:
        return [(first if i == 0 else rest) + line for i, line in enumerate(lines)]

    def unwrap_prefix(self, line: str, first: str, rest: str, index: int) -> str:
        prefix = first if index == 0 else rest
        return line[len(prefix):] if line.startswith(prefix) else line

    def test_no_nested_document_is_joined_inside_its_block(self):
        flat = TestNoJoinInsideAProtectedRegion()
        checked = 0
        for opener, lines in flat.documents():
            for first, rest in self.CONTAINERS:
                nested = self.wrap(lines, first, rest)
                bare = [self.unwrap_prefix(line, first, rest, i)
                        for i, line in enumerate(nested)]
                checked += 1
                clash = set(md_unwrap.merge_indices(nested)) & flat.protected_lines(bare)
                self.assertEqual(
                    set(), clash,
                    f"joined inside {opener!r} nested under {first!r}: lines {sorted(clash)}",
                )
        self.assertGreater(checked, 1000, "the nesting matrix shrank")

    def test_the_rendering_of_every_nested_document_survives_the_fix(self):
        """What a reader sees must not move, whatever --fix does to the bytes.

        Joining a wrapped paragraph turns a newline inside a <p> into a space
        and changes nothing else, so comparing the rendered HTML with runs of
        whitespace collapsed is exactly the invariant: a block whose start was
        missed loses its <pre>, which no amount of whitespace collapsing hides.
        """
        flat = TestNoJoinInsideAProtectedRegion()
        def collapse(html: str) -> str:
            return re.sub(r"\s+", " ", html).strip()

        checked = 0
        for _opener, lines in flat.documents():
            for first, rest in (("", ""), *self.CONTAINERS):
                source = "".join((first if i == 0 else rest) + line + "\n"
                                 for i, line in enumerate(lines))
                checked += 1
                self.assertEqual(
                    collapse(render_commonmark(source)),
                    collapse(render_commonmark(fix(source))),
                    f"--fix changed what {first!r}-nested document renders as:\n{source}",
                )
        self.assertGreater(checked, 1000, "the nesting matrix shrank")


# Documents that previously moved on a second --fix. The repo's own Markdown
# does not happen to contain these shapes, so the corpus sweep below would pass
# on the broken fixer without them.
ADVERSARIAL_FIXTURES = {
    "hard-break-mid-paragraph": "alpha one\nalpha two  \nalpha three\n",
    "hard-break-in-a-list-body": "- item one\n  item two  \n  item three\n",
    "backslash-break-mid-paragraph": "alpha one\nalpha two\\\nalpha three\n",
    "hard-break-after-a-label": "**Label**: one\ntwo  \nthree\n",
    "pre-block-with-a-blank-line": "<pre>\na\n\nb\nc\n</pre>\n",
    "script-block-with-a-blank-line": "<script>\nx = 1\n\ny = 2\nz = 3\n</script>\n",
    "one-line-pre-then-prose": "<pre>inline</pre>\nprose one\nprose two\n",
    "pre-opened-with-a-piped-attribute": '<pre class="a|b">\nalpha\n\nbeta\ngamma\n</pre>\n',
    "script-with-a-pipe-on-the-opening-line": "<script>var re = /a|b/;\nx = 1\n\ny = 2\nz = 3\n</script>\n",
    "comment-with-a-pipe-on-the-opening-line": "<!-- cols | rows\nline one\nline two\n-->\n",
    "table-directly-under-prose": "Intro prose line.\n| a | b |\n|---|---|\n| 1 | 2 |\n",
    "fence-on-a-list-marker-line": "- ```python\n  x = 1\n  y = 2\n  ```\n",
    "tilde-fence-on-a-list-marker-line": "* ~~~\n  x = 1\n  y = 2\n  ~~~\n",
    "pre-on-a-list-marker-line": "1. <pre>\n   a\n\n   b\n   </pre>\n",
    "fence-inside-a-blockquote-list": "> - ```py\n>   x = 1\n>   y = 2\n>   ```\n",
    "closer-indented-past-the-container": "- ```py\n  x = 1\n     ```\nprose one\nprose two\n",
}


class TestIdempotentOverTheRepoCorpus(unittest.TestCase):
    """--fix twice must equal --fix once, over the whole corpus."""

    def corpus(self) -> dict[str, str]:
        documents = dict(ADVERSARIAL_FIXTURES)
        for path in sorted(REPO_ROOT.rglob("*.md")):
            if any(part in md_unwrap.DEFAULT_EXCLUDES for part in path.parts):
                continue
            try:
                documents[str(path.relative_to(REPO_ROOT))] = path.read_text(encoding="utf-8")
            except (OSError, UnicodeDecodeError):
                continue
        return documents

    def test_every_document_reaches_a_fixed_point(self):
        documents = self.corpus()
        self.assertGreater(len(documents), 100, "corpus looks too small to be the repo")
        unstable = [name for name, text in documents.items()
                    if fix(fix(text)) != fix(text)]
        self.assertEqual([], unstable, "--fix is not idempotent for these documents")

    def test_the_cli_gives_the_same_bytes_on_a_second_run(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for name, text in ADVERSARIAL_FIXTURES.items():
                (root / f"{name}.md").write_text(text, encoding="utf-8")
            run = lambda: subprocess.run(  # noqa: E731
                [sys.executable, str(SCRIPT), "--fix", "-q", str(root)],
                capture_output=True, text=True, check=False,
            )
            run()
            once = {p.name: p.read_bytes() for p in sorted(root.glob("*.md"))}
            run()
            twice = {p.name: p.read_bytes() for p in sorted(root.glob("*.md"))}
            self.assertEqual(once, twice)


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


class TestRepoMarkdownStaysClean(unittest.TestCase):
    """The gate itself: Markdown under claude/ must stay unwrapped."""

    def test_claude_markdown_has_no_hard_wrapped_paragraphs(self):
        result = subprocess.run(
            [sys.executable, str(SCRIPT), "--check", str(REPO_ROOT / "claude")],
            capture_output=True, text=True,
        )
        if result.returncode != 0:
            self.fail("hard-wrapped Markdown under claude/:\n" + result.stdout)


if __name__ == "__main__":
    unittest.main()
