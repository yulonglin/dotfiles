"""Behavioural checks for the md2artifact comment box, driven in a real browser.

The structural tests in `test_md2artifact_ios.py` assert the generated page still
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
MD2REVIEW = ROOT / "custom_bins" / "md2artifact"

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
    tmp = tmp_path_factory.mktemp("md2artifact-browser")
    src = tmp / "sample.md"
    src.write_text(SAMPLE, encoding="utf-8")
    for name, key in (("index.html", "review-sample"), ("renamed.html", "review-sample-v2")):
        r = subprocess.run(
            [sys.executable, str(MD2REVIEW), str(src), "-o", str(tmp / name), "--key", key],
            capture_output=True,
            text=True,
        )
        # A render failure is a real regression, not a reason to skip.
        assert r.returncode == 0, f"md2artifact failed: {r.stderr}"

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


# ---- the viewer's sandbox -------------------------------------------------
# Every test above drives the page top-level, which is the one condition the
# real bug could not appear in. The Artifact viewer frames the page with no
# `allow-modals`, and Playwright services dialogs automatically, so a
# confirm-guarded delete passes top-level and is a dead button where these
# pages are actually read. That gap is what shipped it; this closes it.

SANDBOX_HOST = """<!doctype html><meta charset=utf8><title>host</title>
<iframe id="f" src="index.html" sandbox="allow-scripts allow-same-origin"
        style="width:100%;height:900px;border:0"></iframe>
