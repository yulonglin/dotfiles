"""Toggle-state checks for md2artifact, driven in a real browser.

A reviewer ticks a checklist item, refreshes, and finds the tick gone — the
state lived only in the DOM. These assert the three things that fixes:

- a task-list item renders a real control whose state is written to
  `an-states:<key>`, a key prefix-namespaced away from the comment array, and
  read back on load;
- Copy all carries the states out in a `## Checklist` section, so the state
  travels with the notes that explain it;
- `--states a,b,c` replaces the checkbox with a button cycling that set, still
  persisted and still exported, while a page with no declared set keeps the
  plain checkbox it had.

The browser fixture is imported from `test_md2artifact_browser` rather than
copied: its launch fallback (Playwright only finds the exact Chromium build it
pins) is the part that is easy to get wrong twice.
"""

from __future__ import annotations

import functools
import http.server
import socketserver
import subprocess
import sys
import threading
from pathlib import Path

import pytest

playwright_api = pytest.importorskip("playwright.sync_api")
sync_playwright = playwright_api.sync_playwright
expect = playwright_api.expect

from test_md2artifact_browser import _Server, _chromium_path, browser  # noqa: E402,F401

ROOT = Path(__file__).resolve().parent.parent
MD2REVIEW = ROOT / "custom_bins" / "md2artifact"

# "deny" is the label of the last item on purpose: it is also a member of the
# declared state set below, which is what makes the re-anchoring test below
# able to tell the two apart.
SAMPLE = """# State Sample

An opening paragraph long enough that a selection taken from the middle of it
is unambiguous.

## The checklist

- [ ] first thing
- [x] second thing
- [ ] deny

A closing paragraph that carries no control at all.
"""

PLAIN = """# Plain Sample

A document with no task list in it whatsoever, so nothing on this page should
gain a checklist section.
"""

# Three items whose ids used to collide. "ship it 1" slugifies to exactly the
# id the duplicate-name counter hands the SECOND "ship it", because that
# counter tallied only the original slug and never the suffixed ids it emitted.
COLLIDING = """# Collision Sample

An opening paragraph long enough to select from, so this page carries prose of
its own as well as its checklist.

## The checklist

- [ ] ship it
- [ ] ship it
- [ ] ship it 1
"""

STATE_SET = "approve,approve-pending-edits,deny"


@pytest.fixture(scope="module")
def site(tmp_path_factory):
    """Render the three pages and serve them; yields the directory URL."""
    tmp = tmp_path_factory.mktemp("md2artifact-states")
    (tmp / "sample.md").write_text(SAMPLE, encoding="utf-8")
    (tmp / "plain.md").write_text(PLAIN, encoding="utf-8")
    (tmp / "collide.md").write_text(COLLIDING, encoding="utf-8")
    builds = (
        ("box.html", "sample.md", "review-states-box", []),
        ("cycle.html", "sample.md", "review-states-cycle", ["--states", STATE_SET]),
        ("plain.html", "plain.md", "review-states-plain", []),
        ("collide-box.html", "collide.md", "review-states-collide-box", []),
        ("collide-cycle.html", "collide.md", "review-states-collide-cycle",
         ["--states", STATE_SET]),
    )
    for name, src, key, extra in builds:
        r = subprocess.run(
            [sys.executable, str(MD2REVIEW), str(tmp / src), "-o", str(tmp / name),
             "--key", key, *extra],
            capture_output=True,
            text=True,
        )
        assert r.returncode == 0, f"md2artifact failed: {r.stderr}"

    handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(tmp))
    httpd = _Server(("127.0.0.1", 0), handler)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    try:
        yield f"http://127.0.0.1:{httpd.server_address[1]}"
    finally:
        httpd.shutdown()
        httpd.server_close()


@pytest.fixture
def ctx(browser):
    c = browser.new_context()
    try:
        yield c
    finally:
        c.close()


def open_page(ctx, site, name: str):
    p = ctx.new_page()
    p.goto(f"{site}/{name}")
    return p


def export_text(page) -> str:
    """Copy all's output, read through the clipboard-blocked fallback box."""
    page.evaluate(
        "() => { Object.defineProperty(navigator, 'clipboard',"
        "  {value: {writeText: () => Promise.reject(new Error('blocked'))},"
        "   configurable: true});"
        "  document.execCommand = () => false; }"
    )
    page.click("#anCopy")
    page.wait_for_selector("#anExport", state="visible", timeout=3000)
    return page.input_value("#anExportText")


