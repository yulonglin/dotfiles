"""Behavioural checks for the md2review comment box, driven in a real browser.

The structural tests in `test_md2review_ios.py` assert the generated page still
carries each load-bearing piece. These assert what a reviewer actually
experiences, because the bugs they guard were all invisible to a string match:

- the note box used to open on `mouseup` and then close itself ~350ms later.
  Opening it focuses the textarea, focusing collapses the document selection,
  and the debounced `selectionchange` handler read that collapse back as "the
  user deselected" and closed the box. That was the flicker.
- Enter had no binding, so the advertised select-type-Enter flow did nothing.
- a forced refresh dropped whatever was half-typed into the box.

Needs Playwright and Chromium; skipped when either is missing. The page is
served over HTTP because `file://` is blocked in the Playwright plugin.
"""

from __future__ import annotations

import functools
import http.server
import shutil
import socketserver
import subprocess
import sys
import threading
from pathlib import Path

import pytest

playwright_api = pytest.importorskip("playwright.sync_api")
sync_playwright = playwright_api.sync_playwright

ROOT = Path(__file__).resolve().parent.parent
MD2REVIEW = ROOT / "custom_bins" / "md2review"

SAMPLE = """# Review Sample

The first paragraph of the document, long enough that a selection taken from
the middle of it is unambiguous.

## A section

A second paragraph living under its own heading, also comfortably long.
"""

# Selects characters 4..40 of the first paragraph without any mouse event,
# which is the code path iOS Safari takes for a touch drag.
SELECT_JS = """() => {
  const n = document.querySelector('.doc p').firstChild;
  const r = document.createRange();
  r.setStart(n, 4); r.setEnd(n, 40);
  const s = getSelection(); s.removeAllRanges(); s.addRange(r);
  return r.toString();
}"""

POP_OPEN = "() => getComputedStyle(document.getElementById('anPop')).display === 'block'"


@pytest.fixture(scope="module")
def site(tmp_path_factory) -> str:
    """Render the sample and serve its directory; yields the page URL."""
    tmp = tmp_path_factory.mktemp("md2review-browser")
    src = tmp / "sample.md"
    src.write_text(SAMPLE, encoding="utf-8")
    for name, key in (("index.html", "review-sample"), ("renamed.html", "review-sample-v2")):
        r = subprocess.run(
            [sys.executable, str(MD2REVIEW), str(src), "-o", str(tmp / name), "--key", key],
            capture_output=True,
            text=True,
        )
        if r.returncode != 0:
            pytest.skip(f"md2review could not render: {r.stderr}")

    handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(tmp))
    httpd = socketserver.TCPServer(("127.0.0.1", 0), handler)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    yield f"http://127.0.0.1:{httpd.server_address[1]}/index.html"
    httpd.shutdown()


def _chromium_path() -> str | None:
    """A Chromium the installed Playwright can drive.

    Playwright only looks for the exact build its version pins, so a browser
    already on the machine under a different build number is invisible to it.
    Point at one explicitly when the pinned build is missing.
    """
    for candidate in (
        Path("/opt/pw-browsers/chromium"),  # a symlink to the real binary
        *sorted(Path("/opt/pw-browsers").glob("chromium-*/chrome-linux/chrome"), reverse=True),
    ):
        if candidate.is_file():
            return str(candidate)
    for name in ("chromium", "chromium-browser", "google-chrome"):
        found = shutil.which(name)
        if found:
            return found
    return None


@pytest.fixture(scope="module")
def browser():
    with sync_playwright() as pw:
        b = None
        for kwargs in ({}, {"executable_path": _chromium_path()}):
            if "executable_path" in kwargs and not kwargs["executable_path"]:
                continue
            try:
                b = pw.chromium.launch(**kwargs)
                break
            except Exception:  # pragma: no cover - environment dependent
                continue
        if b is None:
            pytest.skip("no chromium Playwright can launch")
        yield b
        b.close()