"""


@pytest.fixture(scope="module")
def sandboxed_site(tmp_path_factory) -> str:
    """The rendered page inside a sandboxed iframe; yields the host page URL.

    `allow-same-origin` is deliberate and matches the viewer: comments survive
    a refresh of a published artifact, so its frame has working localStorage.
    `allow-modals` is deliberately absent, which is the whole point.
    """
    tmp = tmp_path_factory.mktemp("md2review-sandboxed")
    src = tmp / "sample.md"
    src.write_text(SAMPLE, encoding="utf-8")
    r = subprocess.run(
        [sys.executable, str(MD2REVIEW), str(src),
         "-o", str(tmp / "index.html"), "--key", "review-sample"],
        capture_output=True,
        text=True,
    )
    assert r.returncode == 0, f"md2review failed: {r.stderr}"
    (tmp / "host.html").write_text(SANDBOX_HOST, encoding="utf-8")

    handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(tmp))
    httpd = _Server(("127.0.0.1", 0), handler)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    try:
        yield f"http://127.0.0.1:{httpd.server_address[1]}/host.html"
    finally:
        httpd.shutdown()
        httpd.server_close()


def test_delete_all_works_where_the_viewer_suppresses_modals(browser, sandboxed_site) -> None:
    """Delete all was dead in the viewer and perfect in a local tab.

    `window.confirm` returns false in a frame without `allow-modals` — the
    browser only logs "Ignored call to confirm()" — so both branches of the old
    handler returned early on a refusal the reader never made. The dialog
    counter below is the load-bearing assertion: it must stay empty, because a
    dialog appearing again means the guard went back to being a modal.
    """
    ctx = browser.new_context()
    try:
        page = ctx.new_page()
        dialogs: list[str] = []
        page.on("dialog", lambda d: (dialogs.append(d.type), d.accept()))
        page.goto(sandboxed_site)

        framed = page.frame_locator("#f")
        expect(framed.locator("#anCount")).to_be_visible()
        frame = page.frames[1]

        # If modals are not really suppressed here, the rest proves nothing.
        assert frame.evaluate("() => window.confirm('probe')") is False

        assert frame.evaluate(SELECT_JS)
        expect(framed.locator("#anTxt")).to_be_visible()
        framed.locator("#anTxt").fill("a note worth keeping")
        framed.locator("#anTxt").press("Enter")
        expect(framed.locator("#anCount")).to_contain_text("1 comment")

        clear = framed.locator("#anClear")
        clear.click()
        # One click arms and destroys nothing.
        expect(clear).to_have_class(re.compile(r"\banarmed\b"))
        expect(framed.locator("#anCount")).to_contain_text("1 comment")

        clear.click()
        expect(framed.locator("#anCount")).to_contain_text("No comments yet")
        assert frame.evaluate("() => localStorage.getItem('review-sample')") in (None, "[]")
        assert dialogs == [], f"a modal was used as the guard: {dialogs}"
    finally:
        ctx.close()


# --- the copied subset ----------------------------------------------------
# "Delete all" was the only pruning tool, so the second Copy all re-sent every
# comment an agent had already acted on. These cover the narrower control and,
# more importantly, the states in which it must NOT fire.

SELECT_SECOND_JS = """() => {
  const n = document.querySelectorAll('.doc p')[1].firstChild;
  const r = document.createRange();
  r.setStart(n, 2); r.setEnd(n, 30);
  const s = getSelection(); s.removeAllRanges(); s.addRange(r);
  return r.toString();
}"""


def add_comment(page, select_js: str, note: str) -> None:
    page.evaluate(select_js)
    page.wait_for_function(POP_OPEN, timeout=3000)
    page.fill("#anTxt", note)
    page.press("#anTxt", "Enter")


def copy_all(page) -> None:
    """Copy all with a clipboard that resolves, which is what stamps."""
    page.evaluate(
        "() => { Object.defineProperty(navigator, 'clipboard',"
        "  {value: {writeText: () => Promise.resolve()}, configurable: true}); }"
    )
    page.click("#anCopy")
    page.wait_for_timeout(300)


def test_delete_copied_removes_only_what_a_copy_carried_out(page) -> None:
    """The whole point: the next Copy all must send fresh feedback only."""
    add_comment(page, SELECT_JS, "already actioned")
    copy_all(page)
    add_comment(page, SELECT_SECOND_JS, "written after the copy")
    expect(page.locator("#anCount")).to_contain_text("1 of 2 not yet copied out")

    page.click("#anClearCopied")
    page.click("#anClearCopied")

    expect(page.locator(".cmt")).to_have_count(1)
    assert "written after the copy" in page.locator("#anList").inner_text()
    assert "already actioned" not in page.locator("#anList").inner_text()
    # and its highlight went with it
    expect(page.locator("mark.note")).to_have_count(1)


def test_the_first_click_on_delete_copied_destroys_nothing(page) -> None:
    add_comment(page, SELECT_JS, "keep me")
    copy_all(page)
    page.click("#anClearCopied")
    expect(page.locator("#anClearCopied")).to_contain_text("Click again")
    expect(page.locator(".cmt")).to_have_count(1)


def test_delete_copied_is_disabled_until_something_has_been_copied(page) -> None:
    """Disabled rather than hidden: a control that appears and vanishes is
    harder to aim at, and its count is where the copied total is shown."""
    add_comment(page, SELECT_JS, "never copied")
    expect(page.locator("#anClearCopied")).to_be_disabled()
    expect(page.locator("#anClearCopied")).to_contain_text("(0)")
    copy_all(page)
    expect(page.locator("#anClearCopied")).to_be_enabled()
    expect(page.locator("#anClearCopied")).to_contain_text("(1)")


def test_editing_a_copied_comment_puts_it_back_in_the_unsent_set(page) -> None:
    """The copy carried the OLD wording. If the stamp survived an edit,
    "delete copied" would destroy the only copy of the new words."""
    add_comment(page, SELECT_JS, "first wording")
    copy_all(page)
    expect(page.locator("#anCount")).to_contain_text("copied out")

    page.click("mark.note")
    page.wait_for_function(POP_OPEN, timeout=3000)
    page.fill("#anTxt", "rewritten after the copy")
    page.press("#anTxt", "Enter")

    expect(page.locator("#anCount")).to_contain_text("not yet copied out")
    expect(page.locator("#anClearCopied")).to_be_disabled()


def test_delete_all_names_the_unsent_count_on_its_armed_label(page) -> None:
    add_comment(page, SELECT_JS, "safe, already out")
    copy_all(page)
    add_comment(page, SELECT_SECOND_JS, "the only copy")
    page.click("#anClear")
    label = page.locator("#anClear").inner_text()
    assert "1 not yet copied out" in label, label
    assert "delete all 2" in label, label


def test_delete_all_says_so_when_nothing_would_be_lost(page) -> None:
    add_comment(page, SELECT_JS, "already out")
    copy_all(page)
    page.click("#anClear")
    assert "All copied out" in page.locator("#anClear").inner_text()


def test_a_missing_legacy_flag_never_marks_anything_copied(page, site) -> None:
    """An absent key is not evidence. Only an explicit "0" is.

    This is the case the migration must not treat as clean: a page nobody has
    commented on yet has no flag at all, and inferring "copied" from that is
    how the removed backup key destroyed work.
    """
    page.evaluate(
        "() => { localStorage.setItem('review-sample',"
        "  JSON.stringify([{id: 1, where: 'x', quote: 'q', note: 'legacy note'}]));"
        "  localStorage.removeItem('an-dirty:review-sample'); }"
    )
    page.goto(site)
    expect(page.locator("#anCount")).to_contain_text("not yet copied out")
    expect(page.locator("#anClearCopied")).to_be_disabled()


def test_a_clean_legacy_flag_marks_the_comments_already_there(page, site) -> None:
    """Otherwise every upgraded page nags someone who copied out yesterday."""
    page.evaluate(
        "() => { localStorage.setItem('review-sample',"
        "  JSON.stringify([{id: 1, where: 'x', quote: 'q', note: 'legacy note'}]));"
        "  localStorage.setItem('an-dirty:review-sample', '0'); }"
    )
    page.goto(site)
    expect(page.locator("#anCount")).to_contain_text("copied out")
    assert "not yet" not in page.locator("#anCount").inner_text()
    expect(page.locator("#anClearCopied")).to_be_enabled()


def test_a_dirty_legacy_flag_leaves_the_comments_unstamped(page, site) -> None:
    page.evaluate(
        "() => { localStorage.setItem('review-sample',"
        "  JSON.stringify([{id: 1, where: 'x', quote: 'q', note: 'legacy note'}]));"
        "  localStorage.setItem('an-dirty:review-sample', '1'); }"
    )
    page.goto(site)
    expect(page.locator("#anCount")).to_contain_text("not yet copied out")
    expect(page.locator("#anClearCopied")).to_be_disabled()


def test_there_is_no_bulk_delete_of_the_uncopied(page) -> None:
    """Deliberately absent. Every comment predating `copiedAt` reads as
    uncopied, so such a control would have wiped every existing page."""
    add_comment(page, SELECT_JS, "a note")
    ids = page.evaluate(
        "() => Array.from(document.querySelectorAll('[data-annotation-layer] button'))"
        "  .map(b => b.id + '|' + b.textContent).join(' ')"
    )
    assert "uncopied" not in ids.lower()
    assert "not copied" not in ids.lower()


def test_the_stored_shape_stays_a_bare_array_with_the_new_key(page) -> None:
    """Extra keys on the objects are safe; an envelope kills older layers."""
    add_comment(page, SELECT_JS, "stamped")
    copy_all(page)
    raw = page.evaluate("() => localStorage.getItem('review-sample')")
    import json as _json

    data = _json.loads(raw)
    assert isinstance(data, list), data
    assert data[0]["copiedAt"] > 0
    # the shape an older deployed layer calls .reduce() on
    assert page.evaluate("(r) => Array.isArray(JSON.parse(r))", raw)


def test_copying_only_part_of_the_export_box_marks_nothing(page) -> None:
    """A partial selection did not carry every comment out of the browser.

    Stamping them all would put comments the reader never copied into the
    set that "Delete copied" destroys -- the copy is the only evidence the
    layer has, so half a copy has to count as no copy.
    """
    add_comment(page, SELECT_JS, "first note")
    add_comment(page, SELECT_SECOND_JS, "second note")
    open_export_via_blocked_clipboard(page)
    page.wait_for_timeout(300)
    assert "not yet copied out" in page.locator("#anCount").inner_text()

    # Select a few characters instead of the whole blob, then copy.
    page.evaluate(
        "() => { const ta = document.getElementById('anExportText');"
        "  ta.setSelectionRange(0, 12);"
        "  ta.dispatchEvent(new ClipboardEvent('copy')); }"
    )
    page.wait_for_timeout(300)
    assert "not yet copied out" in page.locator("#anCount").inner_text()
    expect(page.locator("#anClearCopied")).to_be_disabled()

    # The whole blob still counts.
    page.evaluate(
        "() => { const ta = document.getElementById('anExportText');"
        "  ta.setSelectionRange(0, ta.value.length);"
        "  ta.dispatchEvent(new ClipboardEvent('copy')); }"
    )
    expect(page.locator("#anCount")).to_contain_text("copied out")
    assert "not yet" not in page.locator("#anCount").inner_text()
    expect(page.locator("#anClearCopied")).to_be_enabled()


# --- suggest-edit mode (layer v2) -----------------------------------------
# The second mode: select text, propose a replacement, export it as Markdown a
# session can apply to the source. Comment stays the default, so every test
# above doubles as the regression suite for "edit mode changed nothing".

SELECT_EDIT_JS = """() => {
  const m = document.querySelector('mark.anedit');
  const r = document.createRange();
  r.selectNodeContents(m);
  const s = getSelection(); s.removeAllRanges(); s.addRange(r);
  return r.toString();
}"""


def open_edit_box(page, select_js: str = SELECT_JS) -> str:
    """Select, switch the open box to Suggest edit; returns the selected text."""
    quote = page.evaluate(select_js)
    page.wait_for_function(POP_OPEN, timeout=3000)
    page.click("#anModeEdit")
    return quote


def add_edit(page, replacement: str, select_js: str = SELECT_JS) -> str:
    quote = open_edit_box(page, select_js)
    page.fill("#anTxt", replacement)
    page.dispatch_event("#anTxt", "input")
    page.press("#anTxt", "Enter")
    return quote


def test_edit_mode_prefills_the_textarea_with_the_selection(page) -> None:
    quote = open_edit_box(page)
    assert page.input_value("#anTxt") == quote


def test_a_saved_edit_renders_strikethrough_plus_the_replacement(page) -> None:
    add_edit(page, "REPLACEMENT WORDS")
    expect(page.locator("mark.anedit")).to_have_count(1)
    expect(page.locator(".anins")).to_have_text("REPLACEMENT WORDS")
    # visually distinct from a comment highlight, which is a different element
    assert page.locator("mark.note").count() == 0
    assert page.evaluate(POP_OPEN) is False


def test_an_edit_survives_reload_and_reopens_with_its_replacement(page) -> None:
    add_edit(page, "REPLACEMENT WORDS")
    page.reload()
    expect(page.locator("mark.anedit")).to_have_count(1)
    expect(page.locator(".anins")).to_have_text("REPLACEMENT WORDS")
    page.locator("mark.anedit").first.click()
    page.wait_for_function(POP_OPEN, timeout=3000)
    assert page.input_value("#anTxt") == "REPLACEMENT WORDS"


def test_an_empty_replacement_is_a_suggested_deletion(page) -> None:
    """Pure strikethrough, reachable only by actively clearing the prefill."""
    add_edit(page, "")
    expect(page.locator("mark.anedit")).to_have_count(1)
    expect(page.locator(".anins")).to_have_count(0)
    expect(page.locator("#anList")).to_contain_text("delete")
    # and it round-trips: reopening shows an empty box, Enter leaves it alone
    page.locator("mark.anedit").first.click()
    page.wait_for_function(POP_OPEN, timeout=3000)
    assert page.input_value("#anTxt") == ""
    page.press("#anTxt", "Enter")
    page.wait_for_timeout(300)
    expect(page.locator("mark.anedit")).to_have_count(1)
    expect(page.locator(".anins")).to_have_count(0)


def test_inserted_text_is_invisible_to_re_anchoring(page) -> None:
    """THE v2 regression: the first saved edit corrupting every later anchor.

    The replacement deliberately repeats the words of the second paragraph, so
    a re-anchoring pass that scans layer-inserted text finds the later
    comment's quote inside the insertion -- early in the page, in the wrong
    place -- instead of where the reader put it.
    """
    add_edit(page, "second paragraph living under its own heading")
    quote = page.evaluate(SELECT_SECOND_JS)
    page.wait_for_function(POP_OPEN, timeout=3000)
    page.fill("#anTxt", "a note anchored after the edit")
    page.press("#anTxt", "Enter")
    expect(page.locator("mark.note")).to_have_count(1)

    page.reload()
    expect(page.locator("mark.anedit")).to_have_count(1)
    expect(page.locator("mark.note")).to_have_count(1)
    where = page.evaluate(
        "() => { const m = document.querySelector('mark.note');"
        "  return {inserted: !!m.closest('[data-an-inserted]'), text: m.textContent}; }"
    )
    assert where["inserted"] is False, "the comment re-attached inside inserted text"
    assert where["text"].strip() == quote.strip(), where
    assert "not found on this version" not in page.locator("#anList").inner_text()


def test_an_untouched_edit_box_closes_on_a_press_outside(page) -> None:
    """The prefill is not user work.

    Keying "refuses to close" on non-emptiness would make every opened edit box
    an unclosable phantom draft, because it opens with the selection in it.
    """
    open_edit_box(page)
    page.mouse.click(5, 5)
    page.wait_for_function("() => !(%s)()" % POP_OPEN, timeout=3000)
    assert page.locator("mark.anedit").count() == 0
    assert page.evaluate("() => localStorage.getItem('review-sample')") in (None, "[]")


def test_the_prefill_alone_is_not_autosaved_as_a_draft(page) -> None:
    open_edit_box(page)
    page.wait_for_timeout(400)  # absence: past any debounce
    assert page.evaluate("() => localStorage.getItem('an-draft:review-sample')") is None


def test_a_modified_edit_box_does_autosave_and_refuses_to_close(page) -> None:
    open_edit_box(page)
    page.fill("#anTxt", "my replacement")
    page.dispatch_event("#anTxt", "input")
    page.wait_for_function(
        "() => (localStorage.getItem('an-draft:review-sample') || '')"
        ".includes('my replacement')",
        timeout=3000,
    )
    page.mouse.click(5, 5)
    page.wait_for_timeout(400)  # absence
    assert page.evaluate(POP_OPEN), "a modified edit box closed on a press outside"
    assert page.input_value("#anTxt") == "my replacement"


def test_a_fresh_selection_comes_back_in_comment_mode(page) -> None:
    """Sticky edit mode would silently change what select-type-Enter means."""
    add_edit(page, "a replacement")
    page.evaluate(SELECT_SECOND_JS)
    page.wait_for_function(POP_OPEN, timeout=3000)
    assert page.input_value("#anTxt") == ""
    assert page.get_attribute("#anModeComment", "aria-pressed") == "true"
    page.fill("#anTxt", "an ordinary comment")
    page.press("#anTxt", "Enter")
    expect(page.locator("mark.note")).to_have_count(1)


def test_a_selection_overlapping_an_edit_points_at_it(page) -> None:
    """Overlapping edits cannot be exported appliably, so the second is declined."""
    add_edit(page, "the first replacement")
    page.evaluate(SELECT_EDIT_JS)
    page.wait_for_function(POP_OPEN, timeout=3000)
    assert page.input_value("#anTxt") == "the first replacement"
    expect(page.locator("mark.anedit")).to_have_count(1)
    stored = page.evaluate("() => JSON.parse(localStorage.getItem('review-sample'))")
    assert len(stored) == 1, stored


def test_switching_mode_declines_rather_than_overwriting_typed_words(page) -> None:
    page.evaluate(SELECT_JS)
    page.wait_for_function(POP_OPEN, timeout=3000)
    page.fill("#anTxt", "words I have not saved")
    page.click("#anModeEdit")
    page.wait_for_timeout(300)
    assert page.input_value("#anTxt") == "words I have not saved"
    assert page.get_attribute("#anModeComment", "aria-pressed") == "true"


def test_edit_mode_keeps_enter_shift_enter_and_escape(page) -> None:
    open_edit_box(page)
    page.click("#anTxt")
    page.keyboard.press("Control+a")
    page.keyboard.type("one")
    page.keyboard.press("Shift+Enter")
    page.keyboard.type("two")
    assert page.input_value("#anTxt") == "one\ntwo"
    assert page.locator("mark.anedit").count() == 0
    page.keyboard.press("Escape")
    page.wait_for_function("() => !(%s)()" % POP_OPEN, timeout=3000)
    assert page.locator("mark.anedit").count() == 0
    assert page.evaluate("() => localStorage.getItem('review-sample')") in (None, "[]")


def test_typing_a_bare_letter_does_not_switch_mode(page) -> None:
    """A mode-switch keystroke must be a chord: the bare-letter collision
    inside a textarea is a documented incident."""
    page.evaluate(SELECT_JS)
    page.wait_for_function(POP_OPEN, timeout=3000)
    page.click("#anTxt")
    page.keyboard.type("edit e E")
    assert page.get_attribute("#anModeComment", "aria-pressed") == "true"
    assert page.input_value("#anTxt") == "edit e E"


def test_an_edit_is_revised_and_deleted_from_its_own_box(page) -> None:
    add_edit(page, "first replacement")
    page.locator("mark.anedit").first.click()
    page.wait_for_function(POP_OPEN, timeout=3000)
    page.fill("#anTxt", "second replacement")
    page.press("#anTxt", "Enter")
    expect(page.locator(".anins")).to_have_text("second replacement")

    page.locator("mark.anedit").first.click()
    page.wait_for_function(POP_OPEN, timeout=3000)
    # Arms first: the replacement is written text, and there is no undo.
    page.click("#anDelete")
    expect(page.locator("#anDelete")).to_have_class(re.compile(r"\banarmed\b"))
    expect(page.locator("mark.anedit")).to_have_count(1)
    page.click("#anDelete")
    expect(page.locator("mark.anedit")).to_have_count(0)
    expect(page.locator(".anins")).to_have_count(0)
    expect(page.locator("#anCount")).to_contain_text("No comments yet")


def test_the_badge_and_the_count_include_edits(page) -> None:
    add_edit(page, "a replacement")
    add_comment(page, SELECT_SECOND_JS, "a note")
    expect(page.locator("#anBadge")).to_contain_text("2")
    count = page.locator("#anCount").inner_text()
    assert "suggested edit" in count, count
    assert "not yet copied out" in count, count


def test_the_export_carries_a_suggested_edits_section(browser, site) -> None:
    ctx = browser.new_context(permissions=["clipboard-read", "clipboard-write"])
    try:
        p = ctx.new_page()
        p.goto(site)
        add_edit(p, "the proposed wording")
        add_comment(p, SELECT_SECOND_JS, "an ordinary note")
        p.click("#anCopy")
        expect(p.locator("#anCount")).to_contain_text("copied out")
        text = p.evaluate("() => navigator.clipboard.readText()")
        assert text.startswith("# Comments")
        assert "## Suggested edits" in text, text
        assert "Replace:" in text and "With:" in text, text
        assert "> the proposed wording" in text, text
        assert "1." in text
        assert "an ordinary note" in text
        # the edits come first, the unchanged comments section after
        assert text.index("## Suggested edits") < text.index("an ordinary note")
    finally:
        ctx.close()


def test_a_deletion_exports_as_a_deletion(browser, site) -> None:
    ctx = browser.new_context(permissions=["clipboard-read", "clipboard-write"])
    try:
        p = ctx.new_page()
        p.goto(site)
        add_edit(p, "")
        p.click("#anCopy")
        expect(p.locator("#anCount")).to_contain_text("copied out")
        text = p.evaluate("() => navigator.clipboard.readText()")
        assert "## Suggested edits" in text, text
        assert "delete" in text.lower(), text
    finally:
        ctx.close()


def test_v1_entries_without_a_type_still_load_as_comments(page) -> None:
    """Every page's existing comments must load unchanged on a v2 rebuild."""
    quote = page.evaluate(SELECT_JS)
    page.evaluate(
        "(q) => localStorage.setItem('review-sample', JSON.stringify(["
        "  {id: 7, where: 'Review Sample', quote: q, note: 'written under v1'}]))",
        quote,
    )
    page.reload()
    expect(page.locator("#anList")).to_contain_text("written under v1")
    expect(page.locator("mark.note")).to_have_count(1)
    expect(page.locator("mark.anedit")).to_have_count(0)
    page.locator("mark.note").first.click()
    page.wait_for_function(POP_OPEN, timeout=3000)
    assert page.input_value("#anTxt") == "written under v1"


