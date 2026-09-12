"""Guards md2artifact's ```svg passthrough.

Background: md2artifact parses Markdown with html disabled, so inline SVG used
to render as literal escaped text — which is why chart pages had to be
hand-written HTML around the pipeline instead of going through it. Charts on an
artifact page are native SVG drawn from `lib/plotting/tokens.json`, so an SVG
fence is the third deliberate exception to html-off, alongside mermaid and
<details>.

It is also the only exception that emits user text UNESCAPED, so it pays for
that with a sanitising check, and that check is two allowlists: an element
vocabulary, and a positive grammar for styling — a property this feature needs
whose value is a colour, a number, a bare word, a numeric colour function or a
same-document `url(#id)`. Anything else refuses. Anything rejected falls back
to an escaped code block plus a visible note — exactly what a plain fence did
before — so the property the passthrough registry exists to hold is unchanged:
a Markdown document you did not write cannot put script into your published
page.

The styling half used to be a text matcher searching a flattened string for
dangerous constructs, and it was bypassed three times: an escaped spelling, a
comment, and a shorthand keyword that the flattening joined to the function
name after it. Those three now fail on the same rule, because the grammar has
no production for any of them — which is the property a denylist over a
language with that much lexical freedom could never have.
"""

from __future__ import annotations

import shutil
import subprocess
import sys
from html.parser import HTMLParser
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


# ─── Parser divergence: what an HTML parser makes of the accepted source ──────
# The fence is emitted verbatim into a page that a BROWSER parses, and an HTML
# parser is not an XML parser. Judging the source with ElementTree alone is a
# bet that the two agree; these tests hold the bet closed.


