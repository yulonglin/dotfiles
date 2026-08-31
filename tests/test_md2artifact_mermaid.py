"""Guards md2artifact's mermaid passthrough.

Background: md2artifact parses Markdown with html disabled (so a reviewed
document cannot inject script into the published page), which escaped mermaid
blocks into literal visible text — `<p>&lt;pre class=&quot;mermaid&quot;&gt;`
instead of a diagram. The Artifact viewer renders `<pre class="mermaid">`
elements natively, so both input spellings in use — a ```mermaid fence and a
raw <pre class="mermaid"> block — must survive as real, unescaped elements
while everything else stays escaped.
"""

from __future__ import annotations

import html
import re
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

MD2ARTIFACT = Path(__file__).resolve().parent.parent / "custom_bins" / "md2artifact"


def _interpreter() -> str:
    """An interpreter that can import md2artifact's markdown-it-py dependency.

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
    """Render Markdown through md2artifact and return the generated HTML."""
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

An injection attempt: a `</pre>` inside the fence used to close the element
early and turn everything after it into live markup.

```mermaid
graph TD
</pre><img src=x onerror="document.title='XSS'"><script>document.title='XSS'</script>
```

Closing paragraph.
"""


@pytest.fixture(scope="module")
def page_html(tmp_path_factory) -> str:
    return _render(SAMPLE, tmp_path_factory.mktemp("md2artifact_mermaid"))


def test_both_spellings_become_real_mermaid_elements(page_html: str) -> None:
    """One from the fence, one from the raw block — as real elements."""
    escaped = html.escape(DIAGRAM, quote=False)
    assert page_html.count('<pre class="mermaid">\n' + escaped + "\n</pre>") == 2


def test_diagram_survives_escaping_as_mermaid_reads_it(page_html: str) -> None:
    """Escaping is transparent to mermaid, which reads textContent.

    The source is entity-escaped (it must be — see the injection test below),
    but mermaid never sees the escaped form: the HTML parser decodes it first.
    So the characters mermaid labels legitimately carry — quotes, <br/>, & —
    arrive intact. Quotes are left alone (quote=False) since they are only
    special inside an attribute, and this is element text.
    """
    decoded = [
        html.unescape(m.group(1)).strip()
        for m in re.finditer(r'<pre class="mermaid">(.*?)</pre>', page_html, re.S)
    ]
    assert decoded.count(DIAGRAM) == 2


def test_a_diagram_cannot_break_out_of_its_pre(page_html: str) -> None:
    """The injection this escaping exists to stop.

    A `</pre>` inside a mermaid fence used to close the element early, so
    everything after it became live markup — confirmed executing in Chrome.
    Any Markdown you did not write yourself was therefore a script-injection
    vector into your published page.
    """
    assert "<script>document.title='XSS'</script>" not in page_html
    assert "<img src=x onerror=" not in page_html
    assert "&lt;/pre&gt;" in page_html


def test_raw_block_no_longer_renders_as_visible_text(page_html: str) -> None:
    """The original bug: the raw block came out as an escaped paragraph."""
    assert "<p>&lt;pre class=&quot;mermaid&quot;&gt;" not in page_html


def test_mermaid_example_inside_a_plain_fence_stays_escaped(page_html: str) -> None:
    """The passthrough is narrow: documentation of the syntax is not a diagram."""
    assert "&lt;pre class=&quot;mermaid&quot;&gt;\nflowchart TD\n    E --&gt; F" in page_html


def test_surrounding_markdown_is_untouched(page_html: str) -> None:
    for text in ("Intro paragraph.", "Between the diagrams.", "Closing paragraph."):
        assert f"<p>{text}</p>" in page_html