# --- the default page keeps a plain checkbox ------------------------------


def test_no_declared_set_renders_a_real_checkbox(ctx, site) -> None:
    page = open_page(ctx, site, "box.html")
    expect(page.locator("input.anstatebox")).to_have_count(3)
    assert page.locator(".anstatebtn").count() == 0
    # `[x]` in the source is the initial state, exactly as before.
    assert page.locator("input.anstatebox").nth(1).is_checked()
    assert not page.locator("input.anstatebox").nth(0).is_checked()


def test_a_page_with_no_task_list_exports_exactly_what_it_did(ctx, site) -> None:
    """No controls, no headings: the v1 export shape is unchanged."""
    page = open_page(ctx, site, "plain.html")
    assert page.locator("[data-an-state-id]").count() == 0
    page.evaluate(
        "() => { const n = document.querySelector('.doc p').firstChild;"
        "  const r = document.createRange(); r.setStart(n, 2); r.setEnd(n, 30);"
        "  const s = getSelection(); s.removeAllRanges(); s.addRange(r); }"
    )
    page.wait_for_function(
        "() => getComputedStyle(document.getElementById('anPop')).display === 'block'",
        timeout=3000,
    )
    page.fill("#anTxt", "a plain note")
    page.press("#anTxt", "Enter")
    text = export_text(page)
    assert "## Checklist" not in text
    assert "## Comments" not in text
    assert "a plain note" in text


# --- state survives a refresh ---------------------------------------------


def test_checkbox_state_survives_a_reload(ctx, site) -> None:
    page = open_page(ctx, site, "box.html")
    page.locator("input.anstatebox").first.check()
    page.reload()
    expect(page.locator("input.anstatebox").first).to_be_checked()
    expect(page.locator("input.anstatebox").nth(2)).not_to_be_checked()


def test_state_uses_its_own_key_and_leaves_the_comments_alone(ctx, site) -> None:
    """The comment array is a bare array every layer generation parses.

    Writing the states into it, or into a key a suffix away from it, is how
    one feature silently eats another's storage.
    """
    page = open_page(ctx, site, "box.html")
    page.locator("input.anstatebox").first.check()
    keys = page.evaluate("() => Object.keys(localStorage).sort()")
    assert "an-states:review-states-box" in keys
    assert page.evaluate("() => localStorage.getItem('review-states-box')") is None
    stored = page.evaluate("() => JSON.parse(localStorage['an-states:review-states-box'])")
    assert stored["first-thing"] == "x"


def test_a_refused_write_does_not_break_the_page(ctx, site) -> None:
    """Private windows and blocked site data throw on setItem.

    The control must still move and the page must still render; only the
    persistence is lost.
    """
    page = open_page(ctx, site, "box.html")
    errors: list[str] = []
    page.on("pageerror", lambda e: errors.append(str(e)))
    page.evaluate(
        "() => { Storage.prototype.setItem = () => { throw new Error('blocked'); }; }"
    )
    page.locator("input.anstatebox").first.check()
    expect(page.locator("input.anstatebox").first).to_be_checked()
    assert errors == [], errors


# --- state is copied out with the comments --------------------------------


def test_copy_all_carries_the_checklist(ctx, site) -> None:
    page = open_page(ctx, site, "box.html")
    page.locator("input.anstatebox").first.check()
    text = export_text(page)
    assert "## Checklist" in text
    assert "- [x] first thing" in text
    assert "- [ ] deny" in text
    # The checklist is the verdict; the notes explain it, so it comes first.
    assert text.index("## Checklist") < len(text)


def test_checklist_and_comments_are_both_labelled(ctx, site) -> None:
    page = open_page(ctx, site, "box.html")
    page.evaluate(
        "() => { const n = document.querySelector('.doc p').firstChild;"
        "  const r = document.createRange(); r.setStart(n, 4); r.setEnd(n, 40);"
        "  const s = getSelection(); s.removeAllRanges(); s.addRange(r); }"
    )
    page.wait_for_function(
        "() => getComputedStyle(document.getElementById('anPop')).display === 'block'",
        timeout=3000,
    )
    page.fill("#anTxt", "a note about the opening")
    page.press("#anTxt", "Enter")
    text = export_text(page)
    assert "## Checklist" in text
    assert "## Comments" in text
    assert "a note about the opening" in text
    assert text.index("## Checklist") < text.index("## Comments")