class _Dom(HTMLParser):
    """The tags and the oddities an HTML parser finds, in order."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.tags: list[tuple[str, dict[str, str | None]]] = []
        self.oddities: list[tuple[str, str]] = []

    def handle_starttag(self, tag, attrs):
        self.tags.append((tag, dict(attrs)))

    def handle_startendtag(self, tag, attrs):
        self.tags.append((tag, dict(attrs)))

    def handle_comment(self, data):
        self.oddities.append(("comment", data))

    def handle_decl(self, decl):
        self.oddities.append(("decl", decl))

    def unknown_decl(self, data):
        self.oddities.append(("unknown_decl", data))

    def handle_pi(self, data):
        self.oddities.append(("pi", data))


def _dom(fragment: str) -> _Dom:
    parser = _Dom()
    parser.feed(fragment)
    parser.close()
    return parser


def _inlined_svg(page: str) -> str:
    """The inlined chart, sliced out of the page so the page's own script tags
    do not pollute the assertion."""
    start = page.index("<svg")
    end = page.index("</svg>", start) + len("</svg>")
    return page[start:end]


def test_the_accepted_chart_parses_as_the_expected_html_dom(page_html: str) -> None:
    """Assert on the DOM an HTML parser builds, not on the output string.

    A string assertion only says the bytes survived; it cannot see that an HTML
    parser read those same bytes as a different tree. Pinning the tag sequence
    means a future divergence — a spelling ElementTree accepts and an HTML
    parser turns into something else — fails here instead of shipping.
    """
    dom = _dom(_inlined_svg(page_html))
    names = [name for name, _ in dom.tags]
    assert names == ["svg", "title", "style", "rect", "rect", "text", "a", "text"]
    assert dom.oddities == []
    assert dom.tags[0][1]["viewbox"] == "0 0 240 120"
    assert dom.tags[6][1]["href"] == "#results"


# A namespace-prefixed root passes an XML check that strips the prefix, but an
# HTML parser sees an unknown element and so never enters SVG foreign content —
# where a CDATA section stops being text and becomes a bogus comment that ends
# at its first `>`, releasing whatever follows as live markup.
PREFIXED_CDATA_BYPASS = (
    '<s:svg xmlns:s="http://www.w3.org/2000/svg">'
    "<![CDATA[><script>alert(1)</script>]]>"
    "</s:svg>"
)


def test_a_namespace_prefixed_root_is_rejected(tmp_path: Path) -> None:
    body = (
        '<s:svg xmlns:s="http://www.w3.org/2000/svg">'
        '<s:rect width="9" height="9"/></s:svg>'
    )
    html = _render(f"# Page\n\n```svg\n{body}\n```\n", tmp_path)
    assert NOTE in html
    assert "<s:svg" not in html, "inlined a namespace-prefixed root verbatim"
    assert "&lt;s:svg" in html


def test_a_cdata_section_is_rejected(tmp_path: Path) -> None:
    body = (
        '<svg xmlns="http://www.w3.org/2000/svg">'
        "<![CDATA[><script>alert(1)</script>]]></svg>"
    )
    html = _render(f"# Page\n\n```svg\n{body}\n```\n", tmp_path)
    assert NOTE in html
    assert "<![CDATA[" not in html
    assert "<svg" not in html


def test_the_prefixed_root_cdata_bypass_cannot_reach_the_page(tmp_path: Path) -> None:
    """The reproduction: XML says accepted, an HTML parser builds a <script>."""
    html = _render(f"# Page\n\n```svg\n{PREFIXED_CDATA_BYPASS}\n```\n", tmp_path)
    assert NOTE in html
    assert "<![CDATA[" not in html
    assert "<script>alert(1)</script>" not in html


# ─── CSS escapes: the same at-rule and the same function, spelled otherwise ───
# A CSS parser resolves `\69` to `i` and `\75` to `u` before it decides what an
# at-keyword or a function token is; a textual check that does not decode first
# reads a different string from the one the browser acts on.
ESCAPED_CSS = {
    "style_element_escaped_import": (
        '<svg xmlns="http://www.w3.org/2000/svg">'
        '<style>@\\69 mport "https://example.invalid/p.css";</style></svg>'
    ),
    "style_attribute_escaped_import": (
        '<svg xmlns="http://www.w3.org/2000/svg">'
        '<rect style="@\\69 mport &#34;https://example.invalid/p.css&#34;" width="9"/></svg>'
    ),
    "style_element_escaped_url": (
        '<svg xmlns="http://www.w3.org/2000/svg">'
        "<style>.bar{fill:\\75 rl(https://example.invalid/p.png)}</style></svg>"
    ),
    "style_attribute_escaped_url": (
        '<svg xmlns="http://www.w3.org/2000/svg">'
        '<rect style="fill:u\\72 l(https://example.invalid/p.png)" width="9"/></svg>'
    ),
    "presentation_attribute_escaped_url": (
        '<svg xmlns="http://www.w3.org/2000/svg">'
        '<rect fill="u\\72\\6c(https://example.invalid/p.png)" width="9"/></svg>'
    ),
}


@pytest.mark.parametrize("case", sorted(ESCAPED_CSS))
def test_escaped_css_spellings_are_rejected(case: str, tmp_path: Path) -> None:
    html = _render(f"# Page\n\n```svg\n{ESCAPED_CSS[case]}\n```\n", tmp_path)
    assert NOTE in html, f"{case}: no rejection note"
    assert "<svg" not in html, f"{case}: inlined a fence that can fetch an external resource"


# ─── Comments: the third preprocessing layer between the bytes and the token ──
# A CSS tokenizer deletes `/* … */` before it decides what a token is, so the
# flattened text a matcher searches is not the text the browser acts on. The
# reported spellings below do NOT in fact fetch — measured on Chromium 151, a
# comment separates tokens rather than joining them, so `u/**/rl(` resolves to
# two idents and the declaration is dropped. They are refused anyway: an inline
# chart has no use for a comment, and leaving a preprocessing layer unmodelled
# is how the two escape holes before this one got in.
COMMENT_SPLIT_CSS = {
    "style_element_comment_split_import": (
        '<svg xmlns="http://www.w3.org/2000/svg">'
        '<style>@i/**/mport "https://example.invalid/p.css";</style></svg>'
    ),
    "style_element_comment_split_url": (
        '<svg xmlns="http://www.w3.org/2000/svg">'
        "<style>.bar{fill:u/**/rl(https://example.invalid/p.png)}</style></svg>"
    ),
    "style_element_comment_before_paren": (
        '<svg xmlns="http://www.w3.org/2000/svg">'
        "<style>.bar{fill:url/**/(https://example.invalid/p.png)}</style></svg>"
    ),
    "style_attribute_comment_split_import": (
        '<svg xmlns="http://www.w3.org/2000/svg">'
        '<rect style="@i/**/mport &#34;https://example.invalid/p.css&#34;" width="9"/></svg>'
    ),
    "style_attribute_comment_split_url": (
        '<svg xmlns="http://www.w3.org/2000/svg">'
        '<rect style="fill:u/**/rl(https://example.invalid/p.png)" width="9"/></svg>'
    ),
    "presentation_attribute_comment_split_url": (
        '<svg xmlns="http://www.w3.org/2000/svg">'
        '<rect fill="u/**/rl(https://example.invalid/p.png)" width="9"/></svg>'
    ),
    # A comment is refused wherever it sits, including the positions where it
    # IS a legal separator and the construct does fetch.
    "style_element_comment_after_import": (
        '<svg xmlns="http://www.w3.org/2000/svg">'
        '<style>@import/**/url(https://example.invalid/p.css);</style></svg>'
    ),
}


@pytest.mark.parametrize("case", sorted(COMMENT_SPLIT_CSS))
def test_comment_split_css_spellings_are_rejected(case: str, tmp_path: Path) -> None:
    html = _render(f"# Page\n\n```svg\n{COMMENT_SPLIT_CSS[case]}\n```\n", tmp_path)
    assert NOTE in html, f"{case}: no rejection note"
    assert "<svg" not in html, f"{case}: inlined a fence carrying a CSS comment"


# ─── A fetch that never spells `url(` ─────────────────────────────────────────
# `url()` and `@import` were the whole model of what fetches. `image-set()`
# takes a bare <string> as its URL, so it fetches with neither token present.
# Measured on Chromium 151: every spelling below issued the request, in the
# <style> element and through a style= attribute on an SVG <rect> alike.
FETCHING_FUNCTIONS = {
    "style_element_image_set": (
        '<svg xmlns="http://www.w3.org/2000/svg">'
        '<style>rect{mask-image:image-set("https://example.invalid/p.png" 1x)}</style></svg>'
    ),
    "style_element_image_set_uppercase": (
        '<svg xmlns="http://www.w3.org/2000/svg">'
        '<style>rect{mask-image:IMAGE-SET("https://example.invalid/p.png" 1x)}</style></svg>'
    ),
    "style_element_webkit_image_set": (
        '<svg xmlns="http://www.w3.org/2000/svg">'
        '<style>rect{-webkit-mask-image:-webkit-image-set("https://example.invalid/p.png" 1x)}'
        "</style></svg>"
    ),
    "style_attribute_image_set": (
        '<svg xmlns="http://www.w3.org/2000/svg">'
        "<rect style=\"mask-image:image-set('https://example.invalid/p.png' 1x)\" width=\"9\"/>"
        "</svg>"
    ),
    "style_element_escaped_image_set": (
        '<svg xmlns="http://www.w3.org/2000/svg">'
        '<style>rect{mask-image:\\69 mage-set("https://example.invalid/p.png" 1x)}</style></svg>'
    ),
}


@pytest.mark.parametrize("case", sorted(FETCHING_FUNCTIONS))
def test_a_css_function_that_fetches_without_url_is_rejected(case: str, tmp_path: Path) -> None:
    html = _render(f"# Page\n\n```svg\n{FETCHING_FUNCTIONS[case]}\n```\n", tmp_path)
    assert NOTE in html, f"{case}: no rejection note"
    assert "<svg" not in html, f"{case}: inlined a fence that can fetch an external resource"


def test_a_ping_attribute_is_rejected(tmp_path: Path) -> None:
    """<a ping> POSTs to every listed URL when the link is followed.

    Measured on Chromium 151: the POST goes out on click from an SVG <a>. The
    href rule exists to stop exactly this leak, and read only href.
    """
    body = (
        '<svg xmlns="http://www.w3.org/2000/svg">'
        '<a href="#x" ping="https://example.invalid/p"><text>go</text></a></svg>'
    )
    html = _render(f"# Page\n\n```svg\n{body}\n```\n", tmp_path)
    assert NOTE in html
    assert "<svg" not in html


def test_parentheses_and_apostrophes_in_label_text_are_still_accepted(tmp_path: Path) -> None:
    """Label text is the reason the grammar is routed by attribute name.

    `aria-label="Bar chart image (USD)"` reads as a function call to any
    matcher that allowlists `ident(`, and refusing it would refuse real
    charts. So `aria-*`, `role`, `lang` and `title` are the names granted a
    plain-text shape, while every other attribute value has to satisfy the
    styling-value grammar — the looseness is granted to a name that was
    positively recognised, never to a value that happened to look benign.
    """
    body = (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 9 9" role="img"'
        ' aria-label="Bar chart image (USD, 2024) — Bob\'s revenue (approx)">'
        '<title>Revenue (USD)</title><rect width="9" height="9" fill="#8fb8b0"/></svg>'
    )
    html = _render(f"# Page\n\n```svg\n{body}\n```\n", tmp_path)
    assert body in html
    assert NOTE not in html


# ─── The third bypass, and why the matcher was replaced by a grammar ──────────
# A shorthand property legitimately takes a keyword before the value that
# fetches. The old check flattened the declaration to a single string before
# matching, which joined that keyword to the function name and so destroyed the
# leading boundary the match needed — the comment claiming that removing
# whitespace "can only ever produce MORE matches than a parser sees" was false,
# and this is the counter-example. Confirmed accepted by the old check, and
# confirmed fetching in Chromium by the reviewer who reported it.
#
# These cases are refused now by the POSITIVE GRAMMAR, not by a rule naming
# them: the grammar permits one function spelling in a value (`url(#id)`) plus
# the numeric colour functions, so a function it has never heard of refuses
# whatever the surrounding whitespace does. The same grammar is what refuses
# the two spellings fixed before it — escapes and comments — so all three are
# now covered by one rule instead of three special cases.
WHITESPACE_JOINED = {
    "style_element_shorthand_keyword_joins_function": (
        '<svg xmlns="http://www.w3.org/2000/svg">'
        '<style>rect{background:no-repeat image-set("https://example.invalid/p.png" 1x)}</style>'
        "</svg>"
    ),
    "style_element_mask_shorthand_keyword_joins_function": (
        '<svg xmlns="http://www.w3.org/2000/svg">'
        '<style>rect{mask:no-repeat image-set("https://example.invalid/p.png" 1x)}</style></svg>'
    ),
    "style_attribute_shorthand_keyword_joins_function": (
        '<svg xmlns="http://www.w3.org/2000/svg">'
        "<rect style=\"background:repeat-x image-set('https://example.invalid/p.png' 1x)\""
        ' width="9"/></svg>'
    ),
    "style_element_shorthand_keyword_joins_url": (
        '<svg xmlns="http://www.w3.org/2000/svg">'
        "<style>rect{background:no-repeat url(https://example.invalid/p.png)}</style></svg>"
    ),
}


@pytest.mark.parametrize("case", sorted(WHITESPACE_JOINED))
def test_a_keyword_abutting_the_function_after_flattening_is_rejected(
    case: str, tmp_path: Path
) -> None:
    html = _render(f"# Page\n\n```svg\n{WHITESPACE_JOINED[case]}\n```\n", tmp_path)
    assert NOTE in html, f"{case}: no rejection note"
    assert "<svg" not in html, f"{case}: inlined a fence that can fetch an external resource"


# ─── The grammar refuses by shape, so a new spelling is refused unread ────────
# Every case below is a construct the grammar has no production for. None of
# them needs its own rule: `@`, `\`, `/*`, a quote outside a font stack and an
# unknown function name are all simply characters and tokens the value grammar
# never permits.
UNRECOGNISED_SHAPES = {
    "unknown_property": (
        '<svg xmlns="http://www.w3.org/2000/svg">'
        "<style>rect{behavior:default}</style></svg>"
    ),
    "unknown_function": (
        '<svg xmlns="http://www.w3.org/2000/svg">'
        "<style>rect{width:calc(100% - 2px)}</style></svg>"
    ),
    "at_rule": (
        '<svg xmlns="http://www.w3.org/2000/svg">'
        "<style>@media screen{rect{fill:#333}}</style></svg>"
    ),
    "backslash_in_a_value": (
        '<svg xmlns="http://www.w3.org/2000/svg">'
        "<style>rect{fill:\\23 333}</style></svg>"
    ),
    "string_outside_a_font_stack": (
        '<svg xmlns="http://www.w3.org/2000/svg">'
        '<style>rect{fill:"https://example.invalid/p.png"}</style></svg>'
    ),
    "attribute_selector": (
        '<svg xmlns="http://www.w3.org/2000/svg">'
        "<style>rect[fill]{fill:#333}</style></svg>"
    ),
    "unknown_transform_function": (
        '<svg xmlns="http://www.w3.org/2000/svg">'
        '<rect transform="attr(href)" width="9"/></svg>'
    ),
    "external_namespace_declaration": (
        '<svg xmlns="http://www.w3.org/2000/svg" xmlns:z="https://example.invalid/ns">'
        '<rect width="9"/></svg>'
    ),
}


@pytest.mark.parametrize("case", sorted(UNRECOGNISED_SHAPES))
def test_a_shape_the_grammar_does_not_permit_is_rejected(case: str, tmp_path: Path) -> None:
    html = _render(f"# Page\n\n```svg\n{UNRECOGNISED_SHAPES[case]}\n```\n", tmp_path)
    assert NOTE in html, f"{case}: no rejection note"
    assert "<svg" not in html, f"{case}: inlined a fence the grammar cannot recognise"


def test_the_note_names_the_property_that_refused(tmp_path: Path) -> None:
    """A legitimate diagram that trips the grammar has to be fixable.

    Naming the property is the whole difference between 'add this to the
    allowlist' and a chart that mysteriously became a code block.
    """
    html = _render(
        '# Page\n\n```svg\n<svg xmlns="http://www.w3.org/2000/svg">'
        "<style>rect{behavior:default}</style></svg>\n```\n",
        tmp_path,
    )
    assert "behavior" in html


def test_the_grammar_accepts_the_styling_a_real_diagram_uses(tmp_path: Path) -> None:
    """The cost check: the properties and value shapes measured in this repo.

    Every property here is used by a diagram in this repo's tests or in the
    `tufte-data-viz` skill's SVG templates. If the allowlist ever has to grow,
    this is where the new property gets pinned.
    """
    body = (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 60"'
        ' style="vertical-align:middle;background:#fffff8">'
        "<style>"
        ".tufte-chart text { font-family: 'ET Book', Palatino, Georgia, serif;"
        " font-size: 11px; fill: #999; letter-spacing: 0.05em }"
        ".axis-line, .tick line { stroke: #ccc; stroke-width: 0.5;"
        " stroke-dasharray: 4 3; stroke-linejoin: round }"
        ".domain { display: none }"
        ".data-line { fill: none; stroke: rgba(102, 102, 102, 0.9); stroke-width: 1.5 }"
        "</style>"
        '<polyline class="data-line" points="0,15.3 10,12.8 20,9.4 30,13.6"/>'
        '<circle cx="0" cy="15.3" r="1.5" fill="#4e79a7" fill-opacity=".8"/>'
        '<text x="10" y="50" text-anchor="middle" font-weight="400" font-style="italic"'
        ' opacity="0.9" paint-order="stroke">label</text>'
        '<g transform="translate(60, 40)" clip-path="url(#clip)">'
        '<rect width="9" height="9" stroke-linecap="round" vector-effect="non-scaling-stroke"/>'
        "</g></svg>"
    )
    html = _render(f"# Page\n\n```svg\n{body}\n```\n", tmp_path)
    assert NOTE not in html
    assert body in html


# ─── The cost of the grammar, measured against real diagrams ─────────────────
# Every SVG in this repo's documentation, as the documentation writes it. The
# grammar was built from these plus the charts above, so if it ever has to be
# widened or narrowed, this is what says whether a real diagram paid for it.
# Both carry HTML comments, which an ```svg fence has refused since before the
# grammar existed, so they are exercised the way a fence would have to carry
# them: with the comments taken out.
TUFTE_BASE_TEMPLATE = """<svg viewBox="0 0 750 500" xmlns="http://www.w3.org/2000/svg"
     style="font-family: 'ET Book', 'Palatino Linotype', Palatino, Georgia, serif;
            background: #fffff8;">
  <g transform="translate(60, 40)">
  </g>
