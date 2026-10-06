"""md2artifact's review features, driven in a real browser.

Collapsible H2 sections and their persistence, links that open what hides
their target, seen marks (localStorage fallback, and the db path against a
fake `claude.use`), and the page-level comment button. The page must render
and work with no `window.claude` at all, and with a `use()` that resolves
null for everything — the platform's own top-level view.

Needs Playwright and Chromium, like test_md2artifact_browser.py; skipped only
when there is genuinely no browser on the machine.
"""

from __future__ import annotations

import functools
import http.server
import json
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

ROOT = Path(__file__).resolve().parent.parent
MD2ARTIFACT = ROOT / "custom_bins" / "md2artifact"
KEY = "review-rb"
SEEN = f"md2a-seen:{KEY}"

SAMPLE = """# Review Page

Intro paragraph, long enough that a selection from it is unambiguous.

## Alpha

Alpha paragraph text.

### Alpha detail

Detail paragraph under the third-level heading, long enough to select from.

### Minor point {lower}

Minor paragraph.

## Beta {judgement}

Beta paragraph.

## Gamma

Gamma paragraph.

```diff
--- a/app.py
+++ b/app.py
@@ -1,3 +1,3 @@
 keep this line
-remove this line
+add this line
```
"""

POP_OPEN = "() => getComputedStyle(document.getElementById('anPop')).display === 'block'"


class _Server(socketserver.ThreadingTCPServer):
    daemon_threads = True
    allow_reuse_address = True


def _build(src_text: str, out: Path) -> None:
    src = out.with_suffix(".md")
    src.write_text(src_text, encoding="utf-8")
    r = subprocess.run(
        [sys.executable, str(MD2ARTIFACT), str(src), "-o", str(out), "--key", KEY],
        capture_output=True,
        text=True,
        check=False,
    )
    assert r.returncode == 0, f"md2artifact failed: {r.stderr}"


@pytest.fixture(scope="module")
def site(tmp_path_factory):
    """Serve a directory of built pages; yields (base URL, directory)."""
    tmp = tmp_path_factory.mktemp("md2artifact-review")
    _build(SAMPLE, tmp / "index.html")
    handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(tmp))
    httpd = _Server(("127.0.0.1", 0), handler)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    try:
        yield f"http://127.0.0.1:{httpd.server_address[1]}/", tmp
    finally:
        httpd.shutdown()
        httpd.server_close()


def _chromium_path() -> str | None:
    for candidate in (
        Path("/opt/pw-browsers/chromium"),
        *sorted(Path("/opt/pw-browsers").glob("chromium-*/chrome-linux/chrome"), reverse=True),
    ):
        if candidate.is_file():
            return str(candidate)
    for name in ("chromium", "chromium-browser", "google-chrome"):
        if found := shutil.which(name):
            return found
    return None


@pytest.fixture(scope="module")
def browser():
    with sync_playwright() as pw:
        try:
            b = pw.chromium.launch()
        except Exception:  # noqa: BLE001 - any launch failure tries the fallback
            fallback = _chromium_path()
            if fallback is None:
                pytest.skip("no chromium on this machine")
            b = pw.chromium.launch(executable_path=fallback)
        try:
            yield b
        finally:
            b.close()


@pytest.fixture
def ctx(browser):
    c = browser.new_context()
    try:
        yield c
    finally:
        c.close()


def _open(ctx, url: str, init_script: str | None = None):
    page = ctx.new_page()
    errors: list[str] = []
    page.on("pageerror", lambda e: errors.append(str(e)))
    if init_script:
        page.add_init_script(init_script)
    page.goto(url)
    page.wait_for_load_state("load")
    page.errors = errors  # type: ignore[attr-defined]
    return page


def _seen_state(page, sec: str) -> str:
    return page.get_attribute(f'.sec[data-sec="{sec}"]', "data-seen")


# ── no window.claude at all ──


