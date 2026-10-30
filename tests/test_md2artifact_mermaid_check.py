"""Guards md2artifact's build-time Mermaid check.

Background: a page generator wrote Mermaid decision nodes as Q"text" instead of
Q{"text"} (a Python f-string ate the braces), and md2artifact passed the broken
blocks through silently, so the published page showed parse-error boxes. The
check parses every diagram with Mermaid's own parser before the page is
written: a block that fails stops the build, and a parser that cannot run
(no uv, Chrome or network, or a sandbox) only warns.

Every test here stubs the parser except the last, which drives the real one
and skips when it cannot run.
"""

from __future__ import annotations

import importlib.machinery
import importlib.util
import sys
from pathlib import Path

import pytest

MD2ARTIFACT = Path(__file__).resolve().parent.parent / "custom_bins" / "md2artifact"


def _load():
    spec = importlib.util.spec_from_loader(
        "md2artifact_mermaid_check_cli",
        importlib.machinery.SourceFileLoader("md2artifact_mermaid_check_cli", str(MD2ARTIFACT)),
    )
    mod = importlib.util.module_from_spec(spec)
    sys.modules["md2artifact_mermaid_check_cli"] = mod
    spec.loader.exec_module(mod)
    return mod


md2 = _load()

GOOD = 'flowchart TD\n  A["start"] --> Q{"Is it on?"}\n  Q -- "yes" --> B["on"]'
BROKEN = 'flowchart TD\n  A["start"] --> Q"Is it on?"'

PAGE = f"""# Page

```mermaid
{GOOD}
```

<pre class="mermaid">
{BROKEN}
</pre>

Syntax shown as an example, not a diagram:

```
<pre class="mermaid">
flowchart TD
    E --> F
</pre>
```
"""


@pytest.fixture
def page(tmp_path: Path) -> Path:
    src = tmp_path / "page.md"
    src.write_text(PAGE, encoding="utf-8")
    return src


def test_sources_are_what_mermaid_reads_with_their_lines() -> None:
    """Both spellings count, unescaped; an example in a plain fence does not."""
    assert md2.mermaid_sources(PAGE) == [(3, GOOD), (9, BROKEN)]


def test_a_block_that_fails_to_parse_stops_the_build(page, monkeypatch, capsys) -> None:
    monkeypatch.setattr(
        md2, "run_mermaid_parser", lambda blocks: [None, "Parse error on line 2:\nExpecting 'SEMI'"]
    )
    out = page.with_suffix(".html")
    assert md2.main([str(page), "-o", str(out)]) == 1
    err = capsys.readouterr().err
    assert "mermaid block 2 of 2 (line 9, starts 'flowchart TD') does not parse:" in err
    assert "    Parse error on line 2:\n    Expecting 'SEMI'" in err
    assert "block 1 of 2" not in err
    assert not out.exists()


def test_an_unavailable_parser_warns_and_builds(page, monkeypatch, capsys) -> None:
    def unavailable(blocks):
        raise md2.MermaidCheckUnavailable("BrowserType.launch: no chrome")

    monkeypatch.setattr(md2, "run_mermaid_parser", unavailable)
    out = page.with_suffix(".html")
    assert md2.main([str(page), "-o", str(out)]) == 0
    err = capsys.readouterr().err
    assert "warning: mermaid check skipped, 2 diagram(s) not validated" in err
    assert "no chrome" in err
    assert out.exists()


def test_the_flag_and_a_diagram_free_page_never_start_the_parser(
    page, tmp_path, monkeypatch
) -> None:
    def must_not_run(blocks):
        raise AssertionError("the parser ran")

    monkeypatch.setattr(md2, "run_mermaid_parser", must_not_run)
    assert md2.main([str(page), "-o", str(tmp_path / "a.html"), "--no-mermaid-check"]) == 0
    plain = tmp_path / "plain.md"
    plain.write_text("# Plain\n\nNo diagrams here.\n", encoding="utf-8")
    assert md2.main([str(plain), "-o", str(tmp_path / "b.html")]) == 0


def test_no_uv_is_unavailable_not_a_failure(monkeypatch) -> None:
    monkeypatch.setattr(md2.shutil, "which", lambda name: None)
    with pytest.raises(md2.MermaidCheckUnavailable, match="uv is not on PATH"):
        md2.run_mermaid_parser([GOOD])


def test_real_parser_accepts_good_and_rejects_the_eaten_braces() -> None:
    """Mermaid's own parser in Chrome; skipped when it cannot start here."""
    try:
        verdicts = md2.run_mermaid_parser([GOOD, BROKEN])
    except md2.MermaidCheckUnavailable as exc:
        pytest.skip(f"mermaid parser unavailable: {exc}")
    assert verdicts[0] is None
    assert verdicts[1] and "Parse error" in verdicts[1]
