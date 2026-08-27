"""Guards `annotate-html` and the shared annotation layer it injects.

The layer is the single copy of md2review's select-to-comment code
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
MD2REVIEW = BINS / "md2review"

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
    assert "window.confirm(" in js  # Clear all asks first


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


def test_md2review_output_uses_the_same_layer(tmp_path: Path) -> None:
    """One copy: a md2review page passes --check and carries the v1 root."""
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