def test_page_works_with_no_window_claude(ctx, site):
    base, _ = site
    page = _open(ctx, base + "index.html")
    assert page.evaluate("() => typeof window.claude") == "undefined"
    expect(page.locator(".sec")).to_have_count(3)
    for sec in ("alpha", "beta", "gamma"):
        assert _seen_state(page, sec) == "new"
    expect(page.locator(".page-comment")).to_be_hidden()
    summary = page.locator(".unseen-sum")
    expect(summary).to_be_visible()
    assert summary.get_attribute("href") == "#alpha"
    assert summary.get_attribute("data-label") == "3 new \u00b7 go to the first"
    # The badge on a {judgement} heading, and the folded Lower priority tray.
    expect(page.locator("#beta .chip-call")).to_be_visible()
    tray = page.locator("#alpha--body details.lower-tray")
    assert tray.evaluate("d => d.open") is False
    expect(tray.locator("summary")).to_have_text("Lower priority (1)")
    assert page.errors == []


# ── collapse / expand ──


def test_collapse_expand_and_it_persists_across_a_reload(ctx, site):
    base, _ = site
    page = _open(ctx, base + "index.html")
    toggle = page.locator('.sec[data-sec="alpha"] > .sec-toggle')
    body = page.locator("#alpha--body")
    expect(body).to_be_visible()
    assert toggle.get_attribute("aria-expanded") == "true"
    toggle.click()
    expect(body).to_be_hidden()
    assert toggle.get_attribute("aria-expanded") == "false"
    expect(page.locator("#alpha")).to_be_visible()  # the heading stays

    page.reload()
    expect(page.locator("#alpha--body")).to_be_hidden()
    expect(page.locator("#beta--body")).to_be_visible()

    # Keyboard: the toggle is a real button.
    page.focus('.sec[data-sec="alpha"] > .sec-toggle')
    page.keyboard.press("Enter")
    expect(page.locator("#alpha--body")).to_be_visible()
    page.reload()
    expect(page.locator("#alpha--body")).to_be_visible()


def test_a_contents_link_opens_its_closed_section_and_the_tray(ctx, site):
    base, _ = site
    page = _open(ctx, base + "index.html")
    page.click('.sec[data-sec="alpha"] > .sec-toggle')
    expect(page.locator("#alpha--body")).to_be_hidden()
    page.click('.toc a[href="#alpha-detail"]')
    expect(page.locator("#alpha--body")).to_be_visible()
    expect(page.locator("#alpha-detail")).to_be_in_viewport()

    page.click('.toc a[href="#minor-point"]')
    assert page.locator("details.lower-tray").evaluate("d => d.open") is True
    expect(page.locator("#minor-point")).to_be_visible()


def test_a_hash_in_the_url_opens_a_closed_section(ctx, site):
    base, _ = site
    page = _open(ctx, base + "index.html")
    page.click('.sec[data-sec="gamma"] > .sec-toggle')
    page.goto(base + "index.html#gamma")
    page.reload()
    expect(page.locator("#gamma--body")).to_be_visible()


def test_page_works_without_storage(browser, site):
    """Storage that throws on every access must not break folding or marks."""
    base, _ = site
    c = browser.new_context()
    try:
        page = _open(
            c,
            base + "index.html",
            "Object.defineProperty(window, 'localStorage', {get() { throw new Error('denied'); }});",
        )
        page.click('.sec[data-sec="alpha"] > .sec-toggle')
        expect(page.locator("#alpha--body")).to_be_hidden()
        page.click('.sec[data-sec="alpha"] .seen-btn')
        assert _seen_state(page, "alpha") == "seen"
        assert [e for e in page.errors if "denied" not in e] == []
    finally:
        c.close()


# ── seen marks, localStorage fallback ──


