"""The md2review annotation layer, as one shared block of CSS + HTML + JS.

This is the single copy of the select-to-comment layer that
`rules/artifact-first-replies.md` requires on every reviewable page. Two
callers use it:

- `md2review` renders Markdown into a page and appends the layer.
- `annotate-html` injects the layer into any existing HTML page (an Artifact
  built by hand, a report from another tool), which is what the
  `block_unannotated_artifact.sh` hook checks for before a publish.

The layer is self-contained: its CSS defines its own `--an-*` tokens, switched
by `prefers-color-scheme` and `[data-theme]`, so it never depends on the host
page's variables. It fetches nothing. Every element id and class is prefixed
`an` so it cannot collide with the host page.

Behaviour, all of which the tests guard:

- opens the note box from a debounced `selectionchange` (iOS fires no
  `mouseup` for a touch drag) as well as from `mouseup`;
- does not steal focus on the touch path (focusing while iOS shows selection
  handles collapses the selection);
- stores comments in localStorage keyed by the page `<title>` (or an explicit
  `data-key` on the layer root), restores highlights on reload, and reopens a
  comment for edit/delete when its highlight is clicked;
- an end-of-page "Your comments" panel with Copy all (Markdown, `> quote`),
  Export text (selectable textarea, since the Artifact viewer blocks
  page-initiated downloads), and Clear all with a confirm;
- a `beforeunload` guard while comments exist that have not been exported;
- a fixed count badge that jumps to the panel.
"""

from __future__ import annotations

import json
import re

LAYER_VERSION = "v1"
MARKER_OPEN = f"<!-- annotation-layer {LAYER_VERSION} -->"
MARKER_CLOSE = "<!-- /annotation-layer -->"
ROOT_ATTR = "data-annotation-layer"

# Accepts this module's marker and the earlier hand-ported spelling
# (`<!-- annotation-layer -->`, no version) so pages patched before the CLI
# existed are recognised rather than double-injected.
_PRESENT_RE = re.compile(
    r"<!--\s*annotation-layer(\s+v\d+)?\s*-->|" + re.escape(ROOT_ATTR) + r"=",
)
_BLOCK_RE = re.compile(
    re.escape(MARKER_OPEN) + r".*?" + re.escape(MARKER_CLOSE) + r"\n?", re.S
)
_BODY_CLOSE_RE = re.compile(r"</body\s*>", re.I)


def has_layer(page: str) -> bool:
    """Whether the page already carries an annotation layer of any version."""
    return _PRESENT_RE.search(page) is not None


def strip_layer(page: str) -> str:
    """Remove a layer injected by this module (older hand ports are left alone)."""
    return _BLOCK_RE.sub("", page)


def layer_html(key: str | None = None) -> str:
    """The complete layer block, markers included.

    `key` fixes the localStorage key; when None the page's `<title>` is used at
    runtime, so republishing under the same title keeps the comments.
    """
    key_attr = f' data-key="{_attr(key)}"' if key else ""
    return (
        f"{MARKER_OPEN}\n<style>{CSS}</style>\n"
        f'<div {ROOT_ATTR}="{LAYER_VERSION}"{key_attr}>{HTML}</div>\n'
        f"<script>{JS}</script>\n{MARKER_CLOSE}\n"
    )


def inject(page: str, key: str | None = None) -> str:
    """Return the page with the layer added before `</body>`, else appended.

    Artifact files carry no `<body>` tag (the viewer wraps them), so the
    append path is the common one.
    """
    block = layer_html(key)
    matches = list(_BODY_CLOSE_RE.finditer(page))
    if matches:
        at = matches[-1].start()
        return page[:at] + block + page[at:]
    sep = "" if page.endswith("\n") or not page else "\n"
    return page + sep + block


def _attr(value: str) -> str:
    return json.dumps(value)[1:-1].replace('"', "&quot;")