@pytest.fixture
def page(browser, site):
    ctx = browser.new_context()
    p = ctx.new_page()
    p.goto(site)
    yield p
    ctx.close()


def test_selection_opens_the_box_and_it_stays_open(page) -> None:
    """The regression: the box used to vanish once the debounce fired."""
    page.evaluate(SELECT_JS)
    page.wait_for_function(POP_OPEN, timeout=3000)
    # Well past the 250ms debounce and any focus-induced selectionchange.
    page.wait_for_timeout(1200)
    assert page.evaluate(POP_OPEN), "note box closed itself after the selection settled"


def test_mouse_selection_opens_the_box_and_it_stays_open(page) -> None:
    """Same guarantee on the desktop path, where mouseup opens and focuses."""
    box = page.locator(".doc p").first.bounding_box()
    page.mouse.move(box["x"] + 10, box["y"] + 6)
    page.mouse.down()
    page.mouse.move(box["x"] + 180, box["y"] + 6, steps=12)
    page.mouse.up()
    page.wait_for_function(POP_OPEN, timeout=3000)
    page.wait_for_timeout(1200)
    assert page.evaluate(POP_OPEN), "note box closed itself after mouse selection"


def test_typing_survives_a_further_selection_event(page) -> None:
    """A stray selectionchange must not wipe a half-typed note."""
    page.evaluate(SELECT_JS)
    page.wait_for_function(POP_OPEN, timeout=3000)
    page.fill("#anTxt", "half typed")
    page.evaluate("() => getSelection().removeAllRanges()")
    page.wait_for_timeout(800)
    assert page.evaluate(POP_OPEN)
    assert page.input_value("#anTxt") == "half typed"


def test_enter_saves_the_comment(page) -> None:
    """Select -> type -> Enter is the advertised workflow."""
    quote = page.evaluate(SELECT_JS)
    page.wait_for_function(POP_OPEN, timeout=3000)
    page.fill("#anTxt", "this is my note")
    page.press("#anTxt", "Enter")
    page.wait_for_timeout(300)
    assert page.evaluate(POP_OPEN) is False
    assert page.locator("mark.note").count() == 1
    assert "this is my note" in page.locator("#anList").inner_text()
    assert quote.strip()[:20] in page.locator("#anList").inner_text()


def test_shift_enter_is_a_newline_not_a_save(page) -> None:
    page.evaluate(SELECT_JS)
    page.wait_for_function(POP_OPEN, timeout=3000)
    page.click("#anTxt")
    page.keyboard.type("first")
    page.keyboard.press("Shift+Enter")
    page.keyboard.type("second")
    assert page.evaluate(POP_OPEN)
    assert page.input_value("#anTxt") == "first\nsecond"
    assert page.locator("mark.note").count() == 0


def test_escape_discards(page) -> None:
    page.evaluate(SELECT_JS)
    page.wait_for_function(POP_OPEN, timeout=3000)
    page.fill("#anTxt", "never mind")
    page.press("#anTxt", "Escape")
    page.wait_for_timeout(200)
    assert page.evaluate(POP_OPEN) is False
    assert page.locator("mark.note").count() == 0


def test_save_is_the_first_button(page) -> None:
    labels = page.locator("#anPop .anrow button").all_text_contents()
    assert labels[0] == "Save", labels


def test_comment_survives_reload_and_reopens_for_edit(page) -> None:
    page.evaluate(SELECT_JS)
    page.wait_for_function(POP_OPEN, timeout=3000)
    page.fill("#anTxt", "persisted note")
    page.press("#anTxt", "Enter")
    page.wait_for_timeout(300)
    page.reload()
    page.wait_for_timeout(400)
    assert page.locator("mark.note").count() == 1
    assert "persisted note" in page.locator("#anList").inner_text()
    page.locator("mark.note").first.click()
    page.wait_for_function(POP_OPEN, timeout=3000)
    assert page.input_value("#anTxt") == "persisted note"


