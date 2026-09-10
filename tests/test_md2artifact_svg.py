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
    # A url() that can fetch is refused wherever it appears — the <style>
    # element, a style= attribute and any other attribute value alike.
    "style_element_external_url": (
        '<svg xmlns="http://www.w3.org/2000/svg">'
        "<style>.bar { fill: url(https://example.invalid/p.png); }</style></svg>"
    ),
    "style_attribute_external_url": (
        '<svg xmlns="http://www.w3.org/2000/svg">'
        '<rect style="fill:url(https://example.invalid/p.png)" width="9"/></svg>'
    ),
    "presentation_attribute_external_url": (
        '<svg xmlns="http://www.w3.org/2000/svg">'
        '<rect fill="url(https://example.invalid/p.png)" width="9"/></svg>'
    ),
    "style_element_import": (
        '<svg xmlns="http://www.w3.org/2000/svg">'
        '<style>@import "https://example.invalid/p.css";</style></svg>'
    ),
    "style_attribute_import": (
        '<svg xmlns="http://www.w3.org/2000/svg">'
        '<rect style="@import &#34;https://example.invalid/p.css&#34;" width="9"/></svg>'
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
    # The element check is an ALLOWLIST, so the HTML elements that break out of
    # SVG foreign content in a browser — and would then carry HTML's own
    # resource-loading attributes — refuse by construction, as does a name
    # nobody has thought of.
    "html_p": '<svg xmlns="http://www.w3.org/2000/svg"><p>text</p></svg>',
    "html_img": '<svg xmlns="http://www.w3.org/2000/svg"><img src="https://example.invalid/t.gif"/></svg>',
    "html_div": '<svg xmlns="http://www.w3.org/2000/svg"><div>text</div></svg>',
    "unrecognised_element": '<svg xmlns="http://www.w3.org/2000/svg"><sparkline r="4"/></svg>',
    # SMIL can rewrite an attribute after the check has read it.
    "animation": (
        '<svg xmlns="http://www.w3.org/2000/svg"><a href="#x">'
        '<set attributeName="href" to="javascript:alert(1)"/></a></svg>'
    ),
    # <image> and <feImage> fetch a resource.
    "raster_image": (
        '<svg xmlns="http://www.w3.org/2000/svg"><image href="#local" width="9"/></svg>'
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


def test_a_data_image_inside_url_is_still_refused(tmp_path: Path) -> None:
    """The url() rule is stricter than the data: rule, and wins.

    `data:image/` is carved out of the value rule that refuses javascript: and
    other data: URLs, but a url() may only be a `#` fragment — so wrapping a
    data:image in url() refuses. Nothing is lost: url() in `fill` names a paint
    server element, not an image, and <image> is outside the vocabulary, so a
    raster cannot reach an accepted chart by any route. Charts here are vector.
    The carve-out stays in the value rule as defence in depth, and would matter
    again the day <image> were allowlisted.
    """
    body = (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 8 8">'
        '<rect fill="url(data:image/png;base64,iVBORw0KGgo=)" width="8" height="8"/></svg>'
    )
    html = _render(f"# Page\n\n```svg\n{body}\n```\n", tmp_path)
    assert NOTE in html
    assert "<svg" not in html


# Every element the allowlist names, in one chart: structure, shapes, text,
# gradients, patterns, clipping, markers, links and the filter primitives. If
# adding a name to SVG_ALLOWED_ELEMENTS, add it here too.
VOCABULARY = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 100">
  <title>Everything</title>
  <desc>One chart using the whole vocabulary</desc>
  <defs>
    <linearGradient id="lg"><stop offset="0" stop-color="#8fb8b0"/></linearGradient>
    <radialGradient id="rg"><stop offset="1" stop-color="#bd5d3a"/></radialGradient>
    <pattern id="pat" width="4" height="4"><rect width="2" height="2"/></pattern>
    <clipPath id="clip"><rect width="90" height="90"/></clipPath>
    <mask id="mk"><rect width="90" height="90" fill="#fff"/></mask>
    <marker id="arrow" markerWidth="4" markerHeight="4"><path d="M0,0 L4,2 L0,4 z"/></marker>
    <symbol id="dot"><circle cx="2" cy="2" r="2"/></symbol>
    <path id="curve" d="M10,80 Q60,10 110,80"/>
    <filter id="shadow">
      <feGaussianBlur stdDeviation="1"/>
      <feOffset dx="1" dy="1"/>
      <feFlood flood-color="#333"/>
      <feColorMatrix type="saturate" values="0.6"/>
      <feComposite operator="over"/>
      <feBlend mode="multiply"/>
      <feMorphology radius="1"/>
      <feDropShadow dx="1" dy="1"/>
      <feMerge><feMergeNode/></feMerge>
    </filter>
  </defs>
  <style>.bar{fill:url(#lg);stroke:#5d5a55}</style>
  <g clip-path="url(#clip)" mask="url(#mk)" filter="url(#shadow)" transform="translate(2,2)">
    <rect class="bar" x="1" y="1" width="8" height="8" style="fill:url(#lg)"/>
    <circle cx="20" cy="20" r="5" fill="url(#rg)"/>
    <ellipse cx="40" cy="20" rx="6" ry="3" fill="url(#pat)"/>
    <line x1="0" y1="0" x2="10" y2="10" marker-end="url(#arrow)"/>
    <polyline points="0,0 5,5 10,0" fill="none"/>
    <polygon points="0,0 5,0 5,5"/>
    <use href="#dot" x="60" y="10"/>
    <text x="10" y="95">label<tspan dx="2">more</tspan></text>
    <text><textPath href="#curve">along the curve</textPath></text>
    <a href="#results"><text x="150" y="95">jump</text></a>
  </g>
</svg>"""


def test_the_whole_chart_vocabulary_renders(tmp_path: Path) -> None:
    """Every allowlisted element, in one chart, inlined verbatim.

    The chart reaches its own gradient three ways on purpose — from the <style>
    element, from a style= attribute and from presentation attributes — because
    `url(#id)` is refused nowhere. Only a url() that could FETCH is.
    """
    html = _render(f"# Page\n\n```svg\n{VOCABULARY}\n```\n", tmp_path)
    assert VOCABULARY in html
    assert NOTE not in html


def test_an_internal_url_reference_is_accepted_everywhere(tmp_path: Path) -> None:
    """`url(#id)` cannot fetch, and it is how a chart reaches its own paint.

    Quotes and whitespace inside the delimiter are the same reference, so
    `url( '#lg' )` is read exactly as `url(#lg)` — a browser would.
    """
    body = (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 9 9">'
        '<defs><linearGradient id="lg"><stop offset="0" stop-color="#8fb8b0"/></linearGradient>'
        '<filter id="f"><feGaussianBlur stdDeviation="1"/></filter></defs>'
        "<style>.bar{fill:url( '#lg' )}</style>"
        '<rect class="bar" style="filter:url(#f)" fill="url(#lg)" width="9" height="9"/></svg>'
    )
    html = _render(f"# Page\n\n```svg\n{body}\n```\n", tmp_path)
    assert body in html
    assert NOTE not in html


def test_the_note_names_the_element_that_refused(tmp_path: Path) -> None:
    """The fix is 'add this name', so the reader has to be told which name."""
    html = _render(
        '# Page\n\n```svg\n<svg xmlns="http://www.w3.org/2000/svg"><sparkline/></svg>\n```\n',
        tmp_path,
    )
    assert "&lt;sparkline&gt; element, which is not in the chart vocabulary" in html


def test_an_svg_fence_with_extra_info_words_stays_escaped(tmp_path: Path) -> None:
    """Only the exact info string `svg` passes, as with mermaid."""
    html = _render(
        '# Page\n\n```svg example\n<svg xmlns="http://www.w3.org/2000/svg"/>\n```\n', tmp_path
    )
    assert "<svg" not in html
    assert "&lt;svg" in html
    assert NOTE not in html