def test_suggest_edit_works_where_the_viewer_suppresses_modals(
    browser, sandboxed_site
) -> None:
    """The whole round trip inside the viewer's own sandbox.

    Nothing in edit mode may reach for `confirm` -- it returns false without
    ever asking in a frame with no `allow-modals`, which is how three controls
    shipped dead.
    """
    ctx = browser.new_context()
    try:
        page = ctx.new_page()
        dialogs: list[str] = []
        page.on("dialog", lambda d: (dialogs.append(d.type), d.accept()))
        page.goto(sandboxed_site)

        framed = page.frame_locator("#f")
        expect(framed.locator("#anCount")).to_be_visible()
        frame = page.frames[1]
        assert frame.evaluate("() => window.confirm('probe')") is False

        assert frame.evaluate(SELECT_JS)
        expect(framed.locator("#anTxt")).to_be_visible()
        framed.locator("#anModeEdit").click()
        framed.locator("#anTxt").fill("a replacement made in the viewer")
        framed.locator("#anTxt").press("Enter")
        expect(framed.locator("mark.anedit")).to_have_count(1)
        expect(framed.locator(".anins")).to_have_text("a replacement made in the viewer")

        framed.locator("mark.anedit").first.click()
        expect(framed.locator("#anTxt")).to_have_value("a replacement made in the viewer")
        delete = framed.locator("#anDelete")
        delete.click()
        expect(framed.locator("mark.anedit")).to_have_count(1)  # armed, not gone
        delete.click()
        expect(framed.locator("mark.anedit")).to_have_count(0)
        assert dialogs == [], f"a modal was used as the guard: {dialogs}"
    finally:
        ctx.close()


