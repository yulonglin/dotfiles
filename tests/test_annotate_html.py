"""Guards `annotate-html` and the shared annotation layer it injects.

The layer is the single copy of md2artifact's select-to-comment code
(`custom_bins/_annotation_layer.py`). `block_unannotated_artifact.sh` refuses
to publish an HTML Artifact that lacks it, so the CLI's --check exit codes and
its idempotence are what the hook depends on.
"""

from __future__ import annotations

import importlib.util
import re
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

BINS = Path(__file__).resolve().parent.parent / "custom_bins"
CLI = BINS / "annotate-html"
MD2REVIEW = BINS / "md2artifact"

PAGE = "<title>Smoke Page</title>\n<h1>Smoke Page</h1>\n<p>hello world</p>\n"
PAGE_WITH_BODY = "<html><head><title>T</title></head><body><p>x</p></body></html>\n"


def _layer_module():
    spec = importlib.util.spec_from_file_location(
        "_annotation_layer", BINS / "_annotation_layer.py"
    )
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(mod)
    return mod


def run(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(CLI), *args], capture_output=True, text=True
    )


@pytest.fixture
def page(tmp_path: Path) -> Path:
    p = tmp_path / "page.html"
    p.write_text(PAGE, encoding="utf-8")
    return p


def test_check_exits_2_when_absent_and_0_when_present(page: Path) -> None:
    assert run(str(page), "--check").returncode == 2
    assert run(str(page)).returncode == 0
    assert run(str(page), "--check").returncode == 0


def test_missing_file_is_a_usage_error(tmp_path: Path) -> None:
    r = run(str(tmp_path / "nope.html"))
    assert r.returncode == 1
    assert "no such file" in r.stderr


def test_help_exits_zero() -> None:
    r = run("--help")
    assert r.returncode == 0
    assert "--check" in r.stdout and "--force" in r.stdout


def test_inject_adds_marker_root_and_one_script(page: Path) -> None:
    assert run(str(page)).returncode == 0
    html = page.read_text(encoding="utf-8")
    assert "<!-- annotation-layer v1 -->" in html
    assert '<div data-annotation-layer="v1"' in html
    assert "<!-- /annotation-layer -->" in html
    assert html.count("<script>") == 1
    # The original content is untouched and precedes the layer.
    assert html.startswith(PAGE)


def test_inject_is_idempotent_unless_forced(page: Path) -> None:
    run(str(page))
    before = page.read_text(encoding="utf-8")
    r = run(str(page))
    assert r.returncode == 0 and "already present" in r.stdout
    assert page.read_text(encoding="utf-8") == before
    r = run(str(page), "--force")
    assert r.returncode == 0 and "replaced" in r.stdout
    html = page.read_text(encoding="utf-8")
    assert html.count("<!-- annotation-layer v1 -->") == 1
    assert html.count("<script>") == 1


def test_layer_goes_before_body_close_when_there_is_one(tmp_path: Path) -> None:
    p = tmp_path / "full.html"
    p.write_text(PAGE_WITH_BODY, encoding="utf-8")
    assert run(str(p)).returncode == 0
    html = p.read_text(encoding="utf-8")
    assert html.index("<!-- annotation-layer v1 -->") < html.index("</body>")


def test_older_hand_ported_marker_counts_as_present(tmp_path: Path) -> None:
    """Pages patched before this CLI existed use `<!-- annotation-layer -->`."""
    p = tmp_path / "old.html"
    p.write_text(PAGE + "<!-- annotation-layer -->\n<script>1</script>\n", encoding="utf-8")
    assert run(str(p), "--check").returncode == 0
    assert "unchanged" in run(str(p)).stdout


def test_explicit_key_lands_on_the_root(page: Path) -> None:
    run(str(page), "--key", "review-x")
    assert 'data-annotation-layer="v1" data-key="review-x"' in page.read_text()


def test_layer_js_has_the_touch_and_focus_safeguards() -> None:
    js = _layer_module().JS
    assert 'addEventListener("selectionchange"' in js
    assert 'addEventListener("mouseup"' in js
    assert "if (autofocus) txt.focus();" in js
    assert 'addEventListener("beforeunload"' in js
    assert "restoreHighlights" in js and "localStorage" in js
    # Delete all still asks first, in the page rather than through a dialog
    # the sandboxed viewer ignores -- see the two tests further down.
    assert "if (!arm(this, (dirty ?" in js


def test_no_selection_event_can_close_the_note_box() -> None:
    """The flicker: the box used to close itself from a selectionchange.

    Opening focuses the textarea, focusing collapses the document selection,
    and the debounced handler read that back as a deselect. So the selection
    handlers must contain no close call at all — only Save, Cancel/Escape and
    a click outside may close the box.
    """
    js = _layer_module().JS
    for name in ("selectionchange", "mouseup"):
        body = re.search(
            r'addEventListener\("%s", function\(.*?\n\}\);' % name, js, re.S
        )
        assert body, f"no {name} handler found"
        assert "closePop" not in body.group(0), f"{name} handler still closes the box"
        assert 'display = "none"' not in body.group(0)


