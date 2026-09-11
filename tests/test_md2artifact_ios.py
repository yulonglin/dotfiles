"""Guards the md2artifact comment flow, especially on iOS.

Background: a md2artifact page opened the note box only from a `mouseup` event.
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

MD2REVIEW = Path(__file__).resolve().parent.parent / "custom_bins" / "md2artifact"


def _interpreter() -> str:
    """An interpreter that can import md2artifact's markdown-it-py dependency.

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
    """Render Markdown through md2artifact and return the generated HTML."""
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
    return _render(SAMPLE, tmp_path_factory.mktemp("md2artifact"))


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
            f"compile(open({str(MD2REVIEW)!r}).read(), 'md2artifact', 'exec')",
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
    # Behaviourally guarded by test_md2artifact_browser.py; this catches the
    # guard being deleted without a browser present.
    assert "if (isOpen() && dirty) return true;" in page_js


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


# --- generated ids are unique ------------------------------------------------
# A checklist item's persistence id, and a heading's anchor, are both slugs of
# visible text, suffixed with a number when two of them slugify the same. The
# suffix counter used to tally the ORIGINAL slug only, never the suffixed ids
# it had already handed out — so two items labelled "ship it" emitted
# "ship-it" and "ship-it-1", and a third item labelled "ship it 1" slugified
# to "ship-it-1" on its own and took the same id. Two controls then shared one
# storage slot and silently overwrote each other's saved state. These are the
# browser-free half of that guard: they fail on the emitted markup alone.

COLLIDING = """# Collision Sample

- [ ] ship it
- [ ] ship it
- [ ] ship it 1
- [ ] ship it

## A section

## A section

## A section 1
"""


def _state_ids(html_text: str) -> list[str]:
    return re.findall(r'data-an-state-id="([^"]*)"', html_text)


@pytest.fixture(scope="module")
def colliding_html(tmp_path_factory) -> str:
    return _render(COLLIDING, tmp_path_factory.mktemp("md2artifact-collide"))


def test_every_task_id_is_unique(colliding_html: str) -> None:
    ids = _state_ids(colliding_html)
    assert len(ids) == 4, ids
    assert len(set(ids)) == len(ids), f"two controls share a persistence id: {ids}"


def test_task_ids_keep_incrementing_past_a_label_that_looks_suffixed(
    colliding_html: str,
) -> None:
    """The exact allocation, pinned: a suffix is retried until genuinely free."""
    assert _state_ids(colliding_html) == [
        "ship-it",
        "ship-it-1",
        "ship-it-1-1",
        "ship-it-2",
    ]


def test_every_heading_id_is_unique(colliding_html: str) -> None:
    """Duplicate DOM ids send a table-of-contents link to the wrong section."""
    ids = re.findall(r'<h2 id="([^"]*)"', colliding_html)
    assert len(ids) == len(set(ids)), f"two headings share an anchor: {ids}"
    assert [i for i in ids if i.startswith("a-section")] == [
        "a-section",
        "a-section-1",
        "a-section-1-1",
    ], ids


# --- a declared state set is checked at build time ---------------------------
# Copy all writes each state into the brackets of a Markdown task line
# (`- [deny] the label`), which is what makes the export paste back into the
# source. A state carrying a bracket produces `- [de]ny] the label`, a line no
# Markdown parser reads as a task item — and the build that accepted it is long
# over by the time anyone looks at the clipboard. So the set is rejected where
# the author can still see the message.


def _run_states(spec: str, tmp: Path) -> subprocess.CompletedProcess[str]:
    src = tmp / "states.md"
    src.write_text("# T\n\n- [ ] one\n", encoding="utf-8")
    return subprocess.run(
        [_interpreter(), str(MD2REVIEW), str(src), "-o", str(tmp / "out.html"),
         "--states", spec],
        capture_output=True,
        text=True,
    )


@pytest.mark.parametrize(
    "spec",
    ["ok,de]ny", "o[k,deny", "ok,de\nny", "ok,de\tny"],
    ids=["close-bracket", "open-bracket", "newline", "tab"],
)
def test_a_state_that_breaks_the_exported_line_is_refused(spec: str, tmp_path) -> None:
    r = _run_states(spec, tmp_path)
    assert r.returncode != 0, r.stdout
    assert "--states must not contain" in r.stderr, r.stderr


@pytest.mark.parametrize(
    "spec",
    ["approve,approve-pending-edits,deny", "yes,no,ask Ana (v2): 50%"],
    ids=["the-documented-set", "punctuation-that-is-fine"],
)
def test_an_ordinary_state_set_still_builds(spec: str, tmp_path) -> None:
    """Only the characters that break the line are refused, not punctuation."""
    r = _run_states(spec, tmp_path)
    assert r.returncode == 0, r.stderr