def test_a_cleared_prefill_survives_a_refresh_as_a_pending_deletion(page) -> None:
    """Empty is the defined 'suggest deletion' value, so a dirty empty edit box is
    work in progress, not nothing — a refresh before Enter must bring it back."""
    open_edit_box(page)
    page.fill("#anTxt", "")
    page.dispatch_event("#anTxt", "input")
    page.wait_for_function(
        "() => { const d = JSON.parse(localStorage.getItem('an-draft:review-sample') || 'null');"
        " return !!d && d.mode === 'edit' && d.note === '' && !!d.quote; }",
        timeout=3000,
    )
    page.reload()
    page.wait_for_function(POP_OPEN, timeout=3000)
    assert page.get_attribute("#anModeEdit", "aria-pressed") == "true"
    assert page.input_value("#anTxt") == ""
    page.press("#anTxt", "Enter")
    expect(page.locator("mark.anedit")).to_have_count(1)
    assert page.evaluate("() => document.querySelectorAll('[data-an-inserted]').length") == 0 or \
        page.evaluate("() => Array.from(document.querySelectorAll('[data-an-inserted]')).every(e => e.textContent === '')")


def test_an_emptied_comment_box_keeps_no_draft(page) -> None:
    """The edit-mode exception must not leak into comment mode, where an empty
    box is nothing to keep."""
    page.evaluate(SELECT_SECOND_JS)
    page.wait_for_function(POP_OPEN, timeout=3000)
    page.fill("#anTxt", "half a thought")
    page.dispatch_event("#anTxt", "input")
    page.wait_for_function(
        "() => (localStorage.getItem('an-draft:review-sample') || '').includes('half a thought')",
        timeout=3000,
    )
    page.fill("#anTxt", "")
    page.dispatch_event("#anTxt", "input")
    page.wait_for_function(
        "() => localStorage.getItem('an-draft:review-sample') === null", timeout=3000
    )