def test_seen_new_then_seen_then_changed_after_an_edit(ctx, site):
    base, tmp = site
    _build(SAMPLE, tmp / "changed.html")
    page = _open(ctx, base + "changed.html")
    assert _seen_state(page, "beta") == "new"
    badge = page.locator('.sec[data-sec="beta"] .seen-badge')
    expect(badge).to_be_visible()
    assert badge.get_attribute("data-label") == "New"

    for sec in ("alpha", "beta"):
        page.click(f'.sec[data-sec="{sec}"] .seen-btn')
    assert _seen_state(page, "beta") == "seen"
    expect(badge).to_be_hidden()
    assert page.get_attribute('.sec[data-sec="beta"] .seen-btn', "aria-pressed") == "true"
    stored = json.loads(page.evaluate(f"() => localStorage.getItem('{SEEN}')"))
    assert stored["beta"] == page.get_attribute('.sec[data-sec="beta"]', "data-hash")
    summary = page.locator(".unseen-sum")
    assert summary.get_attribute("data-label") == "1 new \u00b7 go to the first"
    assert summary.get_attribute("href") == "#gamma"

    page.reload()
    assert _seen_state(page, "beta") == "seen"

    _build(SAMPLE.replace("Beta paragraph.", "Beta paragraph, now edited."), tmp / "changed.html")
    # A new query string: the test server's Last-Modified has one-second
    # resolution, so a plain reload can be answered 304 with the old page.
    page.goto(base + "changed.html?rebuilt=1")
    assert _seen_state(page, "beta") == "changed"
    assert page.get_attribute('.sec[data-sec="beta"] .seen-badge', "data-label") == "Changed"
    assert _seen_state(page, "alpha") == "seen"
    assert _seen_state(page, "gamma") == "new"
    assert summary.get_attribute("data-label") == "1 new, 1 changed \u00b7 go to the first"
    assert summary.get_attribute("href") == "#beta"

    # Clicking a seen section's control marks it unseen again.
    page.click('.sec[data-sec="alpha"] .seen-btn')
    assert _seen_state(page, "alpha") == "new"
    assert page.errors == []


def test_use_resolving_null_everywhere_falls_back_to_local(ctx, site):
    base, _ = site
    page = _open(
        ctx,
        base + "index.html",
        "window.claude = {use: () => new Promise(r => setTimeout(() => r(null), 50))};",
    )
    page.wait_for_timeout(200)  # absence: let every use() settle
    expect(page.locator(".page-comment")).to_be_hidden()
    page.click('.sec[data-sec="gamma"] .seen-btn')
    stored = json.loads(page.evaluate(f"() => localStorage.getItem('{SEEN}')"))
    assert list(stored) == ["gamma"]
    assert page.errors == []


# ── seen marks, db path ──

FAKE_DB = """
window.__log = {paths: [], sets: [], subs: 0};
(function () {
  var listeners = [], body = %(initial)s;
  var doc = {
    onSnapshot: function (next) {
      window.__log.subs++; listeners.push(next);
      setTimeout(function () { next({exists: !!body, data: function () { return body; }, metadata: {hasPendingWrites: false}}); }, 20);
      return function () {};
    },
    set: function (data) {
      window.__log.sets.push(JSON.parse(JSON.stringify(data))); body = data;
      listeners.forEach(function (l) { l({exists: true, data: function () { return body; }, metadata: {hasPendingWrites: true}}); });
      return new Promise(function (r) { setTimeout(r, 30); });
    }
  };
  var caps = {
    db: {doc: function (p) { window.__log.paths.push(p); return doc; }, collection: function () {}},
    user: {id: function () { return Promise.resolve("u-123"); }},
    comments: {openComposer: function (t) { window.__log.composer = t.element.tagName + "#" + t.element.id; return Promise.resolve({opened: true}); }}
  };
  window.claude = {use: function (name) {
    return new Promise(function (r) { setTimeout(function () { r(caps[name] || null); }, %(delay)d); });
  }};
})();
"""


def _fake(initial: str = "null", delay: int = 10) -> str:
    return FAKE_DB % {"initial": initial, "delay": delay}


def test_db_marks_use_the_readers_own_doc_and_write_once_per_click(ctx, site):
    base, _ = site
    page = _open(ctx, base + "index.html", _fake())
    page.wait_for_function("() => window.__log.subs === 1")
    page.wait_for_timeout(200)  # absence: nothing is written on load
    log = page.evaluate("() => window.__log")
    assert log["paths"] == ["seen/u-123"]
    assert log["sets"] == []

    page.click('.sec[data-sec="beta"] .seen-btn')
    page.wait_for_function("() => window.__log.sets.length === 1")
    page.wait_for_timeout(200)  # absence: the echoed snapshot writes nothing
    log = page.evaluate("() => window.__log")
    beta_hash = page.get_attribute('.sec[data-sec="beta"]', "data-hash")
    assert log["sets"] == [{"marks": {"beta": beta_hash}}]
    assert log["subs"] == 1
    assert page.evaluate(f"() => localStorage.getItem('{SEEN}')") is None
    assert _seen_state(page, "beta") == "seen"
    assert page.errors == []


