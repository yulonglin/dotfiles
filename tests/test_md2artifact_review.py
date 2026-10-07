"""Build-time half of md2artifact's review features.

Priority tags (`{judgement}`, `{lower}`), the Lower priority tray, the H2
section wrappers and their content hashes, and the `--capabilities` JSON.
The behaviour in a browser (folding, seen marks, the comment button) is in
test_md2artifact_review_browser.py.
"""

from __future__ import annotations

import importlib.machinery
import importlib.util
import json
import re
import subprocess
import sys
from pathlib import Path

import pytest

pytest.importorskip("markdown_it")

MD2ARTIFACT = Path(__file__).resolve().parent.parent / "custom_bins" / "md2artifact"


def _load():
    spec = importlib.util.spec_from_loader(
        "md2artifact_review_cli",
        importlib.machinery.SourceFileLoader("md2artifact_review_cli", str(MD2ARTIFACT)),
    )
    mod = importlib.util.module_from_spec(spec)
    sys.modules["md2artifact_review_cli"] = mod
    spec.loader.exec_module(mod)
    return mod


md2 = _load()


def _hashes(html: str) -> dict[str, str]:
    return dict(re.findall(r'<div class="sec" data-sec="([^"]+)" data-hash="([0-9a-f]+)"', html))


# ── tags ──


def test_judgement_tag_becomes_a_badge_and_leaves_the_text():
    out, headings = md2.render("## Pick a default {judgement}\n\nBody.\n")
    assert "{judgement}" not in out
    assert headings == [(2, "pick-a-default", "Pick a default")]
    assert '<h2 id="pick-a-default">Pick a default<span class="chip chip-call" data-label="Your call"></span></h2>' in out


def test_judgement_works_at_any_level():
    out, _ = md2.render("# Title {judgement}\n\n### Deep {judgement}\n")
    assert out.count("chip-call") == 2


def test_unknown_suffix_stays_as_text():
    out, headings = md2.render("## Odd {nope}\n\n### Also {Lower}\n")
    assert "Odd {nope}" in out and "Also {Lower}" in out
    assert "chip-call" not in out and "lower-tray" not in out
    assert headings[0][2] == "Odd {nope}"


def test_lower_on_h2_is_not_a_tag():
    out, _ = md2.render("## Top {lower}\n\nBody.\n")
    assert "Top {lower}" in out
    assert "lower-tray" not in out


def test_both_tags_together():
    out, headings = md2.render("## S\n\n### Both {judgement} {lower}\n\nx\n")
    assert headings[1][2] == "Both"
    assert "chip-call" in out and "Lower priority (1)" in out


def test_title_strips_the_judgement_tag(tmp_path):
    src = tmp_path / "doc.md"
    src.write_text("# Ship it? {judgement}\n\n## A\n\nx\n", encoding="utf-8")
    out = tmp_path / "doc.html"
    subprocess.run([sys.executable, str(MD2ARTIFACT), str(src), "-o", str(out)], check=True, capture_output=True)
    assert "<title>Ship it?</title>" in out.read_text(encoding="utf-8")


# ── the Lower priority tray ──

TRAY_DOC = """# Page

## First

Lead paragraph.

### Minor one {lower}

Minor one body.

#### Its own child

Still minor one.

### Kept

Kept body.

### Minor two {lower}

Minor two body.

## Second

Second body.
"""


def _section(out: str, sec: str) -> str:
    start = out.index(f'data-sec="{sec}"')
    nxt = out.find('<div class="sec" ', start)
    return out[start : nxt if nxt >= 0 else len(out)]


def test_lower_subsections_move_to_a_tray_at_the_end_of_their_section():
    out, _ = md2.render(TRAY_DOC)
    first = _section(out, "first")
    tray_at = first.index('<details class="lower-tray"><summary>Lower priority (2)</summary>')
    # Everything that was not tagged stays in place, before the tray.
    assert first.index("Lead paragraph.") < first.index("Kept body.") < tray_at
    # Both tagged subsections, with their own children, are inside it, in order.
    tray = first[tray_at:]
    assert tray.index("Minor one body.") < tray.index("Still minor one.") < tray.index("Minor two body.")
    assert tray.index("</details>") > tray.index("Minor two body.")
    # The tray closes inside the section body, before the section ends.
    assert "Second body." not in first
    assert "lower-tray" not in _section(out, "second")


def test_the_toc_follows_the_moved_order():
    _, headings = md2.render(TRAY_DOC)
    assert [h[2] for h in headings if h[0] == 3] == ["Kept", "Minor one", "Minor two"]


def test_a_lower_subsection_moves_whole_details_with_it():
    """Headings inside an open <details> are never boundaries — not even an
    H2 — so the moved range holds the whole element and the page balances."""
    src = "## S\n\n### Minor {lower}\n\n<details>\n\n### Inside\n\nx\n\n## T\n\n</details>\n\n### After\n\ny\n"
    out, _ = md2.render(src)
    assert list(_hashes(out)) == ["s"]
    tray = out[out.index("lower-tray") :]
    assert tray.index("Inside") < tray.index("</details>\n</details>")
    assert out.index("After") < out.index("lower-tray")
    assert out.count("<details") == out.count("</details>")