CSS = r"""
:root{--an-bg:#fff;--an-ink:#1a1a1a;--an-soft:#5d5a55;--an-rule:#d9d4cc;--an-accent:#bd5d3a;
 --an-mark:#fbe6a2;--an-bad:#a33f2a;--an-good:#2f6b4f;--an-good-bg:#e4f0e9;--an-field:#faf9f7}
@media (prefers-color-scheme: dark){:root:not([data-theme="light"]){--an-bg:#1f2124;--an-ink:#eceae6;
 --an-soft:#a9a59e;--an-rule:#3a3d42;--an-accent:#e08a63;--an-mark:#5c4a15;--an-bad:#e08a75;
 --an-good:#7fc39c;--an-good-bg:#1d2b24;--an-field:#17181a}}
:root[data-theme="dark"]{--an-bg:#1f2124;--an-ink:#eceae6;--an-soft:#a9a59e;--an-rule:#3a3d42;
 --an-accent:#e08a63;--an-mark:#5c4a15;--an-bad:#e08a75;--an-good:#7fc39c;--an-good-bg:#1d2b24;--an-field:#17181a}
mark.note{background:var(--an-mark);color:inherit;border-bottom:2px solid var(--an-accent);cursor:pointer;border-radius:2px}
[data-annotation-layer]{font-family:ui-sans-serif,-apple-system,"Segoe UI",sans-serif;color:var(--an-ink);line-height:1.5}
[data-annotation-layer] *{box-sizing:border-box}
#anPop{position:absolute;z-index:1050;display:none;background:var(--an-bg);border:1px solid var(--an-rule);
 border-radius:8px;box-shadow:0 6px 22px rgba(0,0,0,.18);padding:.6rem;width:min(20rem,calc(100vw - 1.5rem))}
/* iOS zooms the whole page when a focused field is under 16px. */
@media (pointer:coarse){#anPop textarea,#anExportText{font-size:16px}}
#anPop textarea{width:100%;min-height:4.5rem;border:1px solid var(--an-rule);border-radius:5px;
 background:var(--an-field);color:var(--an-ink);padding:.4rem;font:inherit;font-size:.86rem;resize:vertical}
.anbtn{background:var(--an-accent);color:#fff;border:0;border-radius:5px;padding:.35rem .8rem;
 font:inherit;font-size:.84rem;font-weight:600;cursor:pointer}
.anbtn.ghost{background:transparent;color:var(--an-soft);border:1px solid var(--an-rule)}
.anbtn.ghost.danger{color:var(--an-bad);border-color:var(--an-bad)}
.anbtn.tiny{padding:.12rem .5rem;font-size:.76rem;margin-top:.4rem}
#anPop:not(.editing) #anDelete{display:none}
.anrow{display:flex;gap:.4rem;justify-content:flex-end;margin-top:.45rem;flex-wrap:wrap}
#anComments{max-width:48rem;margin:3rem auto 5rem;padding:0 1rem}
#anComments h2{font-size:1.2rem;margin:0 0 .5rem;padding-bottom:.32rem;border-bottom:1px solid var(--an-rule)}
#anComments .anscope{color:var(--an-soft);font-size:.86rem;margin:0 0 .6rem}
.anbar{display:flex;gap:.5rem;align-items:center;flex-wrap:wrap;margin:.5rem 0 1rem}
.ancount{color:var(--an-soft);font-size:.87rem}
.ancount.warn{color:var(--an-bad);font-weight:650}
.cmt{background:var(--an-bg);border:1px solid var(--an-rule);border-left:3px solid var(--an-accent);
 border-radius:0 7px 7px 0;padding:.6rem .8rem;margin:.5rem 0;font-size:.88rem;overflow-wrap:anywhere}
.cmt .q{color:var(--an-soft);font-style:italic;margin-bottom:.3rem}
.cmt .where{font-size:.72rem;color:var(--an-soft);text-transform:uppercase;letter-spacing:.06em}
.cmt .orphan{font-size:.74rem;color:var(--an-bad)}
#anExport{display:none;position:fixed;left:50%;top:50%;transform:translate(-50%,-50%);z-index:1060;
 background:var(--an-bg);border:1px solid var(--an-rule);border-radius:10px;padding:.9rem;
 width:min(46rem,92vw);box-shadow:0 12px 40px rgba(0,0,0,.3)}
#anExport .exphead{display:flex;align-items:center;gap:.6rem;margin-bottom:.5rem;font-size:.9rem;flex-wrap:wrap}
#anExport .exphint{color:var(--an-soft);font-size:.8rem}
#anExport .anbtn{margin-left:auto}
#anExportText{width:100%;height:min(24rem,55vh);border:1px solid var(--an-rule);border-radius:6px;
 background:var(--an-field);color:var(--an-ink);padding:.6rem;font-family:ui-monospace,Menlo,monospace;
 font-size:.82rem;resize:vertical}
.anok{background:var(--an-good-bg);color:var(--an-good);padding:.2rem .55rem;border-radius:5px;font-size:.83rem}
#anBadge{position:fixed;right:calc(.9rem + env(safe-area-inset-right,0px));
 bottom:calc(.9rem + env(safe-area-inset-bottom,0px));z-index:1045;background:var(--an-bg);color:var(--an-ink);
 border:1px solid var(--an-rule);border-radius:999px;padding:.4rem .8rem;font:inherit;font-size:.85rem;
 font-weight:600;box-shadow:0 4px 14px rgba(0,0,0,.18);cursor:pointer}
#anBadge.warn{border-color:var(--an-bad);color:var(--an-bad)}
"""