</svg>"""

TUFTE_SPARKLINE = """<svg viewBox="0 0 80 20" width="80" height="20" xmlns="http://www.w3.org/2000/svg"
     style="vertical-align: middle;">
  <polyline
    points="0,15.3 10,12.8 20,9.4 30,13.6 40,6.8 50,10.2 60,4.3 70,9.4 80,7.7"
    fill="none"
    stroke="#666"
    stroke-width="1"
    stroke-linejoin="round"
  />
  <circle cx="0" cy="15.3" r="1.5" fill="#4e79a7" />
  <circle cx="60" cy="4.3" r="1.5" fill="#e15759" />
  <circle cx="80" cy="7.7" r="1.5" fill="#666" />
</svg>"""


@pytest.mark.parametrize(
    "case,body",
    [("tufte_base_template", TUFTE_BASE_TEMPLATE), ("tufte_sparkline", TUFTE_SPARKLINE)],
)
def test_the_documented_diagrams_still_inline(case: str, body: str, tmp_path: Path) -> None:
    html = _render(f"# Page\n\n```svg\n{body}\n```\n", tmp_path)
    assert NOTE not in html, f"{case}: the grammar refuses a diagram the docs ship"
    assert body in html


def test_mask_type_is_in_the_vocabulary(tmp_path: Path) -> None:
    """Added as a decision, not a measurement.

    <mask> is in the element vocabulary and `mask-type` is how its mode is
    selected, so the gap was real even though the only file in this repo that
    uses it is refused anyway for embedding a raster <image>. The value is a
    keyword and cannot fetch.
    """
    body = (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 9 9">'
        '<mask id="m" style="mask-type:alpha"><rect width="9" height="9" fill="#fff"/></mask>'
        '<rect width="9" height="9" mask="url(#m)"/></svg>'
    )
    html = _render(f"# Page\n\n```svg\n{body}\n```\n", tmp_path)
    assert NOTE not in html
    assert body in html
