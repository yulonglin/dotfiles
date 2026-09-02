"""Guards md2artifact's <details>/<summary> passthrough.

Background: md2artifact parses Markdown with html disabled, which used to
escape <details> blocks into literal visible text — the tags rendered on the
page and nothing collapsed. Collapsible sections are the second deliberate
exception to html-off (alongside mermaid): only exact standalone tag lines
pass through, summary text is entity-escaped, and an unbalanced document
falls back to fully-escaped rendering so an unclosed <details> can never
swallow the rest of the page.
"""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

import pytest

MD2ARTIFACT = Path(__file__).resolve().parent.parent / "custom_bins" / "md2artifact"


def _interpreter() -> str:
    """An interpreter that can import md2artifact's markdown-it-py dependency."""
    for candidate in ("/usr/bin/python3", "python3", sys.executable):
        exe = shutil.which(candidate) if not candidate.startswith("/") else candidate
        if not exe or not Path(exe).exists():
            continue
        probe = subprocess.run([exe, "-c", "import markdown_it"], capture_output=True)
        if probe.returncode == 0:
            return exe
    pytest.skip("no interpreter with markdown-it-py available")


def _render(src_text: str, tmp: Path) -> str:
    src = tmp / "sample.md"
    src.write_text(src_text, encoding="utf-8")
    out = tmp / "sample.html"
    result = subprocess.run(
        [_interpreter(), str(MD2ARTIFACT), str(src), "-o", str(out)],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, result.stderr
    return out.read_text(encoding="utf-8")


BALANCED = """# Page

Intro.

<details><summary>The inventory (~90% confidence)</summary>

- one item with `code`

</details>

Outro.
"""


def test_balanced_details_becomes_real_element(tmp_path: Path) -> None:
    html = _render(BALANCED, tmp_path)
    assert "<details><summary>The inventory (~90% confidence)</summary>" in html
    assert "</details>" in html
    assert "&lt;details&gt;" not in html


def test_body_between_tags_still_renders_as_markdown(tmp_path: Path) -> None:
    html = _render(BALANCED, tmp_path)
    assert "<code>code</code>" in html
    assert "<li>" in html


def test_summary_markup_is_escaped(tmp_path: Path) -> None:
    src = '<details><summary>x <script>alert(1)</script></summary>\n\nbody\n\n</details>\n'
    html = _render(src, tmp_path)
    assert "<summary>x &lt;script&gt;alert(1)&lt;/script&gt;</summary>" in html
    assert "<summary>x <script>" not in html


def test_details_open_variant_passes_through(tmp_path: Path) -> None:
    src = "<details open>\n\n<summary>Shown expanded</summary>\n\nbody\n\n</details>\n"
    html = _render(src, tmp_path)
    assert "<details open>" in html
    assert "<summary>Shown expanded</summary>" in html


def test_unbalanced_details_stays_escaped(tmp_path: Path) -> None:
    src = "<details><summary>never closed</summary>\n\nbody\n"
    html = _render(src, tmp_path)
    assert "<details>" not in html
    assert "&lt;details&gt;" in html


def test_stray_close_stays_escaped(tmp_path: Path) -> None:
    src = "body\n\n</details>\n"
    html = _render(src, tmp_path)
    assert "&lt;/details&gt;" in html


def test_details_inside_code_fence_stays_escaped(tmp_path: Path) -> None:
    src = "```\n<details><summary>example</summary>\n</details>\n```\n"
    html = _render(src, tmp_path)
    assert "<details>" not in html
    assert "&lt;details&gt;" in html


def test_summary_outside_details_stays_escaped(tmp_path: Path) -> None:
    src = "<summary>orphan</summary>\n"
    html = _render(src, tmp_path)
    assert "<summary>" not in html
    assert "&lt;summary&gt;" in html


def test_attributes_are_rejected(tmp_path: Path) -> None:
    src = '<details class="x" onclick="alert(1)"><summary>t</summary>\n\nbody\n\n</details>\n'
    html = _render(src, tmp_path)
    assert "onclick" not in html or "&lt;details" in html
    assert "&lt;details" in html