def test_copy_all_works_with_a_checklist_and_no_comments(ctx, site) -> None:
    """The old guard returned early on an empty comment list."""
    page = open_page(ctx, site, "box.html")
    assert "- [ ] first thing" in export_text(page)


# --- a declared state set --------------------------------------------------


def test_declared_set_cycles_on_click_and_persists(ctx, site) -> None:
    page = open_page(ctx, site, "cycle.html")
    btn = page.locator(".anstatebtn").first
    expect(btn).to_have_text("approve")
    btn.click()
    expect(btn).to_have_text("approve-pending-edits")
    btn.click()
    expect(btn).to_have_text("deny")
    btn.click()
    expect(btn).to_have_text("approve")  # wraps
    btn.click()
    page.reload()
    expect(page.locator(".anstatebtn").first).to_have_text("approve-pending-edits")


def test_declared_set_maps_the_source_markers_to_its_ends(ctx, site) -> None:
    """`[ ]` is the first state and `[x]` the last — checkbox semantics."""
    page = open_page(ctx, site, "cycle.html")
    labels = page.locator(".anstatebtn").all_text_contents()
    assert labels == ["approve", "deny", "approve"]
    assert page.locator("input.anstatebox").count() == 0


def test_declared_set_is_exported_in_the_brackets(ctx, site) -> None:
    page = open_page(ctx, site, "cycle.html")
    page.locator(".anstatebtn").first.click()
    text = export_text(page)
    assert "- [approve-pending-edits] first thing" in text
    assert "- [deny] second thing" in text


def test_a_state_outside_the_declared_set_is_refused(ctx, site) -> None:
    """A rebuild can meet a key written under a different set.

    Showing `maybe` on a three-state control would leave a button whose next
    click has nowhere to go, so the stored value is ignored instead.
    """
    page = open_page(ctx, site, "cycle.html")
    page.evaluate(
        "() => localStorage.setItem('an-states:review-states-cycle',"
        " JSON.stringify({'first-thing': 'maybe'}))"
    )
    page.reload()
    expect(page.locator(".anstatebtn").first).to_have_text("approve")


# --- accessibility ---------------------------------------------------------


def test_the_checkbox_is_named_by_its_item(ctx, site) -> None:
    page = open_page(ctx, site, "box.html")
    assert page.locator("input.anstatebox").first.get_attribute("aria-label") == "first thing"


def test_the_cycling_button_names_its_item_and_its_state(ctx, site) -> None:
    page = open_page(ctx, site, "cycle.html")
    btn = page.locator(".anstatebtn").first
    assert btn.get_attribute("aria-label") == "first thing: approve"
    btn.click()
    assert btn.get_attribute("aria-label") == "first thing: approve-pending-edits"


def test_the_cycling_button_works_from_the_keyboard(ctx, site) -> None:
    page = open_page(ctx, site, "cycle.html")
    btn = page.locator(".anstatebtn").first
    btn.focus()
    page.keyboard.press("Enter")
    expect(btn).to_have_text("approve-pending-edits")
    page.keyboard.press("Space")
    expect(btn).to_have_text("deny")


# --- the comment layer is not regressed ------------------------------------


def test_selecting_an_item_label_still_opens_the_box_and_it_stays(ctx, site) -> None:
    page = open_page(ctx, site, "cycle.html")
    page.evaluate(
        "() => { const n = document.querySelectorAll('.anstatelabel')[0].firstChild;"
        "  const r = document.createRange(); r.setStart(n, 0); r.setEnd(n, 11);"
        "  const s = getSelection(); s.removeAllRanges(); s.addRange(r); }"
    )
    page.wait_for_function(
        "() => getComputedStyle(document.getElementById('anPop')).display === 'block'",
        timeout=3000,
    )
    page.wait_for_timeout(1200)  # absence: must outlast the 250ms debounce
    assert page.evaluate(
        "() => getComputedStyle(document.getElementById('anPop')).display === 'block'"
    ), "note box closed itself on a selection inside an item label"