HTML = r"""
<section id="anComments">
<h2 id="your-comments">Your comments</h2>
<p class="anscope">Select any text on this page to attach a note. Notes live in this browser's localStorage until you copy or export them.</p>
<div class="anbar">
  <span class="ancount" id="anCount">No comments yet</span>
  <button class="anbtn" id="anCopy">Copy all</button>
  <button class="anbtn ghost" id="anExportBtn">Export text</button>
  <button class="anbtn ghost danger" id="anClear">Clear all</button>
  <span id="anToast"></span>
</div>
<div id="anList"></div>
</section>
<div id="anPop" role="dialog" aria-label="Comment">
  <textarea id="anTxt" placeholder="What do you think?"></textarea>
  <div class="anrow">
    <button class="anbtn ghost danger" id="anDelete">Delete</button>
    <button class="anbtn ghost" id="anCancel">Cancel</button>
    <button class="anbtn" id="anSave">Save</button>
  </div>
</div>
<div id="anExport" role="dialog" aria-label="Export comments">
  <div class="exphead">
    <strong>Your comments as Markdown</strong>
    <span class="exphint">already selected &mdash; copy with your usual shortcut</span>
    <button class="anbtn ghost tiny" id="anExportClose">Close</button>
  </div>
  <textarea id="anExportText" readonly></textarea>
</div>
<button id="anBadge" type="button" aria-label="Jump to your comments">&#128172; 0</button>
"""

