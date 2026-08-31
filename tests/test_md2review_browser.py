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
- a press outside the box saved whatever was in it, so right-clicking your own
  selection, grabbing the scrollbar, or cancelling a confirm dialog each
  committed a comment the reviewer had not finished writing.
- storage machinery that lost or leaked comments: a backup key that
  resurrected a cleared list, a neighbouring-key scan that adopted a different
  document's notes, and an "exported" state set by gestures that exported
  nothing. The tests for these assert the mechanisms stay gone.

Needs Playwright and Chromium; skipped only when there is genuinely no browser
on the machine. The page is served over HTTP because `file://` is blocked in
the Playwright plugin.

On timing: a fixed `wait_for_timeout` appears only where the assertion is that
something did NOT happen, which polling cannot express; it must outlast the
250ms debounce. Every positive assertion polls via `expect(...)`.
"""

from __future__ import annotations

import functools
import http.server
import re
import shutil
import socketserver
import subprocess
import sys
import threading
from pathlib import Path

import pytest

playwright_api = pytest.importorskip("playwright.sync_api")
sync_playwright = playwright_api.sync_playwright
expect = playwright_api.expect


class _Server(socketserver.ThreadingTCPServer):
    """Chromium speculatively preconnects.

    A single-threaded server handles one connection at a time, so an idle
    preconnect socket blocks every later request until it closes — a real,
    load-dependent way for `goto`/`reload` to hang until Playwright times out.
    """

    daemon_threads = True
    allow_reuse_address = True


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
        # A render failure is a real regression, not a reason to skip.
        assert r.returncode == 0, f"md2review failed: {r.stderr}"

    handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(tmp))
    httpd = _Server(("127.0.0.1", 0), handler)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    try:
        yield f"http://127.0.0.1:{httpd.server_address[1]}/index.html"
    finally:
        httpd.shutdown()
        httpd.server_close()


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
    """Skip only when there is genuinely no browser; never on a launch bug.

    The pinned-build miss above is routine, so the fallback is expected to be
    used. If a browser binary exists and still will not launch, that is a
    broken environment worth seeing, not fourteen green skips.
    """
    with sync_playwright() as pw:
        try:
            yield_browser = pw.chromium.launch()
        except Exception:
            fallback = _chromium_path()
            if fallback is None:
                pytest.skip("no chromium on this machine")
            yield_browser = pw.chromium.launch(executable_path=fallback)
        try:
            yield yield_browser
        finally:
            yield_browser.close()


@pytest.fixture
def page(browser, site):
    ctx = browser.new_context()
    try:
        p = ctx.new_page()
        p.goto(site)
        yield p
    finally:
        ctx.close()



def open_export_via_blocked_clipboard(page) -> None:
    """Open the export textarea the only way a reader now can.

    The "Export text" button is gone: a page-initiated download is inert in
    the Artifact viewer, so Copy all is the single export and the textarea is
    its fallback when the clipboard refuses. Forcing that refusal is therefore
    how the box opens.
    """
    page.evaluate(
        "() => { Object.defineProperty(navigator, 'clipboard',"
        "  {value: {writeText: () => Promise.reject(new Error('blocked'))},"
        "   configurable: true});"
        "  document.execCommand = () => false; }"
    )
    page.click("#anCopy")
    page.wait_for_selector("#anExport", state="visible", timeout=3000)

def test_touch_selection_opens_the_box(page) -> None:
    """The iOS path: a selection with no mouse event at all opens the box.

    This does NOT guard the flicker. The flicker only ever happened on the
    mouse path, where `autofocus` steals focus and the focus collapses the
    selection; on the touch path nothing is focused and nothing collapsed, so
    this passes against the pre-fix layer too. The test below is the flicker.
    """
    page.evaluate(SELECT_JS)
    page.wait_for_function(POP_OPEN, timeout=3000)
    page.wait_for_timeout(1200)  # absence: must outlast the 250ms debounce
    assert page.evaluate(POP_OPEN), "note box closed itself after the selection settled"


def test_mouse_selection_opens_the_box_and_it_stays_open(page) -> None:
    """THE flicker regression: open on mouseup, gone ~350ms later.

    Opening focuses the textarea, focusing collapses the document selection,
    and the pre-fix `selectionchange` handler read that collapse as a deselect
    and closed the box it had just opened.
    """
    box = page.locator(".doc p").first.bounding_box()
    page.mouse.move(box["x"] + 10, box["y"] + 6)
    page.mouse.down()
    page.mouse.move(box["x"] + 180, box["y"] + 6, steps=12)
    page.mouse.up()
    page.wait_for_function(POP_OPEN, timeout=3000)
    page.wait_for_timeout(1200)  # absence: must outlast the 250ms debounce
    assert page.evaluate(POP_OPEN), "note box closed itself after mouse selection"


def test_a_new_selection_does_not_wipe_a_half_typed_note(page) -> None:
    """Guards `if (isOpen() && hasText()) return true;` in openForSelection.

    The textarea is filled WITHOUT focusing it, because focusing short-circuits
    the `selectionchange` handler on `document.activeElement === txt` and the
    typed-note guards are then never reached — which is what made an earlier
    version of this test pass against every mutation of them.
    """
    page.evaluate(SELECT_JS)
    page.wait_for_function(POP_OPEN, timeout=3000)
    page.evaluate(
        "() => { const t = document.getElementById('anTxt');"
        "  t.value = 'half typed'; t.dispatchEvent(new Event('input')); }"
    )
    assert page.evaluate("() => document.activeElement.id") != "anTxt"
    # A completely different selection, elsewhere in the document.
    page.evaluate(
        "() => { const n = document.querySelectorAll('.doc p')[1].firstChild;"
        "  const r = document.createRange(); r.setStart(n, 2); r.setEnd(n, 30);"
        "  const s = getSelection(); s.removeAllRanges(); s.addRange(r); }"
    )
    page.wait_for_timeout(800)  # absence: past the debounce
    assert page.evaluate(POP_OPEN)
    assert page.input_value("#anTxt") == "half typed"


def test_enter_saves_the_comment(page) -> None:
    """Select -> type -> Enter is the advertised workflow."""
    quote = page.evaluate(SELECT_JS)
    page.wait_for_function(POP_OPEN, timeout=3000)
    page.fill("#anTxt", "this is my note")
    page.press("#anTxt", "Enter")
    expect(page.locator("mark.note")).to_have_count(1)
    expect(page.locator("#anList")).to_contain_text("this is my note")
    expect(page.locator("#anList")).to_contain_text(quote.strip()[:20])
    assert page.evaluate(POP_OPEN) is False


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
    page.wait_for_function("() => !(%s)()" % POP_OPEN, timeout=3000)
    assert page.locator("mark.note").count() == 0


def test_save_is_the_first_button(page) -> None:
    labels = page.locator("#anPop .anrow button").all_text_contents()
    assert labels[0] == "Save", labels


# --- nothing implicit ever writes a comment -------------------------------
# Each of these gestures used to commit or destroy an in-progress note.


def test_pressing_outside_leaves_a_typed_note_alone(page) -> None:
    page.evaluate(SELECT_JS)
    page.wait_for_function(POP_OPEN, timeout=3000)
    page.fill("#anTxt", "still thinking")
    page.mouse.click(5, 5)
    page.wait_for_timeout(400)
    assert page.evaluate(POP_OPEN), "box closed on a press outside"
    assert page.input_value("#anTxt") == "still thinking"
    assert page.locator("mark.note").count() == 0, "a press outside committed a comment"


def test_pressing_outside_closes_an_empty_box(page) -> None:
    page.evaluate(SELECT_JS)
    page.wait_for_function(POP_OPEN, timeout=3000)
    page.mouse.click(5, 5)
    page.wait_for_function("() => !(%s)()" % POP_OPEN, timeout=3000)


def test_right_clicking_the_selection_does_not_commit(page) -> None:
    """Right-clicking your own selection to copy it is an ordinary gesture."""
    page.evaluate(SELECT_JS)
    page.wait_for_function(POP_OPEN, timeout=3000)
    page.fill("#anTxt", "half typed")
    box = page.locator(".doc p").first.bounding_box()
    page.mouse.click(box["x"] + 40, box["y"] + 6, button="right")
    page.wait_for_timeout(400)
    assert page.locator("mark.note").count() == 0
    assert page.input_value("#anTxt") == "half typed"


def test_cancelling_clear_all_does_not_commit(page) -> None:
    page.evaluate(SELECT_JS)
    page.wait_for_function(POP_OPEN, timeout=3000)
    page.fill("#anTxt", "half typed")
    # One click only: Delete all now arms rather than deleting, and with
    # nothing saved yet it does not even arm.
    page.click("#anClear")
    page.wait_for_timeout(400)
    assert page.locator("mark.note").count() == 0
    assert "No comments yet" in page.locator("#anCount").inner_text()


def test_clicking_a_highlight_does_not_overwrite_a_typed_note(page) -> None:
    """It used to replace the textarea outright, losing the note."""
    page.evaluate(SELECT_JS)
    page.wait_for_function(POP_OPEN, timeout=3000)
    page.fill("#anTxt", "saved one")
    page.press("#anTxt", "Enter")
    expect(page.locator("mark.note")).to_have_count(1)
    page.evaluate(
        "() => { const n = document.querySelectorAll('.doc p')[1].firstChild;"
        "  const r = document.createRange(); r.setStart(n, 2); r.setEnd(n, 30);"
        "  const s = getSelection(); s.removeAllRanges(); s.addRange(r); }"
    )
    page.wait_for_timeout(500)
    page.fill("#anTxt", "IN PROGRESS")
    page.locator("mark.note").first.click()
    page.wait_for_timeout(400)
    assert page.input_value("#anTxt") == "IN PROGRESS"
    assert page.locator("mark.note").count() == 1


def test_rereading_a_comment_does_not_reset_the_export_state(page) -> None:
    page.evaluate(SELECT_JS)
    page.wait_for_function(POP_OPEN, timeout=3000)
    page.fill("#anTxt", "a note")
    page.press("#anTxt", "Enter")
    expect(page.locator("mark.note")).to_have_count(1)
    open_export_via_blocked_clipboard(page)
    page.evaluate(
        "() => document.getElementById('anExportText')"
        ".dispatchEvent(new ClipboardEvent('copy'))"
    )
    page.click("#anExportClose")
    expect(page.locator("#anCount")).to_contain_text("copied out")
    assert "not yet" not in page.locator("#anCount").inner_text()
    page.locator("mark.note").first.click()          # reopen to reread
    page.wait_for_function(POP_OPEN, timeout=3000)
    page.press("#anTxt", "Enter")                    # close it unchanged
    page.wait_for_timeout(300)
    assert "not yet" not in page.locator("#anCount").inner_text()


# --- persistence ----------------------------------------------------------


def test_comment_survives_reload_and_reopens_for_edit(page) -> None:
    page.evaluate(SELECT_JS)
    page.wait_for_function(POP_OPEN, timeout=3000)
    page.fill("#anTxt", "persisted note")
    page.press("#anTxt", "Enter")
    expect(page.locator("mark.note")).to_have_count(1)
    page.reload()
    expect(page.locator("mark.note")).to_have_count(1)
    expect(page.locator("#anList")).to_contain_text("persisted note")
    page.locator("mark.note").first.click()
    page.wait_for_function(POP_OPEN, timeout=3000)
    assert page.input_value("#anTxt") == "persisted note"


def test_comments_are_stored_as_a_bare_array(page) -> None:
    """The primary key's shape is a compatibility contract.

    An older deployed layer calls `.reduce()` on the parsed value; anything
    but an array throws at module scope and kills its whole script.
    """
    page.evaluate(SELECT_JS)
    page.wait_for_function(POP_OPEN, timeout=3000)
    page.fill("#anTxt", "shape check")
    page.press("#anTxt", "Enter")
    expect(page.locator("mark.note")).to_have_count(1)
    stored = page.evaluate("() => JSON.parse(localStorage.getItem('review-sample'))")
    assert isinstance(stored, list), stored
    assert stored[0]["note"] == "shape check"


def test_a_legacy_bare_array_is_still_read(page) -> None:
    """Pages published before the envelope experiment must keep their notes."""
    quote = page.evaluate(SELECT_JS)
    page.evaluate(
        "(q) => localStorage.setItem('review-sample', JSON.stringify("
        "  [{id: 7, where: 'Review Sample', quote: q, note: 'from an old page'}]))",
        quote,
    )
    page.reload()
    expect(page.locator("#anList")).to_contain_text("from an old page")
    expect(page.locator("mark.note")).to_have_count(1)


def test_editing_an_existing_comment_updates_it(page) -> None:
    page.evaluate(SELECT_JS)
    page.wait_for_function(POP_OPEN, timeout=3000)
    page.fill("#anTxt", "before")
    page.press("#anTxt", "Enter")
    expect(page.locator("mark.note")).to_have_count(1)
    page.locator("mark.note").first.click()
    page.wait_for_function(POP_OPEN, timeout=3000)
    page.fill("#anTxt", "after")
    page.press("#anTxt", "Enter")
    expect(page.locator("#anList")).to_contain_text("after")
    assert "before" not in page.locator("#anList").inner_text()
    assert page.locator("mark.note").count() == 1


def test_deleting_a_comment_removes_its_highlight(page) -> None:
    page.evaluate(SELECT_JS)
    page.wait_for_function(POP_OPEN, timeout=3000)
    page.fill("#anTxt", "doomed")
    page.press("#anTxt", "Enter")
    expect(page.locator("mark.note")).to_have_count(1)
    page.locator("mark.note").first.click()
    page.wait_for_function(POP_OPEN, timeout=3000)
    page.click("#anDelete")
    expect(page.locator("mark.note")).to_have_count(0)
    expect(page.locator("#anCount")).to_contain_text("No comments yet")


def test_clearing_all_comments_stays_cleared_after_a_reload(page) -> None:
    """A backup key used to resurrect them, flagged unexported and unremovable."""
    page.evaluate(SELECT_JS)
    page.wait_for_function(POP_OPEN, timeout=3000)
    page.fill("#anTxt", "delete me")
    page.press("#anTxt", "Enter")
    expect(page.locator("mark.note")).to_have_count(1)
    # Arm, then confirm. There is no dialog to accept: the Artifact viewer
    # sandboxes the page and ignores one, so the guard is the second click.
    page.click("#anClear")
    expect(page.locator("#anClear")).to_have_class(re.compile(r"\banarmed\b"))
    page.click("#anClear")
    expect(page.locator("#anCount")).to_contain_text("No comments yet")
    page.reload()
    expect(page.locator("#anCount")).to_contain_text("No comments yet")
    assert page.locator("mark.note").count() == 0


def test_the_draft_is_written_on_every_keystroke(page) -> None:
    """Not only on the way out: a crash or a kill fires no pagehide."""
    page.evaluate(SELECT_JS)
    page.wait_for_function(POP_OPEN, timeout=3000)
    page.fill("#anTxt", "typed but not saved")
    page.dispatch_event("#anTxt", "input")
    page.wait_for_function(
        "() => (localStorage.getItem('an-draft:review-sample') || '')"
        ".includes('typed but not saved')",
        timeout=3000,
    )


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
    try:
        p = ctx.new_page()
        p.goto(site)
        p.evaluate(SELECT_JS)
        p.wait_for_function(POP_OPEN, timeout=3000)
        p.fill("#anTxt", "copy me")
        p.press("#anTxt", "Enter")
        expect(p.locator("mark.note")).to_have_count(1)
        p.click("#anCopy")
        expect(p.locator("#anCount")).to_contain_text("copied out")
        text = p.evaluate("() => navigator.clipboard.readText()")
        assert "copy me" in text
        assert text.startswith("# Comments")
        assert "\n  > " in text  # the quote is rendered as a Markdown blockquote
    finally:
        ctx.close()


def test_a_blocked_clipboard_does_not_claim_the_comments_are_exported(page) -> None:
    """It used to say "copied N" and stand the unload guard down regardless."""
    page.evaluate(SELECT_JS)
    page.wait_for_function(POP_OPEN, timeout=3000)
    page.fill("#anTxt", "never left the browser")
    page.press("#anTxt", "Enter")
    expect(page.locator("mark.note")).to_have_count(1)
    page.evaluate(
        "() => { Object.defineProperty(navigator, 'clipboard',"
        "  {value: {writeText: () => Promise.reject(new Error('blocked'))}, configurable: true});"
        "  document.execCommand = () => false; }"
    )
    page.click("#anCopy")
    page.wait_for_timeout(500)
    assert "not yet copied out" in page.locator("#anCount").inner_text()
    assert page.evaluate("() => localStorage.getItem('an-dirty:review-sample')") == "1"


# --- storage safety -------------------------------------------------------


def test_another_documents_comments_are_never_adopted(page, site) -> None:
    """The removed neighbour scan copied one document's notes into another.

    `renamed.html` is the same text under a different --key, so every quote
    matches — the most favourable case the scan had, and it must still refuse.
    """
    page.evaluate(SELECT_JS)
    page.wait_for_function(POP_OPEN, timeout=3000)
    page.fill("#anTxt", "belongs to the other page")
    page.press("#anTxt", "Enter")
    expect(page.locator("mark.note")).to_have_count(1)
    page.goto(site.replace("index.html", "renamed.html"))
    page.wait_for_timeout(600)  # absence: give any recovery path time to run
    assert "belongs to the other page" not in page.locator("#anList").inner_text()
    expect(page.locator("#anCount")).to_contain_text("No comments yet")
    assert page.evaluate("() => localStorage.getItem('review-sample-v2')") in (None, "[]")


def test_a_neighbouring_key_is_never_adopted(page) -> None:
    """Even one seeded by hand with a quote that is on this page."""
    quote = page.evaluate(SELECT_JS)
    page.evaluate(
        "(q) => localStorage.setItem('review-somewhere-else', JSON.stringify("
        "  [{id: 1, where: 'x', quote: q, note: 'CONFIDENTIAL other document'}]))",
        quote,
    )
    page.reload()
    page.wait_for_timeout(600)  # absence: give any recovery path time to run
    assert "CONFIDENTIAL" not in page.locator("#anList").inner_text()
    expect(page.locator("#anCount")).to_contain_text("No comments yet")


def test_the_draft_key_cannot_collide_with_another_pages_comments(page) -> None:
    """`KEY + "-draft"` made Escape here delete a "…-draft" page's comments."""
    page.evaluate(
        "() => localStorage.setItem('review-sample-draft', JSON.stringify("
        "  [{id: 1, where: 'x', quote: 'y', note: 'another pages comments'}]))"
    )
    page.evaluate(SELECT_JS)
    page.wait_for_function(POP_OPEN, timeout=3000)
    page.fill("#anTxt", "typing here")
    page.dispatch_event("#anTxt", "input")
    page.press("#anTxt", "Escape")
    page.wait_for_timeout(300)
    survived = page.evaluate("() => localStorage.getItem('review-sample-draft')")
    assert survived and "another pages comments" in survived


def test_opening_the_export_box_is_not_itself_an_export(page) -> None:
    """It cleared the state on open, before anything left the browser."""
    page.evaluate(SELECT_JS)
    page.wait_for_function(POP_OPEN, timeout=3000)
    page.fill("#anTxt", "still in here")
    page.press("#anTxt", "Enter")
    expect(page.locator("mark.note")).to_have_count(1)
    open_export_via_blocked_clipboard(page)
    page.wait_for_timeout(300)
    assert "not yet copied out" in page.locator("#anCount").inner_text()
    page.evaluate(
        "() => document.getElementById('anExportText')"
        ".dispatchEvent(new ClipboardEvent('copy'))"
    )
    expect(page.locator("#anCount")).to_contain_text("copied out")
    assert "not yet" not in page.locator("#anCount").inner_text()
