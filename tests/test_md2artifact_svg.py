"""Guards md2artifact's ```svg passthrough.

Background: md2artifact parses Markdown with html disabled, so inline SVG used
to render as literal escaped text — which is why chart pages had to be
hand-written HTML around the pipeline instead of going through it. Charts on an
artifact page are native SVG drawn from `lib/plotting/tokens.json`, so an SVG
fence is the third deliberate exception to html-off, alongside mermaid and
<details>.

It is also the only exception that emits user text UNESCAPED, so it pays for
that with a sanitising check: the body must parse as one well-formed <svg>
element carrying nothing on the denylist below. Anything rejected falls back to
an escaped code block plus a visible note — exactly what a plain fence did
before — so the property the passthrough registry exists to hold is unchanged:
a Markdown document you did not write cannot put script into your published
page.
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
        probe = subprocess.run(
            [exe, "-c", "import markdown_it"], capture_output=True, check=False
        )
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
        check=False,
    )
    assert result.returncode == 0, result.stderr
    return out.read_text(encoding="utf-8")


# A chart in the shape the house style produces: a camel-cased viewBox, a
# declared xlink prefix, a <style> block, a same-document link and an entity.
CHART = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 240 120" role="img" aria-label="Two bars">
  <title>Two bars</title>
  <style>.bar { fill: #7a9e9f; } text { font-size: 9px; }</style>
  <rect class="bar" x="10" y="40" width="60" height="70"/>
  <rect class="bar" x="90" y="20" width="60" height="90"/>
  <text x="10" y="112">a &amp; b</text>
  <a href="#results"><text x="180" y="112">jump</text></a>
</svg>"""

NOTE = "This <code>svg</code> block was not inlined because"

MIXED = f"""# Chart Page

Intro paragraph.

```svg
{CHART}
```

Documentation of the syntax, escaped on purpose:

````
```svg
<svg xmlns="http://www.w3.org/2000/svg"><circle r="4"/></svg>
```
````

```mermaid
flowchart TD
    A --> B
```

<details><summary>The workings</summary>

- one item

</details>

Closing paragraph.
"""


@pytest.fixture(scope="module")
def page_html(tmp_path_factory) -> str:
    return _render(MIXED, tmp_path_factory.mktemp("md2artifact_svg"))


def test_accepted_svg_is_emitted_byte_for_byte(page_html: str) -> None:
    """Verbatim, not re-serialised.

    Round-tripping through the parser used to judge the source would lower-case
    `viewBox`, drop the namespace prefixes and reorder attributes — each of
    which silently breaks a chart. The tree judges; it never rewrites.
    """
    assert CHART in page_html
    assert "&lt;svg xmlns=&quot;http://www.w3.org/2000/svg&quot; viewBox=" not in page_html


def test_an_accepted_chart_carries_no_rejection_note(page_html: str) -> None:
    assert NOTE not in page_html


def test_svg_example_inside_an_outer_fence_stays_escaped(page_html: str) -> None:
    """The passthrough is narrow: documentation of the syntax is not a chart."""
    assert "&lt;svg xmlns=&quot;http://www.w3.org/2000/svg&quot;&gt;&lt;circle" in page_html
    assert '<svg xmlns="http://www.w3.org/2000/svg"><circle r="4"/></svg>' not in page_html


def test_mermaid_still_passes_through(page_html: str) -> None:
    assert '<pre class="mermaid">\nflowchart TD\n    A --&gt; B\n</pre>' in page_html


def test_details_still_passes_through(page_html: str) -> None:
    assert "<details><summary>The workings</summary>" in page_html
    assert "&lt;details&gt;" not in page_html


def test_surrounding_markdown_is_untouched(page_html: str) -> None:
    for text in ("Intro paragraph.", "Closing paragraph."):
        assert f"<p>{text}</p>" in page_html


