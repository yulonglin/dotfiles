"""Guards the md2review comment flow, especially on iOS.

Background: a md2review page opened the note box only from a `mouseup` event.
iOS Safari fires no `mouseup` for a touch selection drag, so the page was not
commentable on iPhone or iPad at all. Two further gaps came out of the same
fix: a selection crossing element boundaries saved a comment with no highlight,
and a reload restored the comment list but none of the highlights, so an
existing comment could no longer be clicked open to edit or delete.

These checks are structural: they assert the generated page still carries each
load-bearing piece, and that its JavaScript parses. They are cheap and run
anywhere.

The behavioural check needs a real browser. Serve a generated page over HTTP
(a `file://` URL is blocked in the Playwright plugin) and run, in the page:

    // 1. iOS path: select WITHOUT any mouse event, then wait past the debounce.
    const r = document.createRange();
    const n = document.querySelector('.doc p').firstChild;
    r.setStart(n, 0); r.setEnd(n, 25);
    const s = getSelection(); s.removeAllRanges(); s.addRange(r);
    await new Promise(f => setTimeout(f, 600));
    // #pop must now be display:block, and #txt must NOT have focus.
    // 2. Save a note, reload, and confirm the mark.note comes back and
    //    clicking it reopens the note box with the original text.

Verified against Chromium on 2026-08-18: the pre-fix page never opened the note
box on the selection-only path; the fixed page opened it, saved, restored the
highlight after reload, and reopened it for editing.
"""

from __future__ import annotations

import re
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

MD2REVIEW = Path(__file__).resolve().parent.parent / "custom_bins" / "md2review"


def _interpreter() -> str:
    """An interpreter that can import md2review's markdown-it-py dependency.

    Under `uv run` the ambient `python3` is uv's own, which does not carry the
    dependency, so prefer the system interpreter when it has it.
    """
    for candidate in ("/usr/bin/python3", "python3", sys.executable):
        exe = shutil.which(candidate) if not candidate.startswith("/") else candidate
        if not exe or not Path(exe).exists():
            continue
        probe = subprocess.run(
            [exe, "-c", "import markdown_it"], capture_output=True
        )
        if probe.returncode == 0:
            return exe
    pytest.skip("no interpreter with markdown-it-py available")


def _render(src_text: str, tmp: Path) -> str:
    """Render Markdown through md2review and return the generated HTML."""
    src = tmp / "sample.md"
    src.write_text(src_text, encoding="utf-8")
    out = tmp / "sample.html"
    result = subprocess.run(
        [_interpreter(), str(MD2REVIEW), str(src), "-o", str(out)],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, result.stderr
    return out.read_text(encoding="utf-8")

SAMPLE = """# Sample Page

A paragraph whose source wraps across two lines, so a quote taken from it
contains a line break that the browser renders as a single space.

## A section

Text with `inline code` in the middle of the sentence.
"""


@pytest.fixture(scope="module")
def page_html(tmp_path_factory) -> str:
    return _render(SAMPLE, tmp_path_factory.mktemp("md2review"))


@pytest.fixture(scope="module")
def page_js(page_html: str) -> str:
    """Just the JavaScript of a generated review page."""
    scripts = re.findall(r"<script>(.*?)</script>", page_html, re.S)
    assert scripts, "generated page has no script block"
    return "\n".join(scripts)


def test_source_compiles_without_syntax_warning() -> None:
    """The HTML template is a plain string, so stray backslashes must be escaped."""
    result = subprocess.run(
        [
            "python3",
            "-W",
            "error::SyntaxWarning",
            "-c",
            f"compile(open({str(MD2REVIEW)!r}).read(), 'md2review', 'exec')",
        ],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, result.stderr


def test_opens_the_note_box_without_a_mouse_event(page_js: str) -> None:
    """iOS Safari fires no mouseup for a touch selection drag."""
    assert 'addEventListener("selectionchange"' in page_js
    assert "openForSelection" in page_js


def test_touch_path_does_not_steal_focus(page_js: str) -> None:
    """Focusing the textarea while iOS shows selection handles drops the selection."""
    assert "if (autofocus) txt.focus();" in page_js


def test_debounced_reopen_does_not_wipe_a_half_typed_note(page_js: str) -> None:
    assert "pending.quote === text" in page_js
    assert "document.activeElement === txt" in page_js
    # Typed words survive a selection landing somewhere else entirely.
    # Behaviourally guarded by test_md2review_browser.py; this catches the
    # guard being deleted without a browser present.
    assert "if (isOpen() && hasText()) return true;" in page_js


def test_highlight_survives_a_selection_crossing_elements(page_js: str) -> None:
    """surroundContents refuses such a range, so there must be a fallback."""
    assert "wrapRange" in page_js
    assert "extractContents()" in page_js


def test_highlights_are_restored_on_reload(page_js: str) -> None:
    """Without this, a reloaded comment cannot be clicked open to edit or delete."""
    assert "restoreHighlights" in page_js
    assert re.search(r"^restoreHighlights\(\);$", page_js, re.M)


def test_quote_matching_collapses_whitespace(page_js: str) -> None:
    """A source line break inside a paragraph renders as one space."""
    assert "collapsedIndex" in page_js
    assert 'quote.replace(/\\s+/g, " ")' in page_js


def test_note_box_fits_a_phone_and_does_not_trigger_ios_zoom(page_html: str) -> None:
    assert "width:min(20rem,calc(100vw - 1.5rem))" in page_html
    assert "@media (pointer:coarse)" in page_html


@pytest.mark.skipif(shutil.which("node") is None, reason="node not installed")
def test_generated_javascript_parses(page_js: str, tmp_path) -> None:
    js = tmp_path / "page.js"
    js.write_text(page_js, encoding="utf-8")
    result = subprocess.run(
        ["node", "--check", str(js)], capture_output=True, text=True
    )
    assert result.returncode == 0, result.stderr
