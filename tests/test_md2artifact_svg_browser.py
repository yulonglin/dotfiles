"""What a browser does with the ```svg fences md2artifact emits.

The unit suite (tests/test_md2artifact_svg.py) asserts what the check decides.
This file asserts what Chromium then does with the page, which is the only
question that matters: a fence that inlines is not a fence that fetches, and a
fence that is refused must leave nothing behind.

The measurement that made it worth having: the whitespace-flattening bypass
was reported as a matcher gap, and it is more than that. Built with the
pre-fix script, the page below issued TWO requests to the recording server —
one from a `<style>` element and one from a `style=` attribute — while the
same page built with the grammar issues none. So the probe can see a leak, and
the zero it reports afterwards is a result rather than a silent failure.

Needs Playwright and Chromium; skipped when there is no browser on the machine.
The page is served over HTTP because `file://` is blocked in the Playwright
plugin. Every hostile URL points back at that same server, so a fetch is
recorded as a request rather than escaping the machine.
"""

from __future__ import annotations

import http.server
import socketserver
import subprocess
import sys
import threading
from pathlib import Path

import pytest

playwright_api = pytest.importorskip("playwright.sync_api")
sync_playwright = playwright_api.sync_playwright

ROOT = Path(__file__).resolve().parent.parent
MD2ARTIFACT = ROOT / "custom_bins" / "md2artifact"

# Each spelling names its own path, so the recorded request says which one
# fetched. Filled in with the server's port once it is listening.
HOSTILE = {
    "whitespace_joined_style_element": (
        '<svg xmlns="http://www.w3.org/2000/svg">'
        '<style>rect{background:no-repeat image-set("http://127.0.0.1:%(port)d/leak-a.png" 1x)}'
        "</style></svg>"
    ),
    "whitespace_joined_style_attribute": (
        '<svg xmlns="http://www.w3.org/2000/svg">'
        "<rect style=\"background:repeat-x image-set('http://127.0.0.1:%(port)d/leak-b.png' 1x)\""
        ' width="9" height="9"/></svg>'
    ),
    "escaped_url": (
        '<svg xmlns="http://www.w3.org/2000/svg">'
        "<style>.x{fill:\\75 rl(http://127.0.0.1:%(port)d/leak-c.png)}</style></svg>"
    ),
    "comment_split_url": (
        '<svg xmlns="http://www.w3.org/2000/svg">'
        "<style>.x{fill:u/**/rl(http://127.0.0.1:%(port)d/leak-d.png)}</style></svg>"
    ),
    "plain_image_set": (
        '<svg xmlns="http://www.w3.org/2000/svg">'
        '<style>rect{mask:image-set("http://127.0.0.1:%(port)d/leak-e.png" 1x)}</style></svg>'
    ),
    "script_element": (
        '<svg xmlns="http://www.w3.org/2000/svg"><script>fetch("/leak-f.png")</script></svg>'
    ),
}

BENIGN = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 240 120" role="img" aria-label="Two bars">
  <title>Two bars</title>
  <style>.bar { fill: #7a9e9f; } text { font-size: 9px; }</style>
  <rect class="bar" x="10" y="40" width="60" height="70"/>
  <a href="#results"><text x="180" y="112">jump</text></a>
</svg>"""


class _Server(socketserver.ThreadingTCPServer):
    """Chromium preconnects speculatively, and a single-threaded server would
    let one idle socket block every later request until Playwright times out."""

    daemon_threads = True
    allow_reuse_address = True


@pytest.fixture(scope="module")
def probe(tmp_path_factory):
    """Serve one generated page and record every path the browser asks for."""
    tmp = tmp_path_factory.mktemp("md2artifact-svg-browser")
    page_file = tmp / "page.html"
    seen: list[str] = []

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            seen.append(self.path)
            if self.path == "/page.html" and page_file.exists():
                body = page_file.read_bytes()
                self.send_response(200)
                self.send_header("Content-Type", "text/html")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
                return
            self.send_response(404)
            self.end_headers()

        def do_POST(self):
            seen.append("POST " + self.path)
            self.send_response(204)
            self.end_headers()

        def log_message(self, *args):
            pass

    with _Server(("127.0.0.1", 0), Handler) as server:
        port = server.server_address[1]
        threading.Thread(target=server.serve_forever, daemon=True).start()
        source = "# Chart page\n\n"
        for name, body in HOSTILE.items():
            source += f"## {name}\n\n```svg\n{body % {'port': port}}\n```\n\n"
        source += f"## benign\n\n```svg\n{BENIGN}\n```\n"
        md = tmp / "page.md"
        md.write_text(source, encoding="utf-8")
        result = subprocess.run(
            [sys.executable, str(MD2ARTIFACT), str(md), "-o", str(page_file)],
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode != 0:
            pytest.skip(f"md2artifact could not run here: {result.stderr.strip()}")
        with sync_playwright() as pw:
            browser = pw.chromium.launch()
            page = browser.new_page()
            page.goto(f"http://127.0.0.1:{port}/page.html")
            page.wait_for_timeout(1500)
            facts = {
                "svg_roots": page.evaluate("document.querySelectorAll('svg').length"),
                "scripts_in_fences": page.evaluate(
                    "document.querySelectorAll('svg script').length"
                ),
                "notes": page.evaluate("document.querySelectorAll('.svg-note').length"),
                "label": page.evaluate(
                    "document.querySelector('svg')?.getAttribute('aria-label')"
                ),
            }
            browser.close()
        server.shutdown()
    facts["requests"] = list(seen)
    return facts


def test_only_the_benign_chart_reaches_the_dom(probe) -> None:
    assert probe["svg_roots"] == 1
    assert probe["label"] == "Two bars"
    assert probe["scripts_in_fences"] == 0


def test_every_hostile_fence_leaves_a_visible_note(probe) -> None:
    assert probe["notes"] == len(HOSTILE)


def test_the_page_fetches_nothing_but_itself(probe) -> None:
    """Zero is a result here, not an absence.

    Built with the pre-fix script this same page fetched /leak-a.png and
    /leak-b.png, so a regression that reopens the hole shows up as a path in
    this list rather than as silence.
    """
    assert probe["requests"] == ["/page.html"]