def test_enter_saves_and_escape_discards() -> None:
    js = _layer_module().JS
    assert 'ev.key === "Enter" && !ev.shiftKey' in js
    assert "ev.isComposing" in js  # an IME commit is not a save
    assert 'ev.key === "Escape"' in js


def test_save_is_the_first_button_in_the_note_box() -> None:
    """DOM order is tab order, and the user reads left to right."""
    html = _layer_module().HTML
    ids = re.findall(r'id="(anSave|anCancel|anDelete)"', html)
    assert ids == ["anSave", "anCancel", "anDelete"], ids


def test_storage_stays_readable_by_older_deployed_layers() -> None:
    """Comments are a bare JSON array at the primary key.

    An older layer does `JSON.parse(localStorage.getItem(KEY)).reduce(...)`.
    Hand it an object and that throws at module scope, killing the whole
    script: no handlers, no saving, a page that looks fine and does nothing.
    Two generations of this layer can share an origin, so the primary key's
    shape is a compatibility contract.
    """
    js = _layer_module().JS
    assert "JSON.stringify(comments)" in js, "the array must be stored as-is"
    assert "savedAt" not in js and "STORE_V" not in js, "envelope reintroduced"
    assert "function saveDraft()" in js and "function restoreDraft()" in js
    assert 'addEventListener("pagehide"' in js


def test_no_download_path() -> None:
    """The layer offers no file download, deliberately.

    The Artifact viewer never grants a page download permission, so a Download
    button was inert exactly where these pages are read, while still making
    every publish warn that the page offers the viewer a file. Copy all is the
    single export, with the selectable textarea as its fallback.
    """
    mod = _layer_module()
    js, html = mod.JS, mod.HTML
    assert "tryDownload" not in js, "download path reintroduced"
    assert "createObjectURL" not in js, "blob save reintroduced"
    assert 'id="anDownload"' not in html and 'id="anExportBtn"' not in html
    # The bar is exactly two controls; per-comment edit and delete carry the rest.
    assert 'id="anCopy"' in html and 'id="anClear"' in html
    assert "openExport()" in js, "clipboard fallback lost"
    assert 'x.textContent = "delete"' in js, "per-comment delete missing"


def test_layer_keys_do_not_reach_the_host_page() -> None:
    """Typing a note must never fire a host page's single-key shortcuts.

    The comment box is a TEXTAREA, so a page guarding only INPUT lets every
    letter double as a command -- on the context-ledger page, typing "d" in a
    comment marked the selected row `drop`. The layer stops its own key events
    at its root in the BUBBLE phase: handlers inside the layer have already
    run, and document/window handlers never see the event. A capture listener
    on window would fire too early and kill the layer's own Enter and Escape.
    """
    js = _layer_module().JS
    assert 'root.addEventListener(type, function(ev){ ev.stopPropagation(); })' in js
    for kind in ("keydown", "keypress", "keyup"):
        assert f'"{kind}"' in js, f"{kind} not stopped at the layer root"
    # Bubble phase means no third argument on the registration: a capture-phase
    # stop would fire before the layer's own Enter and Escape and swallow them.
    stop_line = next(
        ln for ln in js.splitlines() if "ev.stopPropagation()" in ln and "root." in ln
    )
    assert "true" not in stop_line and "capture" not in stop_line, (
        f"the stop must stay in the bubble phase: {stop_line.strip()}"
    )


def test_no_cross_document_or_mirrored_storage() -> None:
    """Three removed mechanisms that each lost or leaked data.

    A neighbouring-key scan adopted a different document's comments whenever
    one quote appeared on both pages; an IndexedDB mirror let a save racing
    its own async recovery destroy what it was recovering; a rolling backup
    key resurrected comments the user had deliberately cleared.
    """
    js = _layer_module().JS
    for banned in ("indexedDB", "siblingComments", "quotesMatchPage", "localStorage.key("):
        assert banned not in js, f"{banned} is back"


def test_storage_keys_are_prefixed_not_suffixed() -> None:
    """`KEY + "-draft"` collides with a page genuinely titled "…-draft".

    That page's primary key and this page's draft key are then the same
    string, so Escape here deletes that page's comments outright.
    """
    js = _layer_module().JS
    assert 'var DIRTY = "an-dirty:" + KEY;' in js
    assert 'var DRAFT = "an-draft:" + KEY;' in js


def test_a_failed_write_and_a_failed_copy_are_both_surfaced() -> None:
    """Silence here means the panel counts comments that are already gone."""
    js = _layer_module().JS
    assert "unsaved = !lsSet(" in js
    assert "refused to store them" in js
    # markClean() must be reachable only once a copy has actually happened.
    assert "if (!ok) {" in js and "ok = true;" in js