def test_a_quote_never_re_anchors_onto_the_state_word(ctx, site) -> None:
    """The third item's label is the word `deny`, which is also a state.

    With the button's own text left in the searched text, restoring this
    comment lands the highlight inside the control — where the next cycle
    overwrites it — instead of on the reader's own words.
    """
    page = open_page(ctx, site, "cycle.html")
    page.evaluate(
        "() => { const n = document.querySelectorAll('.anstatelabel')[2].firstChild;"
        "  const r = document.createRange(); r.setStart(n, 0); r.setEnd(n, 4);"
        "  const s = getSelection(); s.removeAllRanges(); s.addRange(r); }"
    )
    page.wait_for_function(
        "() => getComputedStyle(document.getElementById('anPop')).display === 'block'",
        timeout=3000,
    )
    page.fill("#anTxt", "why is this one denied")
    page.press("#anTxt", "Enter")
    page.reload()
    expect(page.locator("mark.note")).to_have_count(1)
    assert page.evaluate(
        "() => !!document.querySelector('mark.note').closest('.anstatelabel')"
    ), "the restored highlight is not on the item's own text"
    assert page.evaluate(
        "() => !document.querySelector('mark.note').closest('.anstatebtn')"
    ), "the restored highlight landed inside the state control"


# --- one item's state never lands on another ------------------------------
# Each control persists under an id slugified from its visible label, with a
# number appended when two labels slugify the same. The counter behind that
# suffix used to record only the ORIGINAL slug, so the second "ship it" was
# handed "ship-it-1" — which is also what the third item, labelled "ship it 1",
# slugifies to on its own. The two shared one storage slot, and ticking either
# brought the other back ticked. Reproduced in Chromium as [F, T, F] before a
# reload and [F, T, T] after it.


def _checked(page) -> list[bool]:
    return [b.is_checked() for b in page.locator("input.anstatebox").all()]


def test_ticking_one_item_does_not_tick_its_same_named_neighbour(ctx, site) -> None:
    page = open_page(ctx, site, "collide-box.html")
    assert _checked(page) == [False, False, False]
    page.locator("input.anstatebox").nth(1).check()
    assert _checked(page) == [False, True, False]
    page.reload()
    expect(page.locator("input.anstatebox").nth(1)).to_be_checked()
    assert _checked(page) == [False, True, False], (
        "a row the reader never touched came back marked complete"
    )


@pytest.mark.parametrize("idx", [0, 1, 2])
def test_each_same_named_item_round_trips_on_its_own(ctx, site, idx: int) -> None:
    """Every item in turn, because only one of the three collided each way."""
    page = open_page(ctx, site, "collide-box.html")
    page.locator("input.anstatebox").nth(idx).check()
    page.reload()
    expect(page.locator("input.anstatebox").nth(idx)).to_be_checked()
    assert _checked(page) == [i == idx for i in range(3)]


def test_each_item_holds_its_own_storage_slot(ctx, site) -> None:
    """Three controls, three keys: a short dict is a collision by itself."""
    page = open_page(ctx, site, "collide-box.html")
    for i in range(3):
        page.locator("input.anstatebox").nth(i).check()
    stored = page.evaluate(
        "() => JSON.parse(localStorage['an-states:review-states-collide-box'])"
    )
    assert len(stored) == 3, stored
    ids = page.evaluate(
        "() => [...document.querySelectorAll('[data-an-state-id]')]"
        "        .map(e => e.dataset.anStateId)"
    )
    assert len(set(ids)) == 3, ids


def test_cycling_one_item_does_not_move_its_same_named_neighbour(ctx, site) -> None:
    """The custom states ride the same ids, so they corrupt the same way."""
    page = open_page(ctx, site, "collide-cycle.html")
    assert page.locator(".anstatebtn").all_text_contents() == ["approve"] * 3
    page.locator(".anstatebtn").nth(1).click()
    expect(page.locator(".anstatebtn").nth(1)).to_have_text("approve-pending-edits")
    page.reload()
    expect(page.locator(".anstatebtn").nth(1)).to_have_text("approve-pending-edits")
    assert page.locator(".anstatebtn").all_text_contents() == [
        "approve",
        "approve-pending-edits",
        "approve",
    ]


@pytest.mark.parametrize("idx", [0, 1, 2])
def test_each_same_named_item_cycles_on_its_own(ctx, site, idx: int) -> None:
    page = open_page(ctx, site, "collide-cycle.html")
    page.locator(".anstatebtn").nth(idx).click()
    page.reload()
    expect(page.locator(".anstatebtn").nth(idx)).to_have_text("approve-pending-edits")
    assert page.locator(".anstatebtn").all_text_contents() == [
        "approve-pending-edits" if i == idx else "approve" for i in range(3)
    ]
