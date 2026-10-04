#!/usr/bin/env python3
"""Add select-to-comment to a rendered debrief page.

The hive renderer leaves commenting to the claude.ai shell's comment mode, which
a reader has to switch on first. This appends a small script: select text and a
"Comment" button appears beside it, opening the shell's own composer on that
selection. The page must be published with `comments: {"composer_only": true}`
among its capabilities; without it the button never shows.

    add_comment_entry.py <page.html>      # edits in place; safe to re-run
"""

from __future__ import annotations

import sys
from pathlib import Path

MARKER = "<!-- debrief-comment-entry -->"

SNIPPET = MARKER + r"""
<style>
#dce-btn{position:absolute;z-index:2147483000;display:none;padding:4px 10px;border-radius:6px;
  border:1px solid #c9c6bd;background:#fffdf8;color:#1f1e1b;font:500 13px/1.4 system-ui,sans-serif;
  box-shadow:0 2px 8px rgba(0,0,0,.15);cursor:pointer}
@media (prefers-color-scheme:dark){#dce-btn{background:#2a2925;color:#f2efe6;border-color:#55524a}}
</style>
<button id="dce-btn" type="button" tabindex="-1" data-uncommentable>Comment</button>
<script>
(async function () {
  var btn = document.getElementById("dce-btn");
  var comments = null;
  try { comments = await window.claude.use("comments"); } catch (e) { comments = null; }
  if (!comments) { btn.remove(); return; }
  var range = null, timer = null, dead = false;
  function hide() { btn.style.display = "none"; range = null; }
  function place() {
    var sel = document.getSelection();
    if (dead || !sel || sel.isCollapsed || sel.rangeCount === 0) { hide(); return; }
    var r = sel.getRangeAt(0);
    if (btn.contains(r.commonAncestorContainer) || !String(sel).trim()) { hide(); return; }
    var rects = r.getClientRects();
    var last = rects.length ? rects[rects.length - 1] : r.getBoundingClientRect();
    range = r.cloneRange();
    btn.style.display = "block";
    var left = Math.min(last.right + window.scrollX + 6, window.scrollX + document.documentElement.clientWidth - btn.offsetWidth - 8);
    btn.style.left = Math.max(window.scrollX + 8, left) + "px";
    btn.style.top = (last.bottom + window.scrollY + 6) + "px";
  }
  // selectionchange, not mouseup: iOS fires no mouseup for a touch selection.
  document.addEventListener("selectionchange", function () { clearTimeout(timer); timer = setTimeout(place, 250); });
  // Keep the selection alive: pressing the button must not move focus or collapse it.
  btn.addEventListener("pointerdown", function (e) { e.preventDefault(); });
  btn.addEventListener("mousedown", function (e) { e.preventDefault(); });
  btn.addEventListener("click", async function () {
    if (!range) return;
    var target = range;
    hide();
    try {
      await comments.openComposer({ range: target });
    } catch (err) {
      if (err && err.code === "unavailable") { dead = true; btn.remove(); }
    }
  });
})();
</script>
"""


def main() -> int:
    if len(sys.argv) != 2 or sys.argv[1] in {"-h", "--help"}:
        print(__doc__.strip())
        return 0 if len(sys.argv) == 2 else 2
    page = Path(sys.argv[1])
    text = page.read_text(encoding="utf-8")
    if MARKER in text:
        return 0
    page.write_text(text.rstrip("\n") + "\n" + SNIPPET, encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