def test_layer_opens_no_blocking_dialog() -> None:
    """A dialog-guarded delete is a dead button in the Artifact viewer.

    The viewer renders the page inside a sandboxed iframe, and a sandbox
    without the `allow-modals` keyword makes `window.confirm` return false
    without ever asking -- Chrome only logs "Ignored call to ...". Both
    delete controls read that refusal as "the user said no" and returned
    early, so the click did nothing at all, silently. The same code worked in
    a local tab, which is why it shipped. `window.alert` and `window.prompt`
    are ignored in the same way, so none of the three may come back.
    """
    for name in ("JS", "HTML"):
        s = getattr(_layer_module(), name)
        for banned in ("window.confirm(", "confirm(", "alert(", "prompt("):
            assert banned not in s, f"{name} calls {banned} -- a no-op in the viewer"


def test_destructive_controls_arm_before_they_destroy() -> None:
    """The in-page replacement for the dialog, on both delete controls.

    A first click arms the button and makes it say what a second click will
    destroy; `arm()` returns true only on that second click. The "not copied
    out yet" warning the dialog used to carry moves onto the armed label,
    and `render()` disarms so a rebuilt list cannot confirm a stale row.
    """
    js = _layer_module().JS
    assert "function arm(btn, label)" in js
    assert "function disarm()" in js
    assert "var ARM_MS = 4000;" in js
    assert 'btn.classList.add("anarmed");' in js
    # Escape cancels, from the button and from outside the layer.
    assert 'function escDisarm(ev){ if (ev.key === "Escape") disarm(); }' in js
    assert 'root.addEventListener("keydown", escDisarm);' in js
    assert 'document.addEventListener("keydown", escDisarm);' in js
    # Delete all: guarded, and still says the comments were never copied out.
    assert "if (!arm(this, (dirty ?" in js
    assert "Not copied out yet" in js
    # Per-comment delete: guarded too.
    assert 'if (!arm(x, "click again")) return;' in js
    # A re-render must not leave an arm standing on a row it just replaced.
    assert "function render(){" in js and js.split("function render(){", 1)[1].lstrip().startswith("//")
    assert "  disarm();\n  var list = $(\"anList\")" in js
    assert ".anarmed" in _layer_module().CSS


def test_layer_emits_no_raw_non_ascii() -> None:
    """The layer is injected into host pages whose charset it does not control.

    A page served without `charset=utf-8` is decoded as latin-1, and a raw 💬
    or “curly quote” in a JavaScript string then reaches the reader as
    mojibake. Escapes render the same under either decoding. Comments — `//`
    in JS and `/* */` in CSS — are exempt: nothing renders them, and readable
    prose is worth more there. A `—` survives a latin-1 decode as three bytes
    that contain no newline, so it cannot break out of the comment it sits in.
    """
    mod = _layer_module()
    for name in ("JS", "HTML", "CSS"):
        for lineno, line in enumerate(getattr(mod, name).splitlines(), 1):
            code = re.sub(r"/\*.*?\*/", "", line)
            code = re.sub(r"(^|\s)//.*$", "", code)
            bad = [c for c in code if ord(c) > 127]
            assert not bad, f"{name}:{lineno} has raw {bad!r}: {line.strip()}"


def test_layer_has_no_external_assets() -> None:
    block = _layer_module().layer_html()
    assert not re.search(r"https?://", block)
    assert "<link" not in block and 'src="' not in block
    assert "@import" not in block


def test_layer_css_is_theme_aware_without_host_tokens() -> None:
    css = _layer_module().CSS
    assert "prefers-color-scheme: dark" in css
    assert ':root[data-theme="dark"]' in css
    assert ':root:not([data-theme="light"])' in css
    # Every var() the layer consumes is one it defines itself.
    used = set(re.findall(r"var\((--[a-z0-9-]+)", css))
    assert used and all(v.startswith("--an-") for v in used), used


@pytest.mark.skipif(shutil.which("node") is None, reason="node not installed")
def test_layer_javascript_parses(tmp_path: Path) -> None:
    js = tmp_path / "layer.js"
    js.write_text(_layer_module().JS, encoding="utf-8")
    r = subprocess.run(["node", "--check", str(js)], capture_output=True, text=True)
    assert r.returncode == 0, r.stderr


def test_md2artifact_output_uses_the_same_layer(tmp_path: Path) -> None:
    """One copy: a md2artifact page passes --check and carries the v1 root."""
    probe = subprocess.run(
        ["/usr/bin/python3", "-c", "import markdown_it"], capture_output=True
    )
    if probe.returncode != 0:
        pytest.skip("no interpreter with markdown-it-py available")
    src = tmp_path / "s.md"
    src.write_text("# Title\n\nbody\n", encoding="utf-8")
    out = tmp_path / "s.html"
    r = subprocess.run(
        ["/usr/bin/python3", str(MD2REVIEW), str(src), "-o", str(out)],
        capture_output=True,
        text=True,
    )
    assert r.returncode == 0, r.stderr
    html = out.read_text(encoding="utf-8")
    assert '<div data-annotation-layer="v1" data-key="review-s"' in html
    assert run(str(out), "--check").returncode == 0