def test_editing_an_existing_comment_updates_it(page) -> None:
    page.evaluate(SELECT_JS)
    page.wait_for_function(POP_OPEN, timeout=3000)
    page.fill("#anTxt", "before")
    page.press("#anTxt", "Enter")
    page.wait_for_timeout(200)
    page.locator("mark.note").first.click()
    page.wait_for_function(POP_OPEN, timeout=3000)
    page.fill("#anTxt", "after")
    page.press("#anTxt", "Enter")
    page.wait_for_timeout(200)
    text = page.locator("#anList").inner_text()
    assert "after" in text and "before" not in text
    assert page.locator("mark.note").count() == 1


def test_deleting_a_comment_removes_its_highlight(page) -> None:
    page.evaluate(SELECT_JS)
    page.wait_for_function(POP_OPEN, timeout=3000)
    page.fill("#anTxt", "doomed")
    page.press("#anTxt", "Enter")
    page.wait_for_timeout(200)
    page.locator("mark.note").first.click()
    page.wait_for_function(POP_OPEN, timeout=3000)
    page.click("#anDelete")
    page.wait_for_timeout(200)
    assert page.locator("mark.note").count() == 0
    assert "No comments yet" in page.locator("#anCount").inner_text()


def test_a_half_typed_note_survives_a_forced_refresh(page) -> None:
    page.evaluate(SELECT_JS)
    page.wait_for_function(POP_OPEN, timeout=3000)
    page.fill("#anTxt", "draft in progress")
    page.dispatch_event("#anTxt", "input")
    page.wait_for_timeout(200)
    page.reload()
    page.wait_for_function(POP_OPEN, timeout=3000)
    assert page.input_value("#anTxt") == "draft in progress"


def test_copy_all_puts_markdown_on_the_clipboard(browser, site) -> None:
    ctx = browser.new_context(permissions=["clipboard-read", "clipboard-write"])
    p = ctx.new_page()
    p.goto(site)
    p.evaluate(SELECT_JS)
    p.wait_for_function(POP_OPEN, timeout=3000)
    p.fill("#anTxt", "copy me")
    p.press("#anTxt", "Enter")
    p.wait_for_timeout(200)
    p.click("#anCopy")
    p.wait_for_timeout(300)
    text = p.evaluate("() => navigator.clipboard.readText()")
    assert "copy me" in text
    assert text.startswith("# Comments")
    assert "\n  > " in text  # the quote is rendered as a Markdown blockquote
    ctx.close()


def test_comments_are_recovered_when_the_storage_key_changes(page, site) -> None:
    """A republished Artifact can come back under a different storage key.

    `renamed.html` is the same document rendered with a different --key, which
    is what a retitled republish looks like to the browser: same origin, empty
    primary key, comments still sitting under the old one.
    """
    page.evaluate(SELECT_JS)
    page.wait_for_function(POP_OPEN, timeout=3000)
    page.fill("#anTxt", "survives a republish")
    page.press("#anTxt", "Enter")
    page.wait_for_timeout(200)
    page.goto(site.replace("index.html", "renamed.html"))
    page.wait_for_timeout(600)
    assert "survives a republish" in page.locator("#anList").inner_text()
    assert page.locator("mark.note").count() == 1


def test_recovery_ignores_another_documents_comments(page, site) -> None:
    """A key whose quotes are not on this page belongs to a different doc."""
    page.evaluate(
        "() => localStorage.setItem('review-somewhere-else', JSON.stringify({"
        "  v: 2, savedAt: Date.now(),"
        "  comments: [{id: 1, where: 'x', quote: 'text that is not on this page at all', note: 'nope'}]"
        "}))"
    )
    page.reload()
    page.wait_for_timeout(600)
    assert "No comments yet" in page.locator("#anCount").inner_text()