REJECTED = {
    "script": '<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>',
    "script_uppercase": '<svg xmlns="http://www.w3.org/2000/svg"><SCRIPT>alert(1)</SCRIPT></svg>',
    "foreign_object": (
        '<svg xmlns="http://www.w3.org/2000/svg"><foreignObject width="9" height="9">'
        "</foreignObject></svg>"
    ),
    "iframe": '<svg xmlns="http://www.w3.org/2000/svg"><iframe src="x"/></svg>',
    "object": '<svg xmlns="http://www.w3.org/2000/svg"><object data="x"/></svg>',
    "embed": '<svg xmlns="http://www.w3.org/2000/svg"><embed src="x"/></svg>',
    "use_external_href": (
        '<svg xmlns="http://www.w3.org/2000/svg">'
        '<use href="https://example.invalid/sprite.svg#icon"/></svg>'
    ),
    "use_external_xlink_href": (
        '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">'
        '<use xlink:href="https://example.invalid/sprite.svg#icon"/></svg>'
    ),
    "style_url": (
        '<svg xmlns="http://www.w3.org/2000/svg">'
        "<style>.bar { fill: url(https://example.invalid/p.png); }</style></svg>"
    ),
    "style_import": (
        '<svg xmlns="http://www.w3.org/2000/svg">'
        '<style>@import "https://example.invalid/p.css";</style></svg>'
    ),
    "event_handler": (
        '<svg xmlns="http://www.w3.org/2000/svg"><rect onload="alert(1)" width="9"/></svg>'
    ),
    "event_handler_uppercase": (
        '<svg xmlns="http://www.w3.org/2000/svg"><rect ONCLICK="alert(1)" width="9"/></svg>'
    ),
    "javascript_url": (
        '<svg xmlns="http://www.w3.org/2000/svg"><rect fill="url(javascript:alert(1))"/></svg>'
    ),
    # `java\nscript:` runs in a browser, so values are compared with the
    # whitespace stripped out, exactly as the browser resolves them.
    "javascript_url_split": (
        '<svg xmlns="http://www.w3.org/2000/svg"><rect fill="url(java\nscript:alert(1))"/></svg>'
    ),
    "non_image_data_url": (
        '<svg xmlns="http://www.w3.org/2000/svg"><rect fill="url(data:text/plain,hi)"/></svg>'
    ),
    "external_href": (
        '<svg xmlns="http://www.w3.org/2000/svg">'
        '<a href="https://example.invalid/"><text>go</text></a></svg>'
    ),
    "malformed": '<svg xmlns="http://www.w3.org/2000/svg"><rect width="9"></svg>',
    "two_roots": '<svg xmlns="http://www.w3.org/2000/svg"/><svg xmlns="http://www.w3.org/2000/svg"/>',
    "not_an_svg_root": '<div><svg xmlns="http://www.w3.org/2000/svg"/></div>',
    # ElementTree resolves no external entity but does expand internal ones, so
    # an internal DTD subset is a denial of service against the page's author.
    "doctype": (
        '<!DOCTYPE svg [<!ENTITY a "aaaaaaaaaa">]>'
        '<svg xmlns="http://www.w3.org/2000/svg"><text>&a;</text></svg>'
    ),
}


@pytest.mark.parametrize("case", sorted(REJECTED))
def test_rejected_svg_falls_back_to_escaped_source_plus_a_note(
    case: str, tmp_path: Path
) -> None:
    """The fallback is today's behavior — an escaped fence — never silence."""
    html = _render(f"# Page\n\n```svg\n{REJECTED[case]}\n```\n", tmp_path)
    assert NOTE in html, f"{case}: no rejection note"
    assert "<svg" not in html, f"{case}: inlined an svg element it should have refused"
    assert "&lt;svg" in html, f"{case}: source is not shown escaped"


def test_a_rejection_reason_cannot_itself_inject_markup(tmp_path: Path) -> None:
    """The note quotes the parser's complaint, so that text is escaped too."""
    html = _render('# Page\n\n```svg\n<x><script>alert(1)</script></x>\n```\n', tmp_path)
    assert NOTE in html
    assert "<script>alert(1)</script>" not in html
    assert "&lt;script&gt;" in html


def test_data_image_values_are_accepted(tmp_path: Path) -> None:
    """data:image/ is the one data: form a chart legitimately carries."""
    body = (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 8 8">'
        '<rect fill="url(data:image/png;base64,iVBORw0KGgo=)" width="8" height="8"/></svg>'
    )
    html = _render(f"# Page\n\n```svg\n{body}\n```\n", tmp_path)
    assert body in html
    assert NOTE not in html


def test_an_svg_fence_with_extra_info_words_stays_escaped(tmp_path: Path) -> None:
    """Only the exact info string `svg` passes, as with mermaid."""
    html = _render(
        '# Page\n\n```svg example\n<svg xmlns="http://www.w3.org/2000/svg"/>\n```\n', tmp_path
    )
    assert "<svg" not in html
    assert "&lt;svg" in html
    assert NOTE not in html