def test_a_pending_deletion_is_not_overwritten_by_a_fresh_selection(page) -> None:
    """A dirty EMPTY edit box is work (a suggested deletion); selecting other
    text must not replace it. The old guard keyed on non-emptiness and would."""
    open_edit_box(page)
    page.fill("#anTxt", "")
    page.dispatch_event("#anTxt", "input")
    page.evaluate(SELECT_SECOND_JS)
    page.dispatch_event(".doc", "mouseup")  # the real end-of-drag path
    page.wait_for_timeout(400)  # absence: past the debounce
    assert page.get_attribute("#anModeEdit", "aria-pressed") == "true"
    assert page.input_value("#anTxt") == ""
    page.press("#anTxt", "Enter")
    expect(page.locator("mark.anedit")).to_have_count(1)


def test_an_untouched_prefilled_edit_box_yields_to_a_fresh_selection(page) -> None:
    """The prefill is not user work, so it must not block the next selection."""
    open_edit_box(page)
    assert page.input_value("#anTxt") != ""
    page.evaluate(SELECT_SECOND_JS)
    page.dispatch_event(".doc", "mouseup")  # the real end-of-drag path
    page.wait_for_function(
        "() => document.querySelector('#anModeComment').getAttribute('aria-pressed') === 'true'"
        " && document.querySelector('#anTxt').value === ''",
        timeout=3000,
    )


def test_a_new_comment_is_stored_with_its_type(page) -> None:
    page.evaluate(SELECT_SECOND_JS)
    page.wait_for_function(POP_OPEN, timeout=3000)
    page.fill("#anTxt", "typed v2 comment")
    page.press("#anTxt", "Enter")
    stored = page.evaluate("() => JSON.parse(localStorage.getItem('review-sample') || '[]')")
    assert stored and stored[-1]["type"] == "comment"
