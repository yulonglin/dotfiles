"""The md2review annotation layer, as one shared block of CSS + HTML + JS.

This is the single copy of the select-to-comment layer that
the `artifact-writing` skill requires on every reviewable page. Two
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
- once open, the note box is never closed by a selection event — only by
  Enter/Save, Escape/Cancel, or a click outside it. Nothing the browser does
  to the selection (including the focus that opening the box itself causes)
  can make the box flicker away;
- Enter saves, Shift+Enter is a newline, Escape discards; Save is the first
  and primary button, Delete is pushed away from it;
- stores comments in localStorage keyed by the page `<title>` (or an explicit
  `data-key` on the layer root), restores highlights on reload, and reopens a
  comment for edit/delete when its highlight is clicked;
- survives a forced refresh or a republish of the Artifact: every mutation is
  written through to localStorage *and* mirrored to IndexedDB, the half-typed
  note is autosaved as a draft and reopened, a rolling backup keeps the last
  non-empty state, and if the primary key comes back empty (which is what a
  retitled republish looks like) the layer recovers from the backup, from
  IndexedDB, or from a sibling key whose quotes still match this page;
- an end-of-page "Your comments" panel with Copy all (Markdown, `> quote`),
  Download .md, Export text (selectable textarea, since the Artifact viewer
  blocks page-initiated downloads), and Clear all with a confirm;
- a `beforeunload` guard while comments exist that have not been exported,
  which also snapshots and attempts the download on the way out;
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
/* Save leads: it is the first button in the DOM, so it is also first in tab
   order. Delete is pushed to the far end so it is never the near miss. */
.anrow{display:flex;gap:.4rem;align-items:center;margin-top:.45rem;flex-wrap:wrap}
#anDelete{margin-left:auto}
.anhint{color:var(--an-soft);font-size:.72rem;margin-top:.35rem}
.anhint kbd{font:inherit;font-size:.95em;border:1px solid var(--an-rule);border-bottom-width:2px;
 border-radius:4px;padding:0 .25rem;background:var(--an-field)}
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
<p class="anscope">Select any text on this page to attach a note, then press Enter. Notes are saved in this browser and survive a refresh or a republish of this page &mdash; copy or download them to keep them anywhere else.</p>
<div class="anbar">
  <span class="ancount" id="anCount">No comments yet</span>
  <button class="anbtn" id="anCopy">Copy all</button>
  <button class="anbtn ghost" id="anDownload">Download .md</button>
  <button class="anbtn ghost" id="anExportBtn">Export text</button>
  <button class="anbtn ghost danger" id="anClear">Clear all</button>
  <span id="anToast"></span>
</div>
<div id="anList"></div>
</section>
<div id="anPop" role="dialog" aria-label="Comment">
  <textarea id="anTxt" placeholder="What do you think?"></textarea>
  <div class="anrow">
    <button class="anbtn" id="anSave">Save</button>
    <button class="anbtn ghost" id="anCancel">Cancel</button>
    <button class="anbtn ghost danger" id="anDelete">Delete</button>
  </div>
  <div class="anhint"><kbd>Enter</kbd> saves &middot; <kbd>Shift</kbd>+<kbd>Enter</kbd> newline &middot; <kbd>Esc</kbd> discards</div>
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
var DRAFT = KEY + "-draft";
var BAK = KEY + "-bak";
var STORE_V = 2;

// ---- storage -------------------------------------------------------------
// localStorage is the primary store; IndexedDB mirrors it because the two are
// evicted under different conditions, and either alone can come back empty
// after a browser clears site data or the page is republished under a new
// title. Both are wrapped: any of them can throw (private windows, embedded
// previews, browsers set to block site data) and the page must still work.
function lsGet(k){ try { return localStorage.getItem(k); } catch (e) { return null; } }
function lsSet(k, v){ try { localStorage.setItem(k, v); return true; } catch (e) { return false; } }
function lsDel(k){ try { localStorage.removeItem(k); } catch (e) {} }

// Envelope {v, key, title, savedAt, comments}. A bare array is the older
// format and is still read, so existing pages keep their comments.
function pack(list){
  return JSON.stringify({ v: STORE_V, key: KEY, title: document.title, savedAt: Date.now(), comments: list });
}
function unpack(raw){
  if (!raw) return null;
  var d; try { d = JSON.parse(raw); } catch (e) { return null; }
  if (Array.isArray(d)) return { comments: d, savedAt: 0 };
  if (d && Array.isArray(d.comments)) return d;
  return null;
}
function idbOpen(cb){
  try {
    if (!window.indexedDB) return cb(null);
    var rq = indexedDB.open("anAnnotations", 1);
    rq.onupgradeneeded = function(){ try { rq.result.createObjectStore("kv"); } catch (e) {} };
    rq.onsuccess = function(){ cb(rq.result); };
    rq.onerror = function(){ cb(null); };
  } catch (e) { cb(null); }
}
function idbPut(k, v){
  idbOpen(function(db){
    if (!db) return;
    try { db.transaction("kv", "readwrite").objectStore("kv").put(v, k); } catch (e) {}
  });
}
function idbGet(k, cb){
  idbOpen(function(db){
    if (!db) return cb(null);
    try {
      var r = db.transaction("kv", "readonly").objectStore("kv").get(k);
      r.onsuccess = function(){ cb(r.result || null); };
      r.onerror = function(){ cb(null); };
    } catch (e) { cb(null); }
  });
}

var loaded = unpack(lsGet(KEY));
var comments = (loaded && loaded.comments) || [], dirty = false;
try { dirty = localStorage.getItem(DIRTY) === "1"; } catch (e) {}
var nextId = comments.reduce(function(m, c){ return Math.max(m, c.id || 0); }, 0) + 1;
comments.forEach(function(c){ if (!c.id) c.id = nextId++; });
var pop = $("anPop"), txt = $("anTxt"), badge = $("anBadge");
var pending = null, editingId = null;

// Written on the way out so a forced refresh cannot lose anything: the last
// non-empty state goes to the backup key, and the half-typed note to the draft.
function snapshot(){
  saveDraft();
  if (!comments.length) return;
  var blob = pack(comments);
  lsSet(BAK, blob); idbPut(BAK, blob);
}
window.addEventListener("pagehide", snapshot);
document.addEventListener("visibilitychange", function(){
  if (document.visibilityState === "hidden") snapshot();
});
window.addEventListener("beforeunload", function(e){
  snapshot();
  if (!dirty || !comments.length) return;
  // Works in an ordinary tab; the Artifact viewer blocks page-initiated
  // downloads, which is why the confirm below and the stored copy both stay.
  tryDownload();
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
function isOpen(){ return pop.style.display === "block"; }
// `rect` is viewport-relative. Measure the box while it is laid out but not
// yet painted, so it never appears at the wrong place for one frame — that
// single-frame jump is itself a flicker.
function placePop(rect){
  pop.style.visibility = "hidden";
  pop.style.display = "block";
  var w = pop.offsetWidth, h = pop.offsetHeight;
  var vw = document.documentElement.clientWidth, vh = document.documentElement.clientHeight;
  var top = rect.bottom + 8;
  if (top + h > vh - 8) top = Math.max(8, rect.top - h - 8);
  pop.style.left = (Math.max(8, Math.min(rect.left, vw - w - 12)) + window.scrollX) + "px";
  pop.style.top = (top + window.scrollY) + "px";
  pop.style.visibility = "";
}
function openEdit(c, anchor){
  editingId = c.id; pending = null; txt.value = c.note;
  pop.classList.add("editing");
  placePop(anchor ? anchor.getBoundingClientRect() : { left: 16, top: 100, bottom: 100 });
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
//
// This function only ever OPENS. Nothing about the selection closes the box —
// that asymmetry is the whole flicker fix. Opening the box focuses the
// textarea, focusing collapses the document selection, and the old code read
// that collapse back as "the user deselected" and closed the box it had just
// opened. The box now closes only on Save, Cancel/Escape, or a click outside.
function openForSelection(autofocus){
  if (editingId !== null) return false;
  var sel = window.getSelection();
  if (!sel || sel.rangeCount === 0 || sel.isCollapsed) return false;
  var text = sel.toString().trim();
  if (!text) return false;
  if (inLayer(sel.anchorNode) || inLayer(sel.focusNode)) return false;
  // Already open on this exact selection: do not wipe a half-typed note.
  if (pending && pending.quote === text && isOpen()) return true;
  // Open on some other selection with a note already typed: leave it be
  // rather than throwing away words the user has not saved.
  if (isOpen() && txt.value.trim()) return true;
  var range = sel.getRangeAt(0), rect = range.getBoundingClientRect();
  editingId = null; pop.classList.remove("editing");
  pending = { quote: text, where: sectionOf(sel.anchorNode), range: range.cloneRange() };
  placePop(rect);
  txt.value = "";
  if (autofocus) txt.focus();
  return true;
}
document.addEventListener("mouseup", function(ev){
  if (pop.contains(ev.target)) return;
  if (ev.target.closest && ev.target.closest("mark.note")) return;
  clearTimeout(selTimer);
  // A tick later, so the selection the browser reports is the settled one.
  setTimeout(function(){ openForSelection(true); }, 0);
});
// A press outside the box dismisses it — the one gesture that may close it.
// A note already typed is kept rather than dropped on the floor.
document.addEventListener("mousedown", function(ev){
  if (!isOpen() || pop.contains(ev.target)) return;
  if (ev.target.closest && ev.target.closest("mark.note")) return;
  if (txt.value.trim()) save(); else closePop();
});
// iOS Safari fires no mouseup for a touch selection drag, so a mouseup-only
// handler makes the page uncommentable on iPhone and iPad. selectionchange
// fires on every platform; debounce it so it runs once the selection settles.
var selTimer = null;
document.addEventListener("selectionchange", function(){
  if (document.activeElement === txt) return;
  if (editingId !== null) return;
  if (isOpen() && txt.value.trim()) return;
  clearTimeout(selTimer);
  selTimer = setTimeout(function(){ openForSelection(false); }, 250);
});

txt.addEventListener("keydown", function(ev){
  if (ev.key === "Enter" && !ev.shiftKey && !ev.altKey && !ev.isComposing) { ev.preventDefault(); save(); }
  else if (ev.key === "Escape") { ev.preventDefault(); discard(); }
});
txt.addEventListener("input", saveDraft);
document.addEventListener("keydown", function(ev){
  if (ev.key === "Escape" && isOpen() && document.activeElement !== txt) discard();
});

function closePop(){
  pop.style.display = "none"; pending = null; editingId = null;
  pop.classList.remove("editing"); txt.value = ""; lsDel(DRAFT);
}
function discard(){ closePop(); }
// The in-progress note, saved on every keystroke, so a forced refresh reopens
// the box where it was instead of losing what was typed into it.
function saveDraft(){
  if (!isOpen() || !txt.value.trim()) { lsDel(DRAFT); return; }
  lsSet(DRAFT, JSON.stringify({
    note: txt.value, editingId: editingId,
    quote: pending ? pending.quote : null, where: pending ? pending.where : null
  }));
}
function restoreDraft(){
  var d = unpackDraft();
  if (!d) return;
  if (d.editingId != null) {
    var c = comments.find(function(x){ return x.id === d.editingId; });
    if (!c) return;
    openEdit(c, document.querySelector('mark.note[data-cid="' + c.id + '"]'));
    txt.value = d.note;
    return;
  }
  var r = rangeForQuote(d.quote);
  if (!r) return;
  var sel = window.getSelection();
  if (sel) { try { sel.removeAllRanges(); sel.addRange(r); } catch (e) {} }
  editingId = null; pop.classList.remove("editing");
  pending = { quote: d.quote, where: d.where || sectionOf(r.startContainer), range: r.cloneRange() };
  placePop(r.getBoundingClientRect());
  txt.value = d.note;
}
function unpackDraft(){
  var d = null; try { d = JSON.parse(lsGet(DRAFT) || "null"); } catch (e) {}
  return d && typeof d.note === "string" && d.note.trim() ? d : null;
}
function markDirty(){ dirty = true; lsSet(DIRTY, "1"); }
function markClean(){ dirty = false; lsSet(DIRTY, "0"); }
// Write-through to both stores on every mutation. The backup key keeps the
// last non-empty state, so an accidental Clear all is still recoverable.
function persist(){
  var blob = pack(comments);
  lsSet(KEY, blob); idbPut(KEY, blob);
  if (comments.length) { lsSet(BAK, blob); idbPut(BAK, blob); }
}
function unwrap(id){
  var m = document.querySelector('mark.note[data-cid="' + id + '"]');
  if (m) { while (m.firstChild) m.parentNode.insertBefore(m.firstChild, m); m.remove(); }
}

function save(){
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
  var sel = window.getSelection(); if (sel) sel.removeAllRanges();
}

$("anCancel").onclick = discard;
$("anDelete").onclick = function(){
  if (editingId === null) { closePop(); return; }
  comments = comments.filter(function(c){ return c.id !== editingId; });
  unwrap(editingId);
  markDirty(); persist(); render(); closePop();
};
$("anSave").onclick = save;

// Builds into a fragment and swaps once, so the list never blanks between
// clearing and refilling.
function render(){
  var list = $("anList"), count = $("anCount");
  badge.textContent = "\uD83D\uDCAC " + comments.length;
  badge.className = dirty && comments.length ? "warn" : "";
  if (!comments.length) {
    count.textContent = "No comments yet"; count.className = "ancount";
    var empty = document.createElement("p");
    empty.className = "anscope"; empty.textContent = "Select any text above to comment.";
    list.replaceChildren(empty);
    return;
  }
  count.textContent = comments.length + (comments.length === 1 ? " comment" : " comments") + (dirty ? " \u2014 not yet exported" : " \u2014 exported");
  count.className = "ancount" + (dirty ? " warn" : "");
  var frag = document.createDocumentFragment();
  comments.forEach(function(c){
    var d = document.createElement("div"); d.className = "cmt";
    var w = document.createElement("div"); w.className = "where"; w.textContent = c.where;
    var q = document.createElement("div"); q.className = "q"; q.textContent = "\u201C" + c.quote + "\u201D";
    var n = document.createElement("div"); n.textContent = c.note;
    var a = document.createElement("button"); a.className = "anbtn ghost tiny"; a.textContent = "edit";
    a.onclick = function(){
      var m = document.querySelector('mark.note[data-cid="' + c.id + '"]');
      if (m) { m.scrollIntoView({ block: "center" }); m.click(); }
      else openEdit(c, null);
    };
    d.append(w, q, n);
    if (!hasMark(c)) { var o = document.createElement("div"); o.className = "orphan"; o.textContent = "quoted text not found on this version of the page"; d.append(o); }
    d.append(a); frag.appendChild(d);
  });
  list.replaceChildren(frag);
}

function markdown(){
  return comments.map(function(c){
    return "- **" + c.where + "** \u2014 " + c.note + "\n  > " + c.quote.replace(/\n/g, "\n  > ");
  }).join("\n");
}
function exportText(){ return "# Comments \u2014 " + document.title + "\n\n" + markdown() + "\n"; }
function toast(html, ms){ var t = $("anToast"); t.innerHTML = html; setTimeout(function(){ t.innerHTML = ""; }, ms || 1800); }
// Saves the comments as a .md file. Works in an ordinary browser tab; the
// Artifact viewer sandboxes the page without download permission and swallows
// the click, which is why Copy all and Export text stay the reliable paths.
function tryDownload(){
  if (!comments.length) return false;
  try {
    var url = URL.createObjectURL(new Blob([exportText()], { type: "text/markdown" }));
    var a = document.createElement("a");
    a.href = url;
    a.download = (document.title || "comments").replace(/[^\w.-]+/g, "-").replace(/^-|-$/g, "") + "-comments.md";
    document.body.appendChild(a); a.click(); a.remove();
    setTimeout(function(){ URL.revokeObjectURL(url); }, 5000);
    return true;
  } catch (e) { return false; }
}

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
$("anDownload").onclick = function(){
  if (!comments.length) { toast('<span class="anok">nothing to download</span>', 1600); return; }
  if (tryDownload()) { markClean(); render(); toast('<span class="anok">saved ' + comments.length + ' as .md</span>'); }
  else $("anExportBtn").click();
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

// ---- recovery ------------------------------------------------------------
// A republish under a new title, or a browser that dropped localStorage,
// leaves the primary key empty while the comments still exist somewhere.
// Look, in order: this page's backup key, other keys on this origin whose
// quotes still match this page, then the IndexedDB mirror of both.
function adopt(list, why){
  if (!list || !list.length || comments.length) return false;
  comments = list;
  nextId = comments.reduce(function(m, c){ return Math.max(m, c.id || 0); }, 0) + 1;
  comments.forEach(function(c){ if (!c.id) c.id = nextId++; });
  markDirty(); persist(); restoreHighlights(); render();
  toast('<span class="anok">' + why + '</span>', 5000);
  return true;
}
// A sibling key is only this document's if some quote of it is still on the
// page — otherwise it belongs to another document sharing the origin, which
// is what several review pages opened from file:// look like.
function quotesMatchPage(list){
  for (var i = 0; i < list.length; i++) if (rangeForQuote(list[i].quote)) return true;
  return false;
}
function siblingComments(){
  var found = [];
  try {
    for (var i = 0; i < localStorage.length; i++) {
      var k = localStorage.key(i);
      if (!k || k === KEY || k === BAK) continue;
      if (!/^(annot:|review-)/.test(k) || /-(dirty|draft|bak)$/.test(k)) continue;
      var d = unpack(localStorage.getItem(k));
      if (d && d.comments.length) found.push(d);
    }
  } catch (e) {}
  found.sort(function(a, b){ return (b.savedAt || 0) - (a.savedAt || 0); });
  for (var j = 0; j < found.length; j++) if (quotesMatchPage(found[j].comments)) return found[j].comments;
  return null;
}
function recover(){
  if (comments.length) return;
  var own = unpack(lsGet(BAK));
  if (own && adopt(own.comments, "restored " + own.comments.length + " comments from backup")) return;
  var sib = siblingComments();
  if (sib && adopt(sib, "recovered " + sib.length + " comments from an earlier version of this page")) return;
  idbGet(KEY, function(v){
    var d = unpack(v);
    if (d && adopt(d.comments, "restored " + d.comments.length + " comments from backup storage")) return;
    idbGet(BAK, function(v2){
      var d2 = unpack(v2);
      if (d2) adopt(d2.comments, "restored " + d2.comments.length + " comments from backup storage");
    });
  });
}

restoreHighlights();
render();
recover();
restoreDraft();
})();
"""
