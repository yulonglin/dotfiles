"""Guards md2artifact's ```diff passthrough.

A ```diff fence renders as a unified diff: coloured +/- rows that keep their
sign as text, styled hunk headers, old/new line numbers drawn from data
attributes, and one open <details> per file when the fence carries file
headers. It is a passthrough in the registry's sense, so it must emit the
fence body only as escaped text.
"""

from __future__ import annotations

import importlib.machinery
import importlib.util
import re
import sys
from pathlib import Path

import pytest

pytest.importorskip("markdown_it")

MD2ARTIFACT = Path(__file__).resolve().parent.parent / "custom_bins" / "md2artifact"


def _load():
    spec = importlib.util.spec_from_loader(
        "md2artifact_diff_cli",
        importlib.machinery.SourceFileLoader("md2artifact_diff_cli", str(MD2ARTIFACT)),
    )
    mod = importlib.util.module_from_spec(spec)
    sys.modules["md2artifact_diff_cli"] = mod
    spec.loader.exec_module(mod)
    return mod


md2 = _load()

TWO_FILES = """diff --git a/src/app.py b/src/app.py
index 1111111..2222222 100644
--- a/src/app.py
+++ b/src/app.py
@@ -10,3 +10,4 @@ def main():
     setup()
-    run()
+    run(fast=True)
+    report()
     teardown()
@@ -40,2 +41,2 @@
-x = 1
+x = 2
 y = 3
diff --git a/README.md b/README.md
new file mode 100644
--- /dev/null
+++ b/README.md
@@ -0,0 +1,2 @@
+# Title
+--- not a header, an added line
"""


def test_rows_carry_old_and_new_line_numbers():
    files = md2.parse_diff(TWO_FILES)
    rows = [r for r in files[0]["rows"] if r[0] in {"add", "del", "ctx"}]
    assert rows[:5] == [
        ("ctx", 10, 10, " ", "    setup()"),
        ("del", 11, None, "-", "    run()"),
        ("add", None, 11, "+", "    run(fast=True)"),
        ("add", None, 12, "+", "    report()"),
        ("ctx", 12, 13, " ", "    teardown()"),
    ]
    # The second hunk restarts numbering from its own header.
    assert rows[5] == ("del", 40, None, "-", "x = 1")
    assert rows[6] == ("add", None, 41, "+", "x = 2")


def test_split_per_file_and_paths_come_from_the_headers():
    files = md2.parse_diff(TWO_FILES)
    assert [md2._diff_file_name(f) for f in files] == ["src/app.py", "README.md"]


def test_a_counted_hunk_line_reading_like_a_header_stays_a_line():
    files = md2.parse_diff(TWO_FILES)
    assert len(files) == 2
    assert files[1]["rows"][-1] == ("add", None, 2, "+", "--- not a header, an added line")


def test_each_file_is_an_open_details_with_its_path():
    out = md2.diff_html(TWO_FILES)
    summaries = re.findall(r'<details class="diff-file" open><summary><code>([^<]*)</code>', out)
    assert summaries == ["src/app.py", "README.md"]
    assert out.count("</details>") == 2


def test_line_numbers_are_attributes_and_signs_are_text():
    out = md2.diff_html(TWO_FILES)
    assert '<span class="ln" data-n="11"></span><span class="ds">-</span>' not in out  # del has no new no.
    assert '<span class="dl dl-del"><span class="ln" data-n="11"></span><span class="ln"></span><span class="ds">-</span>' in out
    assert '<span class="dl dl-add"><span class="ln"></span><span class="ln" data-n="11"></span><span class="ds">+</span>' in out
    assert '<span class="dl dl-hunk">' in out
    assert '<span class="dl dl-meta">' in out  # the `index` line


def test_a_bare_snippet_without_headers_is_one_unnumbered_block():
    out = md2.diff_html("-old line\n+new line\n same\n")
    assert "<details" not in out
    assert 'data-n=' not in out
    assert '<span class="dl dl-del"><span class="ln"></span><span class="ln"></span><span class="ds">-</span><span class="dc">old line</span>' in out
    assert '<span class="dl dl-ctx">' in out


def test_rename_shows_both_paths():
    src = "diff --git a/old.py b/new.py\nsimilarity index 90%\nrename from old.py\nrename to new.py\n"
    assert md2._diff_file_name(md2.parse_diff(src)[0]) == "old.py → new.py"


def test_fence_body_is_escaped_never_markup():
    src = "```diff\n+</pre><script>alert(1)</script>\n-<img src=x onerror=alert(2)>\n```\n"
    out, _ = md2.render(src)
    assert "<script>alert" not in out
    assert "<img" not in out
    assert "&lt;/pre&gt;&lt;script&gt;alert(1)&lt;/script&gt;" in out


def test_a_path_with_markup_is_escaped_in_the_summary():
    src = "```diff\n--- a/<b>x</b>\n+++ b/<b>x</b>\n@@ -1 +1 @@\n-a\n+b\n```\n"
    out, _ = md2.render(src)
    assert "<b>x</b>" not in out
    assert "<code>&lt;b&gt;x&lt;/b&gt;</code>" in out


def test_other_fences_are_unchanged():
    out, _ = md2.render("```python\n+x = 1\n-y\n```\n")
    assert '<pre><code class="language-python">+x = 1\n-y\n</code></pre>' in out
    assert "diff-wrap" not in out