def test_db_marks_are_read_from_the_existing_doc(ctx, site):
    base, _ = site
    # Learn Alpha's hash from a plain load, then serve it back from the db.
    probe = _open(ctx, base + "index.html")
    alpha = probe.get_attribute('.sec[data-sec="alpha"]', "data-hash")
    probe.close()
    page = _open(ctx, base + "index.html", _fake(json.dumps({"marks": {"alpha": alpha, "gamma": "stale"}})))
    page.wait_for_function("() => document.querySelector('.sec[data-sec=\"alpha\"]').dataset.seen === 'seen'")
    assert _seen_state(page, "gamma") == "changed"
    assert _seen_state(page, "beta") == "new"
    assert page.evaluate("() => window.__log.sets.length") == 0


def test_a_click_before_the_db_connects_is_written_once_it_does(ctx, site):
    base, _ = site
    page = _open(ctx, base + "index.html", _fake(delay=600))
    page.click('.sec[data-sec="gamma"] .seen-btn')
    assert _seen_state(page, "gamma") == "seen"
    page.wait_for_function("() => window.__log.sets.length === 1", timeout=5000)
    gamma = page.get_attribute('.sec[data-sec="gamma"]', "data-hash")
    assert page.evaluate("() => window.__log.sets") == [{"marks": {"gamma": gamma}}]
    assert _seen_state(page, "gamma") == "seen"


# ── page-level comment ──


def test_comment_button_opens_the_composer_on_the_title(ctx, site):
    base, _ = site
    page = _open(ctx, base + "index.html", _fake())
    btn = page.locator(".page-comment")
    expect(btn).to_be_visible()
    assert btn.get_attribute("aria-label") == "Comment on this page"
    btn.click()
    page.wait_for_function("() => !!window.__log.composer")
    assert page.evaluate("() => window.__log.composer") == "H1#review-page"


def test_comment_button_hides_when_the_composer_is_unavailable(ctx, site):
    base, _ = site
    script = _fake().replace(
        "return Promise.resolve({opened: true});",
        "return Promise.reject({code: 'unavailable'});",
    )
    page = _open(ctx, base + "index.html", script)
    btn = page.locator(".page-comment")
    expect(btn).to_be_visible()
    btn.click()
    expect(btn).to_be_hidden()


# ── the annotation layer still labels comments by their nearest heading ──


def test_a_comment_under_an_h3_is_labelled_with_the_h3(ctx, site):
    base, _ = site
    page = _open(ctx, base + "index.html")
    page.evaluate(
        """() => {
          const n = document.querySelector('#alpha-detail + p').firstChild;
          const r = document.createRange(); r.setStart(n, 0); r.setEnd(n, 30);
          const s = getSelection(); s.removeAllRanges(); s.addRange(r);
        }"""
    )
    page.wait_for_function(POP_OPEN, timeout=3000)
    page.fill("#anTxt", "a note")
    page.press("#anTxt", "Enter")
    page.wait_for_function(f"() => (JSON.parse(localStorage.getItem('{KEY}') || '[]')).length === 1")
    stored = json.loads(page.evaluate(f"() => localStorage.getItem('{KEY}')"))
    assert stored[0]["where"] == "Alpha detail"


def test_a_comment_across_diff_rows_comes_back_after_a_reload(ctx, site):
    """The layer re-finds a quote in the page's raw text with whitespace
    collapsed. Selection text breaks lines between block rows, so the rows
    must carry a real newline or a multi-row quote never matches again."""
    base, _ = site
    page = _open(ctx, base + "index.html")
    quote = page.evaluate(
        """() => {
          const rows = document.querySelectorAll('pre.diff .dl .dc');
          const r = document.createRange();
          r.setStart(rows[0].firstChild, 5); r.setEnd(rows[2].firstChild, 8);
          const s = getSelection(); s.removeAllRanges(); s.addRange(r);
          return s.toString();
        }"""
    )
    assert "\n" in quote
    page.wait_for_function(POP_OPEN, timeout=3000)
    page.fill("#anTxt", "a note on the diff")
    page.press("#anTxt", "Enter")
    expect(page.locator("mark.note")).not_to_have_count(0)
    page.reload()
    expect(page.locator("mark.note")).not_to_have_count(0)