JS = r"""
(function(){
"use strict";
var $ = function(id){ return document.getElementById(id); };
var root = document.querySelector("[data-annotation-layer]");
var KEY = (root && root.dataset.key) || ("annot:" + document.title);
var DIRTY = KEY + "-dirty";
var comments = [], dirty = false;
try { comments = JSON.parse(localStorage.getItem(KEY) || "[]"); } catch (e) { comments = []; }
try { dirty = localStorage.getItem(DIRTY) === "1"; } catch (e) {}
var nextId = comments.reduce(function(m, c){ return Math.max(m, c.id || 0); }, 0) + 1;
comments.forEach(function(c){ if (!c.id) c.id = nextId++; });
var pop = $("anPop"), txt = $("anTxt"), badge = $("anBadge");
var pending = null, editingId = null;

window.addEventListener("beforeunload", function(e){
  if (!dirty || !comments.length) return;
  e.preventDefault(); e.returnValue = ""; return "";
});

function inLayer(node){
  while (node && node.nodeType === 3) node = node.parentNode;
  return !!(node && node.closest && node.closest("[data-annotation-layer]"));
}
function sectionOf(node){
  while (node && node.nodeType === 3) node = node.parentNode;
  var sec = node && node.closest ? node.closest("section") : null;
  if (sec) { var h = sec.querySelector("h1,h2,h3"); if (h) return h.textContent.trim(); }
  while (node && node !== document.body) {
    var p = node.previousElementSibling;
    while (p) { if (/^H[1-3]$/.test(p.tagName)) return p.textContent.trim(); p = p.previousElementSibling; }
    node = node.parentNode;
  }
  return "document";
}
function placePop(top, left){
  pop.style.display = "block";
  pop.style.top = top + "px";
  pop.style.left = Math.max(8, Math.min(left, window.scrollX + document.documentElement.clientWidth - pop.offsetWidth - 12)) + "px";
}
function openEdit(c, anchor){
  editingId = c.id; pending = null; txt.value = c.note;
  pop.classList.add("editing");
  if (anchor) { var r = anchor.getBoundingClientRect(); placePop(window.scrollY + r.bottom + 8, window.scrollX + r.left); }
  else placePop(window.scrollY + 120, 16);
  txt.focus();
}
document.addEventListener("click", function(ev){
  var m = ev.target.closest && ev.target.closest("mark.note");
  if (!m || pop.contains(ev.target)) return;
  var c = comments.find(function(x){ return x.id === Number(m.dataset.cid); });
  if (!c) return;
  ev.preventDefault(); openEdit(c, m);
});

// Wraps a range in a highlight. surroundContents refuses a range that crosses
// element boundaries, so fall back to lifting the contents out and wrapping.
function wrapRange(range, id, note){
  var m = document.createElement("mark");
  m.className = "note"; m.title = note; m.dataset.cid = String(id);
  try { range.surroundContents(m); }
  catch (e) { m.appendChild(range.extractContents()); range.insertNode(m); }
  return m;
}
// Every text node of the page, skipping the layer's own UI and existing highlights.
function docTextNodes(){
  var host = document.querySelector(".doc") || document.querySelector("main") || document.body;
  var walker = document.createTreeWalker(host, NodeFilter.SHOW_TEXT, { acceptNode: function(n){
    var p = n.parentNode;
    if (!p || !p.closest) return NodeFilter.FILTER_ACCEPT;
    if (p.closest("mark.note") || p.closest("[data-annotation-layer]") || p.closest("script,style")) return NodeFilter.FILTER_REJECT;
    return NodeFilter.FILTER_ACCEPT;
  }});
  var out = [], n;
  while ((n = walker.nextNode())) out.push(n);
  return out;
}
// Collapses runs of whitespace to one space, and records where each kept
// character sits in the raw text, so a match can be mapped back to real nodes.
function collapsedIndex(nodes){
  var norm = "", rawAt = [], raw = 0, lastWasSpace = false;
  for (var k = 0; k < nodes.length; k++) {
    var v = nodes[k].nodeValue;
    for (var i = 0; i < v.length; i++, raw++) {
      var isSpace = /\s/.test(v[i]);
      if (isSpace && lastWasSpace) continue;
      norm += isSpace ? " " : v[i];
      rawAt.push(raw);
      lastWasSpace = isSpace;
    }
  }
  return { norm: norm, rawAt: rawAt };
}
// Finds a stored quote again after a reload. Selection.toString() gives
// rendered text, where a newline inside a paragraph reads as a single space,
// so the comparison has to collapse whitespace.
function rangeForQuote(quote){
  if (!quote) return null;
  var nodes = docTextNodes();
  if (!nodes.length) return null;
  var starts = [], raw = 0;
  for (var k = 0; k < nodes.length; k++) { starts.push(raw); raw += nodes[k].nodeValue.length; }
  var idx = collapsedIndex(nodes);
  var needle = quote.replace(/\s+/g, " ").trim();
  if (!needle) return null;
  var at = idx.norm.indexOf(needle);
  if (at < 0) return null;
  var rawFrom = idx.rawAt[at], rawTo = idx.rawAt[at + needle.length - 1] + 1;
  function locate(offset, isEnd){
    for (var j = 0; j < nodes.length; j++) {
      var base = starts[j], end = base + nodes[j].nodeValue.length;
      if (isEnd ? (offset > base && offset <= end) : (offset >= base && offset < end)) return [nodes[j], offset - base];
    }
    return null;
  }
  var s = locate(rawFrom, false), f = locate(rawTo, true);
  if (!s || !f) return null;
  var r = document.createRange(); r.setStart(s[0], s[1]); r.setEnd(f[0], f[1]);
  return r;
}
// A reload rebuilds the DOM, so saved highlights are gone while the comments
// survive in localStorage. Put the marks back, or a comment cannot be clicked
// open to edit or delete. Quotes no longer on the page stay listed as orphans.
function restoreHighlights(){
  var missed = 0;
  comments.forEach(function(c){
    if (document.querySelector('mark.note[data-cid="' + c.id + '"]')) return;
    var r = rangeForQuote(c.quote);
    if (!r) { missed++; return; }
    try { wrapRange(r, c.id, c.note); } catch (e) { missed++; }
  });
  return missed;
}
function hasMark(c){ return !!document.querySelector('mark.note[data-cid="' + c.id + '"]'); }

// Opens the note box for the current selection. autofocus is false on touch:
// focusing a textarea while iOS is showing its selection handles collapses the
// selection before the user has typed anything.
function openForSelection(autofocus){
  var sel = window.getSelection();
  if (!sel || sel.rangeCount === 0 || sel.isCollapsed) return false;
  var text = sel.toString().trim();
  if (!text) return false;
  if (inLayer(sel.anchorNode) || inLayer(sel.focusNode)) return false;
  // Already open on this exact selection: do not wipe a half-typed note.
  if (pending && pending.quote === text && pop.style.display === "block") return true;
  var range = sel.getRangeAt(0), rect = range.getBoundingClientRect();
  editingId = null; pop.classList.remove("editing");
  pending = { quote: text, where: sectionOf(sel.anchorNode), range: range.cloneRange() };
  placePop(window.scrollY + rect.bottom + 8, window.scrollX + rect.left);
  txt.value = "";
  if (autofocus) txt.focus();
  return true;
}
document.addEventListener("mouseup", function(ev){
  if (pop.contains(ev.target)) return;
  if (ev.target.closest && ev.target.closest("mark.note")) return;
  if (openForSelection(true)) return;
  var sel = window.getSelection();
  if (!sel || !sel.toString().trim()) pop.style.display = "none";
});
// iOS Safari fires no mouseup for a touch selection drag, so a mouseup-only
// handler makes the page uncommentable on iPhone and iPad. selectionchange
// fires on every platform; debounce it so it runs once the selection settles.
var selTimer = null;
document.addEventListener("selectionchange", function(){
  if (document.activeElement === txt) return;
  if (editingId !== null) return;
  clearTimeout(selTimer);
  selTimer = setTimeout(function(){
    if (openForSelection(false)) return;
    if (editingId === null && !txt.value.trim()) closePop();
  }, 350);
});

function closePop(){ pop.style.display = "none"; pending = null; editingId = null; pop.classList.remove("editing"); }
function markDirty(){ dirty = true; try { localStorage.setItem(DIRTY, "1"); } catch (e) {} }
function markClean(){ dirty = false; try { localStorage.setItem(DIRTY, "0"); } catch (e) {} }
function persist(){ try { localStorage.setItem(KEY, JSON.stringify(comments)); } catch (e) {} }
function unwrap(id){
  var m = document.querySelector('mark.note[data-cid="' + id + '"]');
  if (m) { while (m.firstChild) m.parentNode.insertBefore(m.firstChild, m); m.remove(); }
}

$("anCancel").onclick = closePop;
$("anDelete").onclick = function(){
  if (editingId === null) { closePop(); return; }
  comments = comments.filter(function(c){ return c.id !== editingId; });
  unwrap(editingId);
  markDirty(); persist(); render(); closePop();
};
$("anSave").onclick = function(){
  var note = txt.value.trim();
  if (!note) { closePop(); return; }
  if (editingId !== null) {
    var c = comments.find(function(x){ return x.id === editingId; });
    if (c) c.note = note;
    var m = document.querySelector('mark.note[data-cid="' + editingId + '"]');
    if (m) m.title = note;
  } else if (pending) {
    var id = nextId++;
    try { wrapRange(pending.range, id, note); } catch (e) {}
    comments.push({ id: id, where: pending.where, quote: pending.quote, note: note });
  }
  markDirty(); persist(); render(); closePop();
  window.getSelection().removeAllRanges();
};

function render(){
  var list = $("anList"), count = $("anCount");
  list.innerHTML = "";
  badge.textContent = "💬 " + comments.length;
  badge.className = dirty && comments.length ? "warn" : "";
  if (!comments.length) {
    count.textContent = "No comments yet"; count.className = "ancount";
    list.innerHTML = '<p class="anscope">Select any text above to comment.</p>';
    return;
  }
  count.textContent = comments.length + (comments.length === 1 ? " comment" : " comments") + (dirty ? " — not yet exported" : " — exported");
  count.className = "ancount" + (dirty ? " warn" : "");
  comments.forEach(function(c){
    var d = document.createElement("div"); d.className = "cmt";
    var w = document.createElement("div"); w.className = "where"; w.textContent = c.where;
    var q = document.createElement("div"); q.className = "q"; q.textContent = "“" + c.quote + "”";
    var n = document.createElement("div"); n.textContent = c.note;
    var a = document.createElement("button"); a.className = "anbtn ghost tiny"; a.textContent = "edit";
    a.onclick = function(){
      var m = document.querySelector('mark.note[data-cid="' + c.id + '"]');
      if (m) { m.scrollIntoView({ block: "center" }); m.click(); }
      else openEdit(c, null);
    };
    d.append(w, q, n);
    if (!hasMark(c)) { var o = document.createElement("div"); o.className = "orphan"; o.textContent = "quoted text not found on this version of the page"; d.append(o); }
    d.append(a); list.appendChild(d);
  });
}

function markdown(){
  return comments.map(function(c){
    return "- **" + c.where + "** — " + c.note + "\n  > " + c.quote.replace(/\n/g, "\n  > ");
  }).join("\n");
}
function exportText(){ return "# Comments — " + document.title + "\n\n" + markdown() + "\n"; }
function toast(html, ms){ var t = $("anToast"); t.innerHTML = html; setTimeout(function(){ t.innerHTML = ""; }, ms || 1800); }

$("anCopy").onclick = async function(){
  if (!comments.length) { toast('<span class="anok">nothing to copy</span>', 1600); return; }
  try { await navigator.clipboard.writeText(exportText()); }
  catch (e) {
    var ta = document.createElement("textarea");
    ta.value = exportText(); document.body.appendChild(ta); ta.select();
    try { document.execCommand("copy"); } catch (e2) {}
    ta.remove();
  }
  markClean(); render();
  toast('<span class="anok">copied ' + comments.length + '</span>');
};
// The Artifact viewer blocks any page-initiated file save, so the export that
// always works is a selectable textarea.
$("anExportBtn").onclick = function(){
  if (!comments.length) { toast('<span class="anok">nothing to export</span>', 1600); return; }
  var ta = $("anExportText"); ta.value = exportText();
  $("anExport").style.display = "block";
  ta.focus(); ta.select();
  markClean(); render();
};
$("anExportClose").onclick = function(){ $("anExport").style.display = "none"; };
$("anClear").onclick = function(){
  if (!comments.length) return;
  if (dirty && !window.confirm("These " + comments.length + " comments have not been copied or exported yet. Delete anyway?")) return;
  if (!dirty && !window.confirm("Delete all " + comments.length + " comments?")) return;
  comments.slice().forEach(function(c){ unwrap(c.id); });
  comments = []; markClean(); persist(); render();
};
badge.onclick = function(){ $("anComments").scrollIntoView({ behavior: "smooth", block: "start" }); };

restoreHighlights();
render();
})();
"""
