"""Toggle-state checks for md2artifact, driven in a real browser.

A reviewer ticks a checklist item, refreshes, and finds the tick gone — the
state lived only in the DOM. These assert the three things that fixes:

- a task-list item renders a real control whose state is written to a key of
  its own, `an-state:<key>:<id>`, prefix-namespaced away from the comment
  array, and read back on load;
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
import json
import subprocess
import sys
import threading
from pathlib import Path

import pytest

playwright_api = pytest.importorskip("playwright.sync_api")
sync_playwright = playwright_api.sync_playwright
expect = playwright_api.expect

from test_md2artifact_browser import _Server, browser  # noqa: E402,F401

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

# A numbered checklist. The bullet-hiding rule used to be a bare `li.antask`,
# which reaches an ordered list too and deletes the step numbers the author
# wrote a numbered list to keep.
ORDERED = """# Ordered Sample

An opening paragraph, so this page carries prose as well as its numbered steps.

## The steps

1. [ ] first step
2. [ ] second step
3. [ ] third step
"""

STATE_SET = "approve,approve-pending-edits,deny"


@pytest.fixture(scope="module")
def site(tmp_path_factory):
    """Render the three pages and serve them; yields the directory URL."""
    tmp = tmp_path_factory.mktemp("md2artifact-states")
    (tmp / "sample.md").write_text(SAMPLE, encoding="utf-8")
    (tmp / "plain.md").write_text(PLAIN, encoding="utf-8")
    (tmp / "collide.md").write_text(COLLIDING, encoding="utf-8")
    (tmp / "ordered.md").write_text(ORDERED, encoding="utf-8")
    builds = (
        ("box.html", "sample.md", "review-states-box", []),
        ("cycle.html", "sample.md", "review-states-cycle", ["--states", STATE_SET]),
        ("plain.html", "plain.md", "review-states-plain", []),
        ("collide-box.html", "collide.md", "review-states-collide-box", []),
        ("collide-cycle.html", "collide.md", "review-states-collide-cycle",
         ["--states", STATE_SET]),
        ("ordered.html", "ordered.md", "review-states-ordered", []),
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

    Changed with the storage model: this used to read the tick out of a shared
    `an-states:<key>` document holding every control at once. Only that design
    could put it there. The property under test -- states live under their own
    prefix-namespaced key and never touch the comment array -- is unchanged;
    the key is now one per control.
    """
    page = open_page(ctx, site, "box.html")
    page.locator("input.anstatebox").first.check()
    keys = page.evaluate("() => Object.keys(localStorage).sort()")
    assert "an-state:review-states-box:first-thing" in keys
    assert page.evaluate("() => localStorage.getItem('review-states-box')") is None
    assert page.evaluate(
        "() => localStorage.getItem('an-state:review-states-box:first-thing')"
    ) == "x"


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
        "() => localStorage.setItem('an-state:review-states-cycle:first-thing',"
        " 'maybe')"
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
    """Three controls, three keys: two sharing one key is a collision by itself.

    Changed with the storage model: the count used to be of entries in one
    shared document. It is now of localStorage keys, which is the same property
    read off the storage model that replaced it.
    """
    page = open_page(ctx, site, "collide-box.html")
    for i in range(3):
        page.locator("input.anstatebox").nth(i).check()
    stored = page.evaluate(
        "() => Object.keys(localStorage)"
        "        .filter(k => k.indexOf('an-state:review-states-collide-box:') === 0)"
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


# --- a lost tick is reported as loudly as a lost comment --------------------
# A refused comment write sets the page's unsaved flag, which paints the badge,
# writes "this browser refused to store them" into the panel and arms the
# unload guard. The state write used to discard its result and the unload guard
# counted comments only — so on a page that is all checklist and no notes,
# which is exactly what a review queue is, a reviewer with blocked or full site
# data ticked every row, closed the tab, and was never told the verdict did not
# survive.


def _guard_armed(page) -> bool:
    """Whether the `beforeunload` handler would stop the reader leaving.

    Dispatched rather than driven through a real navigation: Chromium only
    shows the browser's own leave-confirmation for a page the user has
    interacted with, and the assertion here is about the handler's decision,
    not about Chromium's heuristic for honouring it.
    """
    return page.evaluate(
        "() => { const e = new Event('beforeunload', {cancelable: true});"
        "  window.dispatchEvent(e); return e.defaultPrevented; }"
    )


def _block_storage(page) -> None:
    page.evaluate(
        "() => { Storage.prototype.setItem = () => { throw new Error('blocked'); }; }"
    )


def test_a_refused_state_write_says_so_on_a_page_with_no_comments(ctx, site) -> None:
    page = open_page(ctx, site, "box.html")
    assert "refused" not in page.locator("#anCount").inner_text()
    _block_storage(page)
    page.locator("input.anstatebox").first.check()
    expect(page.locator("#anCount")).to_contain_text("refused")
    assert "warn" in page.locator("#anCount").get_attribute("class")
    assert "warn" in page.locator("#anBadge").get_attribute("class")


def test_a_refused_state_write_arms_the_unload_guard(ctx, site) -> None:
    page = open_page(ctx, site, "box.html")
    assert not _guard_armed(page), "a page with nothing on it stopped the reader"
    _block_storage(page)
    page.locator("input.anstatebox").first.check()
    assert _guard_armed(page), "the reviewer could close the tab on a lost verdict"


def test_a_stored_tick_does_not_arm_the_unload_guard(ctx, site) -> None:
    """The guard reports LOSS. Ticks that reached localStorage are not lost."""
    page = open_page(ctx, site, "box.html")
    page.locator("input.anstatebox").first.check()
    assert not _guard_armed(page)
    assert "refused" not in page.locator("#anCount").inner_text()


def test_a_refused_state_write_warns_on_a_page_that_also_has_comments(ctx, site) -> None:
    """One flag, two writers: a stored comment must not mask a lost tick."""
    page = open_page(ctx, site, "box.html")
    page.evaluate(
        "() => { const n = document.querySelector('.doc p').firstChild;"
        "  const r = document.createRange(); r.setStart(n, 2); r.setEnd(n, 30);"
        "  const s = getSelection(); s.removeAllRanges(); s.addRange(r); }"
    )
    page.wait_for_function(
        "() => getComputedStyle(document.getElementById('anPop')).display === 'block'",
        timeout=3000,
    )
    page.fill("#anTxt", "a note that stored fine")
    page.press("#anTxt", "Enter")
    _block_storage(page)
    page.locator("input.anstatebox").first.check()
    expect(page.locator("#anCount")).to_contain_text("refused to store")


# --- an ordered checklist keeps its numbers --------------------------------
# The rule that hides the bullet applied to every `li.antask`, so a numbered
# checklist rendered as an unnumbered one: the steps a reviewer refers to by
# number lost the numbers.


def _list_style(page, selector: str) -> list[str]:
    return page.evaluate(
        "sel => [...document.querySelectorAll(sel)]"
        "         .map(li => getComputedStyle(li).listStyleType)",
        selector,
    )


def test_an_ordered_checklist_keeps_its_numbering(ctx, site) -> None:
    page = open_page(ctx, site, "ordered.html")
    expect(page.locator("ol li.antask")).to_have_count(3)
    assert _list_style(page, "ol li.antask") == ["decimal"] * 3


def test_an_unordered_checklist_still_drops_its_bullet(ctx, site) -> None:
    """The other half: the control replaces the bullet, it does not join it."""
    page = open_page(ctx, site, "box.html")
    assert _list_style(page, "ul li.antask") == ["none"] * 3


def test_an_ordered_item_persists_like_any_other(ctx, site) -> None:
    page = open_page(ctx, site, "ordered.html")
    page.locator("input.anstatebox").nth(1).check()
    page.reload()
    expect(page.locator("input.anstatebox").nth(1)).to_be_checked()
    assert "- [x] second step" in export_text(page)


# --- a second tab never discards this tab's unstored ticks -------------------
# The layer used to write every control's state as ONE SHARED DOCUMENT, on the
# grounds that removing a key is the only way to say "no longer ticked" and a
# merge-style write cannot say it. It can: an untick is stored as an explicit
# " ". Under one key per control there is no document to replace, no read a
# write is derived from, and two tabs touching different controls write
# different keys. These assert what is left: whose value wins, and that a loss
# is still reported.

STATE_PREFIX = "an-state:review-states-box:"
LEGACY_STATES_KEY = "an-states:review-states-box"


def _stored_states(page) -> dict:
    """Every stored control state for this page, gathered off its own keys."""
    return page.evaluate(
        "p => Object.fromEntries(Object.keys(localStorage)"
        "       .filter(k => k.indexOf(p) === 0)"
        "       .map(k => [k.slice(p.length), localStorage.getItem(k)]))",
        STATE_PREFIX,
    )


def _refuse_the_first_state_write(page) -> None:
    """One transient refusal, the shape a full quota has: it throws, then stops.

    A permanent block (`_block_storage`) cannot show this defect, because the
    write that clears the flag has to be allowed to succeed.
    """
    page.evaluate(
        "p => { const real = Storage.prototype.setItem; let refused = false;"
        "  Storage.prototype.setItem = function(k, v){"
        "    if (!refused && String(k).indexOf(p) === 0) {"
        "      refused = true; throw new Error('blocked'); }"
        "    return real.call(this, k, v); }; }",
        STATE_PREFIX,
    )


def test_a_refused_tick_keeps_warning_while_its_neighbours_store(ctx, site) -> None:
    """A refused write for one control cannot reach any other control.

    A's write of item 1 is refused and warns. B stores a tick of item 3. A then
    unticks item 2, which stores. Item 1 is still not in the store, so its
    warning and its unload guard both stand, and neither of the other two
    controls is touched by any of it.

    Changed with the storage model, and this is the one behaviour the change
    takes away: the shared-document write used to carry every pending control
    with it, so A's untick of item 2 opportunistically re-wrote item 1 and
    cleared its warning. That free retry was a property of replacing the whole
    document, and replacing the whole document is what silently dropped other
    tabs' work. A per-control write is honest instead -- the tick that was
    refused stays refused, and the reader is still being told so -- and adding
    a retry back would re-couple controls that now cannot affect each other.
    """
    a = open_page(ctx, site, "box.html")
    b = open_page(ctx, site, "box.html")

    _refuse_the_first_state_write(a)
    a.locator("input.anstatebox").nth(0).check()
    expect(a.locator("#anCount")).to_contain_text("refused")
    assert _guard_armed(a), "a refused tick left the tab free to close"

    b.locator("input.anstatebox").nth(2).check()
    # Polls A's own DOM, so it waits for A's storage listener to have run
    # rather than for the shared store to have changed.
    expect(a.locator("input.anstatebox").nth(2)).to_be_checked()

    a.locator("input.anstatebox").nth(1).uncheck()

    stored = _stored_states(a)
    assert stored.get("second-thing") == " ", "this tab's untick was lost"
    assert stored.get("deny") == "x", "the other tab's tick was overwritten"
    assert stored.get("first-thing") is None, "the refused write is not retried"
    expect(a.locator("#anCount")).to_contain_text("refused")
    assert _guard_armed(a), "the guard stood down over a tick that never stored"
    # On screen the refused tick still shows where the reader put it, which is
    # what the warning is about: it is here and it is nowhere else.
    expect(a.locator("input.anstatebox").nth(0)).to_be_checked()


def test_a_remote_write_never_clears_a_loss_flag_it_did_not_carry(ctx, site) -> None:
    """The other tab stored ITS tick, not this tab's. The warning stands."""
    a = open_page(ctx, site, "box.html")
    b = open_page(ctx, site, "box.html")

    _block_storage(a)
    a.locator("input.anstatebox").nth(0).check()
    assert _guard_armed(a)

    b.locator("input.anstatebox").nth(2).check()
    expect(a.locator("input.anstatebox").nth(2)).to_be_checked()

    assert _stored_states(a).get("first-thing") is None
    expect(a.locator("input.anstatebox").nth(0)).to_be_checked()
    expect(a.locator("#anCount")).to_contain_text("refused")
    assert _guard_armed(a), "a remote write stood the guard down over lost work"


def test_a_remote_clear_unticks_what_it_removed(ctx, site) -> None:
    """An id the incoming map omits must stop being shown as ticked.

    The listener only ever applied ids the incoming map named, so a state the
    other tab removed went on being displayed here as current — the display
    disagreeing with the store, which is how the lost tick above stayed
    invisible until a reload.
    """
    a = open_page(ctx, site, "box.html")
    b = open_page(ctx, site, "box.html")

    b.locator("input.anstatebox").nth(2).check()
    expect(a.locator("input.anstatebox").nth(2)).to_be_checked()

    b.evaluate("p => localStorage.removeItem(p + 'deny')", STATE_PREFIX)
    expect(a.locator("input.anstatebox").nth(2)).not_to_be_checked()
    # The page ships item 2 ticked. Falling back means the value the document
    # carries, not a blanket untick.
    expect(a.locator("input.anstatebox").nth(1)).to_be_checked()


def test_a_write_merges_onto_a_store_this_tab_has_not_seen(ctx, site) -> None:
    """The window between another tab's write and this tab's storage event.

    A write from this same document fires no storage event here, so it leaves
    the page in exactly the state that window leaves it in: the store has moved
    and the listener has not run. A write computed from the map read at load
    silently overwrites what landed in between.
    """
    page = open_page(ctx, site, "box.html")
    page.evaluate("p => localStorage.setItem(p + 'deny', 'x')", STATE_PREFIX)
    page.locator("input.anstatebox").nth(0).check()

    stored = _stored_states(page)
    assert stored.get("deny") == "x", "a stored tick this tab had not seen was overwritten"
    assert stored.get("first-thing") == "x"


def test_a_write_that_silently_stores_nothing_still_warns(ctx, site) -> None:
    """`setItem` returning without storing is a refusal too.

    The flag used to come from whether `setItem` threw. It has to come from
    what the store holds afterwards, or a browser that no-ops the write clears
    the warning on work that never left the page.
    """
    page = open_page(ctx, site, "box.html")
    page.evaluate("() => { Storage.prototype.setItem = function(){}; }")
    page.locator("input.anstatebox").nth(0).check()

    expect(page.locator("#anCount")).to_contain_text("refused")
    assert _guard_armed(page), "a write that stored nothing let the tab close quietly"


# --- two tabs are not one thread -------------------------------------------
# The enumeration the previous round wrote argued every concurrent state
# unreachable because "localStorage is synchronous and the page is
# single-threaded, so read -> merge -> write -> read-back is one indivisible
# step". That is true WITHIN a tab and says nothing across tabs: being
# single-threaded stops this tab's own handlers interleaving, it does not
# serialise a second tab, which is a separate process writing the same origin's
# store. Between tab A's read and tab A's write, tab B can store anything it
# likes, and a whole-document write from A then lands on a map that never
# contained it.


def _freeze_the_next_state_read(page) -> None:
    """Pin what the next state read sees, then let reads go live again.

    Playwright cannot suspend a tab in the middle of a task, so the schedule is
    produced from the value side instead: a read that returns the store as it
    was a moment ago is indistinguishable, to the code under test, from a read
    that happened a moment ago. One shot, so the write and the read-back that
    follow it see the real store.
    """
    page.evaluate(
        "() => { const realGet = Storage.prototype.getItem;"
        "  const realSet = Storage.prototype.setItem, snap = {};"
        "  for (let i = 0; i < localStorage.length; i++) { const k = localStorage.key(i);"
        "    if (k.indexOf('an-state') === 0) snap[k] = realGet.call(localStorage, k); }"
        "  Storage.prototype.getItem = function(k){"
        "    if (String(k).indexOf('an-state') === 0)"
        "      return snap.hasOwnProperty(k) ? snap[k] : null;"
        "    return realGet.call(this, k); };"
        "  Storage.prototype.setItem = function(k, v){"
        "    if (String(k).indexOf('an-state') === 0) {"
        "      Storage.prototype.getItem = realGet; Storage.prototype.setItem = realSet; }"
        "    return realSet.call(this, k, v); }; }"
    )


def test_a_tick_from_another_tab_survives_this_tabs_next_tick(ctx, site) -> None:
    """The confirmed defect: two tabs, two DIFFERENT items, one survivor.

    Tab A reads the stored state, tab B ticks item 3 and stores it, tab A then
    finishes ticking item 1. Under a shared document A's write replaces the
    whole map, so B's tick is gone and both tabs' unsaved guards are false:
    nothing anywhere says the verdict was dropped. Under one key per item the
    two tabs write two different keys and cannot collide at all.
    """
    a = open_page(ctx, site, "box.html")
    b = open_page(ctx, site, "box.html")

    _freeze_the_next_state_read(a)
    b.locator("input.anstatebox").nth(2).check()
    a.locator("input.anstatebox").nth(0).check()

    stored = _stored_states(a)
    assert stored.get("deny") == "x", "the other tab's tick was silently overwritten"
    assert stored.get("first-thing") == "x", "this tab's own tick did not land"
    assert not _guard_armed(a), "this tab's tick did land, so nothing is lost here"
    assert not _guard_armed(b), "the other tab was never told its tick went away"


def test_two_tabs_ticking_different_items_both_survive(ctx, site) -> None:
    """The same thing with no instrumentation at all, and a reload to prove it."""
    a = open_page(ctx, site, "box.html")
    b = open_page(ctx, site, "box.html")

    a.locator("input.anstatebox").nth(0).check()
    b.locator("input.anstatebox").nth(2).check()
    expect(a.locator("input.anstatebox").nth(2)).to_be_checked()

    a.reload()
    assert _checked(a) == [True, True, True]


def test_the_same_item_in_two_tabs_resolves_last_writer_wins(ctx, site) -> None:
    """Two tabs disagreeing about ONE value: the last one to speak decides.

    This is correct, not a defect to file. They are not two edits to merge --
    they are two opinions about a single cell, and there is no third thing to
    do with them. Nothing is silently lost here: the losing tab repaints to the
    winning value the moment the storage event lands, so both tabs agree with
    the store and with each other.
    """
    a = open_page(ctx, site, "box.html")
    b = open_page(ctx, site, "box.html")

    a.locator("input.anstatebox").nth(0).check()
    expect(b.locator("input.anstatebox").nth(0)).to_be_checked()
    b.locator("input.anstatebox").nth(0).uncheck()

    expect(a.locator("input.anstatebox").nth(0)).not_to_be_checked()
    assert _stored_states(a).get("first-thing") == " "


# --- state written by the shared-document layer is picked up -----------------
# Readers have ticks stored under the old `an-states:<key>` document. It is read
# once, written out one key per control, and LEFT WHERE IT IS: a page rolled
# back to the previous layer still finds every tick its reader made.


def _seed_legacy_document(ctx, site, doc: dict):
    """Write the old shared document before the page that reads it is opened."""
    page = open_page(ctx, site, "plain.html")  # same origin, no controls of its own
    page.evaluate(
        "a => localStorage.setItem(a[0], a[1])",
        [LEGACY_STATES_KEY, json.dumps(doc)],
    )
    return page


def test_a_shared_document_from_the_old_layer_is_picked_up(ctx, site) -> None:
    """Including the untick, which the old layer said by omitting the key."""
    page = _seed_legacy_document(ctx, site, {"first-thing": "x", "second-thing": " "})
    page.goto(f"{site}/box.html")

    assert _checked(page) == [True, False, False]
    assert _stored_states(page) == {"first-thing": "x", "second-thing": " "}


def test_the_old_shared_document_is_left_in_place(ctx, site) -> None:
    """A page rolled back to the previous layer must still find the ticks."""
    page = _seed_legacy_document(ctx, site, {"first-thing": "x"})
    page.goto(f"{site}/box.html")
    page.locator("input.anstatebox").nth(2).check()

    assert page.evaluate("k => localStorage.getItem(k)", LEGACY_STATES_KEY) is not None


def test_migration_never_resurrects_a_state_the_reader_cleared(ctx, site) -> None:
    """It runs once. Otherwise every load undoes what the reader did last time.

    The reader unticks an item the old document had ticked, which stores an
    explicit " " -- and then clears that key outright, which is what a second
    tab's `localStorage.clear()` does. Neither may come back ticked.
    """
    page = _seed_legacy_document(ctx, site, {"first-thing": "x", "deny": "x"})
    page.goto(f"{site}/box.html")
    # Item 2 is ticked in the source and the old document names it nowhere, so
    # it falls back to the value the page shipped with.
    assert _checked(page) == [True, True, True]

    page.locator("input.anstatebox").nth(0).uncheck()
    page.evaluate("p => localStorage.removeItem(p + 'deny')", STATE_PREFIX)
    page.reload()

    assert _checked(page) == [False, True, False], (
        "the legacy document was read a second time and undid the reader"
    )