# ── sections ──


def test_each_top_level_h2_is_one_collapsible_section():
    out, _ = md2.render("# T\n\nIntro.\n\n## A\n\na\n\n> ## Quoted\n\n## B\n\nb\n")
    assert list(_hashes(out)) == ["a", "b"]
    a = _section(out, "a")
    assert 'aria-controls="a--body"' in a and 'aria-expanded="true"' in a
    assert '<div class="sec-body" id="a--body">' in a
    assert "Quoted" in a  # the quoted H2 is content, not a boundary
    # The page tools sit right under the H1, before the intro.
    assert out.index("page-tools") < out.index("Intro.")


def test_a_section_is_a_div_with_the_h2_as_the_bodys_heading_sibling():
    """The annotation layer labels a comment by `closest("section")`, else the
    nearest preceding heading sibling. A <section> would relabel every comment
    under an H3 with its H2."""
    out, _ = md2.render("## A\n\n### Sub\n\ntext\n")
    assert "<section" not in out
    assert re.search(r'<h2 id="a">A</h2>\s*<div class="sec-tools">.*?</div><div class="sec-body"', out)


def test_no_text_nodes_in_the_controls():
    """Dynamic labels are CSS generated content, so the layer's text search
    can never anchor a quote onto them."""
    out, _ = md2.render("# T\n\n## A\n\nx\n")
    for tag in re.findall(r"<(?:button|span|a)[^>]*class=\"(?:sec-toggle|seen-btn|chip seen-badge|unseen-sum|page-comment)[^>]*>(.*?)</", out):
        assert tag == ""


# ── hashes ──

HASH_DOC = """# T

## Alpha

- [ ] ship it

Alpha text.

## Beta

- [ ] ship it

Beta text.
"""


def test_hash_is_stable_across_rebuilds():
    assert _hashes(md2.render(HASH_DOC)[0]) == _hashes(md2.render(HASH_DOC)[0])


def test_hash_changes_when_the_section_changes():
    before = _hashes(md2.render(HASH_DOC)[0])
    after = _hashes(md2.render(HASH_DOC.replace("Beta text.", "Beta text, edited."))[0])
    assert before["alpha"] == after["alpha"]
    assert before["beta"] != after["beta"]


def test_hash_ignores_checklist_ids_allocated_elsewhere():
    """Task-control ids are allocated across the document: another `ship it`
    added to Alpha renumbers Beta's, which must not mark Beta Changed."""
    before = _hashes(md2.render(HASH_DOC)[0])
    after = _hashes(md2.render(HASH_DOC.replace("- [ ] ship it\n\nAlpha", "- [ ] ship it\n- [ ] ship it\n\nAlpha"))[0])
    assert after["beta"] == before["beta"]
    assert after["alpha"] != before["alpha"]


def test_hash_ignores_heading_ids_allocated_elsewhere():
    """A duplicate heading earlier on renames this section's id (its slug, so
    its seen mark is keyed afresh), but not its content hash."""
    before = _hashes(md2.render(HASH_DOC)[0])
    after = _hashes(md2.render(HASH_DOC.replace("Alpha text.", "Alpha text.\n\n### Beta"))[0])
    assert after["beta-1"] == before["beta"]


def test_hash_changes_when_a_tag_moves_content_into_the_tray():
    plain = "## A\n\nx\n\n### Sub\n\ny\n\n### Last\n\nz\n"
    tagged = plain.replace("### Sub", "### Sub {lower}")
    assert _hashes(md2.render(plain)[0])["a"] != _hashes(md2.render(tagged)[0])["a"]


# ── CLI ──


def test_capabilities_flag_prints_the_exact_json_without_a_source():
    r = subprocess.run([sys.executable, str(MD2ARTIFACT), "--capabilities"], capture_output=True, text=True, check=True)
    assert r.stdout == (
        '{"db":{"rules":[{"path":"seen","read":"admin","write":"owner"},'
        '{"path":"seen/{self}","read":"interact","write":"interact"}]},'
        '"user":{},"comments":{"composer_only":true}}\n'
    )
    json.loads(r.stdout)


def test_source_is_still_required_for_a_build():
    r = subprocess.run([sys.executable, str(MD2ARTIFACT)], capture_output=True, text=True, check=False)
    assert r.returncode == 2
    assert "source" in r.stderr


def test_help_documents_the_flag_and_tags():
    r = subprocess.run([sys.executable, str(MD2ARTIFACT), "--help"], capture_output=True, text=True, check=True)
    for word in ("--capabilities", "{judgement}", "{lower}", "```diff"):
        assert word in r.stdout
