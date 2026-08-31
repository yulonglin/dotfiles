"""Guards md2review's mermaid passthrough.

Background: md2review parses Markdown with html disabled (so a reviewed
document cannot inject script into the published page), which escaped mermaid
blocks into literal visible text — `<p>&lt;pre class=&quot;mermaid&quot;&gt;`
instead of a diagram. The Artifact viewer renders `<pre class="mermaid">`
elements natively, so both input spellings in use — a ```mermaid fence and a
raw <pre class="mermaid"> block — must survive as real, unescaped elements
while everything else stays escaped.
"""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

import pytest

MD2REVIEW = Path(__file__).resolve().parent.parent / "custom_bins" / "md2review"


def _interpreter() -> str:
    """An interpreter that can import md2review's markdown-it-py dependency.

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
    """Render Markdown through md2review and return the generated HTML."""
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


DIAGRAM = 'flowchart TD\n    A["node one"] --> B["node <br/> two"]'

SAMPLE = f"""# Mermaid Page

Intro paragraph.

```mermaid
{DIAGRAM}
```

Between the diagrams.

<pre class="mermaid">
{DIAGRAM}
</pre>

Documentation of the raw spelling, escaped on purpose:

```
<pre class="mermaid">
flowchart TD
    E --> F
</pre>
```

Closing paragraph.
"""


@pytest.fixture(scope="module")
def page_html(tmp_path_factory) -> str:
    return _render(SAMPLE, tmp_path_factory.mktemp("md2review_mermaid"))


def test_both_spellings_become_real_mermaid_elements(page_html: str) -> None:
    """One from the fence, one from the raw block — as real elements."""
    assert page_html.count('<pre class="mermaid">\n' + DIAGRAM + "\n</pre>") == 2


def test_diagram_source_is_not_entity_escaped(page_html: str) -> None:
    """Mermaid labels legitimately contain quotes and <br/>."""
    assert '&quot;node one&quot;' not in page_html
    assert 'A["node one"] --> B["node <br/> two"]' in page_html


def test_raw_block_no_longer_renders_as_visible_text(page_html: str) -> None:
    """The original bug: the raw block came out as an escaped paragraph."""
    assert "<p>&lt;pre class=&quot;mermaid&quot;&gt;" not in page_html


def test_mermaid_example_inside_a_plain_fence_stays_escaped(page_html: str) -> None:
    """The passthrough is narrow: documentation of the syntax is not a diagram."""
    assert "&lt;pre class=&quot;mermaid&quot;&gt;\nflowchart TD\n    E --&gt; F" in page_html


def test_surrounding_markdown_is_untouched(page_html: str) -> None:
    for text in ("Intro paragraph.", "Between the diagrams.", "Closing paragraph."):
        assert f"<p>{text}</p>" in page_html
