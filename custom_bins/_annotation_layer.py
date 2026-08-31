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
  Enter/Save, Escape/Cancel, or a press outside it while it is still empty.
  Nothing the browser does to the selection (including the focus that opening
  the box itself causes) can make the box flicker away;
- nothing implicit ever writes a comment. A press outside a box with words in
  it leaves the box open rather than committing or discarding it, because the
  gestures that land there are ordinary ones: right-clicking your own
  selection, grabbing the scrollbar, cancelling a confirm dialog;
- Enter saves, Shift+Enter is a newline, Escape discards; Save is the first
  and primary button, Delete is pushed away from it;
- stores comments in localStorage keyed by the page `<title>` (or an explicit
  `data-key` on the layer root), restores highlights on reload, and reopens a
  comment for edit/delete when its highlight is clicked;
- survives a forced refresh: the half-typed note is autosaved as a draft on
  every keystroke and the box reopens on it. A republish is survived by the
  key being fixed from the filename by the generator rather than derived from
  the title. Comments are written as a bare JSON array, which every generation
  of this layer can read — an older deployed page calls `.reduce()` on the
  parsed value and its whole script dies on anything else;
- an end-of-page "Your comments" panel with Copy all (Markdown, `> quote`),
  Download .md, Export text (selectable textarea, since the Artifact viewer
  blocks page-initiated downloads), and Delete all. Only a copy that actually
  happened clears the "not yet exported" state;
- every destructive control asks twice in the page itself, never through a
  blocking dialog. The Artifact viewer runs the page in a sandboxed iframe
  with no `allow-modals` keyword, so `window.confirm` returns false without
  ever asking and the browser only logs "Ignored call to ...". A delete
  guarded that way is a dead button exactly where these pages are read;
- a `beforeunload` guard while comments exist that have not been exported,
  which also saves the draft and attempts the download on the way out;
- a fixed count badge that jumps to the panel.

Deliberately absent, each having been built and then removed for causing a
worse failure than it prevented: an IndexedDB mirror (a save racing its own
asynchronous recovery destroyed the comments being recovered), a rolling
backup key (it resurrected comments the user had deliberately cleared, flagged
unexported and unremovable), and a scan of neighbouring localStorage keys to
survive a retitle (it adopted a *different* document's comments, and copied
them into this document's storage and exports, whenever one quote happened to
appear on both pages).
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
 border-radius:8px;box-shadow:0 6px 22px rgba(0,0,0,.18);padding:.6rem;width:min(20rem,calc(100vw - 1.5rem));
 max-height:min(80vh,26rem);overflow:auto}
/* A control that would overwrite unsaved words points at them instead. */
#anPop.nudge{outline:2px solid var(--an-accent);outline-offset:2px}
/* iOS zooms the whole page when a focused field is under 16px. */
@media (pointer:coarse){#anPop textarea,#anExportText{font-size:16px}}
#anPop textarea{width:100%;min-height:4.5rem;border:1px solid var(--an-rule);border-radius:5px;
 background:var(--an-field);color:var(--an-ink);padding:.4rem;font:inherit;font-size:.86rem;resize:vertical}
.anbtn{background:var(--an-accent);color:#fff;border:0;border-radius:5px;padding:.35rem .8rem;
 font:inherit;font-size:.84rem;font-weight:600;cursor:pointer}
.anbtn.ghost{background:transparent;color:var(--an-soft);border:1px solid var(--an-rule)}
.anbtn.ghost.danger,.anbtn.ghost.tiny.danger{color:var(--an-bad);border-color:var(--an-bad)}
/* An armed control must not look like the button that just did nothing, so it
   fills: the second click is visibly a different act from the first. */
.anbtn.anarmed,.anbtn.ghost.danger.anarmed,.anbtn.ghost.tiny.danger.anarmed{
 background:var(--an-bad);color:#fff;border-color:var(--an-bad)}
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
.anacts{display:flex;gap:.4rem;margin-top:.4rem}
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
.anwarn{background:var(--an-bad);color:#fff;padding:.2rem .55rem;border-radius:5px;font-size:.83rem}
#anBadge{position:fixed;right:calc(.9rem + env(safe-area-inset-right,0px));
 bottom:calc(.9rem + env(safe-area-inset-bottom,0px));z-index:1045;background:var(--an-bg);color:var(--an-ink);
 border:1px solid var(--an-rule);border-radius:999px;padding:.4rem .8rem;font:inherit;font-size:.85rem;
 font-weight:600;box-shadow:0 4px 14px rgba(0,0,0,.18);cursor:pointer}
#anBadge.warn{border-color:var(--an-bad);color:var(--an-bad)}
"""

HTML = r"""
<section id="anComments">
<h2 id="your-comments">Your comments</h2>
<p class="anscope">Select any text on this page to attach a note, then press Enter. Notes are saved in this browser and survive a refresh or a republish of this page &mdash; copy them to keep them anywhere else.</p>
<div class="anbar">
  <span class="ancount" id="anCount">No comments yet</span>
  <button class="anbtn" id="anCopy">Copy all</button>
  <button class="anbtn ghost danger" id="anClear">Delete all</button>
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
// Namespaced with a PREFIX, never a suffix. With `KEY + "-draft"`, a page
// titled "Spec-draft" owns the same key as the draft of a page titled "Spec",
// so pressing Escape on one deletes the other's comments outright.
var DIRTY = "an-dirty:" + KEY;
var DRAFT = "an-draft:" + KEY;

// ---- storage -------------------------------------------------------------
// localStorage, and nothing else. An IndexedDB mirror, a backup key and a
// scan of neighbouring keys all lived here and all came out: the mirror let a
// save that raced its own asynchronous recovery destroy the comments it was
// recovering; the backup key resurrected comments the user had deliberately
// cleared; and the neighbour scan adopted a different document's comments
// whenever one quote happened to appear on this page. The republish they were
// meant to survive is already covered, because the generator fixes the key
// (`data-key`) from the filename rather than the title.
function lsGet(k){ try { return localStorage.getItem(k); } catch (e) { return null; } }
function lsSet(k, v){ try { localStorage.setItem(k, v); return true; } catch (e) { return false; } }
function lsDel(k){ try { localStorage.removeItem(k); } catch (e) {} }

// Stored as a bare array, which every generation of this layer can read. An
// older deployed page does `JSON.parse(...).reduce(...)` on this value and
// throws on an object, and that kills its whole script: no handlers, no
// saving, a page that looks fine and silently does nothing.
function readComments(){
  var d; try { d = JSON.parse(lsGet(KEY) || "[]"); } catch (e) { return []; }
  if (Array.isArray(d)) return d;
  if (d && Array.isArray(d.comments)) return d.comments;  // envelope from a newer layer
  return [];
}
// Not a per-tab counter: two tabs on one page would both hand out id 1.
function newId(){ return Date.now() * 1000 + Math.floor(Math.random() * 1000); }

var comments = readComments(), dirty = false, unsaved = false;
try { dirty = localStorage.getItem(DIRTY) === "1"; } catch (e) {}
comments.forEach(function(c){ if (!c.id) c.id = newId(); });
var pop = $("anPop"), txt = $("anTxt"), badge = $("anBadge");
var pending = null, editingId = null;

window.addEventListener("pagehide", saveDraft);
document.addEventListener("visibilitychange", function(){
  if (document.visibilityState === "hidden") saveDraft();
});
window.addEventListener("beforeunload", function(e){
  saveDraft();
  if (!dirty || !comments.length) return;
  // The comments are already in localStorage; this only warns that they have
  // not been copied anywhere outside this browser yet.
  e.preventDefault(); e.returnValue = ""; return "";
});
// A second tab on the same page used to be last-writer-wins. Take its write
// instead — unless a note is open here, because nothing may pull the DOM out
// from under a range the user is still typing against.
window.addEventListener("storage", function(e){
  if (e.key !== KEY || isOpen()) return;
  comments.slice().forEach(function(c){ unwrap(c.id); });
  comments = readComments();
  comments.forEach(function(c){ if (!c.id) c.id = newId(); });
  restoreHighlights(); render();
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
function hasText(){ return !!txt.value.trim(); }
// `rect` is viewport-relative. Measure the box while it is laid out but not
// yet painted, so it never appears at the wrong place for one frame — that
// single-frame jump is itself a flicker.
function placePop(rect){
  pop.style.visibility = "hidden";
  pop.style.display = "block";
  var w = pop.offsetWidth, h = pop.offsetHeight;
  var vw = document.documentElement.clientWidth, vh = document.documentElement.clientHeight;
  var top = rect.bottom + 8;
  if (top + h > vh - 8) top = rect.top - h - 8;             // no room below: flip above
  top = Math.max(8, Math.min(top, Math.max(8, vh - h - 8))); // and keep it on screen either way
  pop.style.left = (Math.max(8, Math.min(rect.left, vw - w - 12)) + window.scrollX) + "px";
  pop.style.top = (top + window.scrollY) + "px";
  pop.style.visibility = "";
}
// Words the user has not saved are not something another control may
// overwrite: clicking a second highlight used to replace the text outright.
function nudge(){
  txt.focus();
  pop.classList.add("nudge");
  setTimeout(function(){ pop.classList.remove("nudge"); }, 700);
}
function openEdit(c, anchor){
  if (isOpen() && editingId !== c.id && hasText()) { nudge(); return; }
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
// opened. The box now closes only on Save, Cancel/Escape, or a press outside
// it while it is still empty.
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
  if (isOpen() && hasText()) return true;
  var range = sel.getRangeAt(0), rect = range.getBoundingClientRect();
  editingId = null; pop.classList.remove("editing");
  pending = { quote: text, where: sectionOf(sel.anchorNode), range: range.cloneRange() };
  placePop(rect);
  txt.value = "";
  if (autofocus) txt.focus();
  return true;
}
// Synchronous, so the focus stays inside the user gesture — Safari only
// raises the soft keyboard for a focus() called within one.
document.addEventListener("mouseup", function(ev){
  if (pop.contains(ev.target)) return;
  if (ev.target.closest && ev.target.closest("mark.note")) return;
  clearTimeout(selTimer);
  openForSelection(true);
});
// A press outside closes an EMPTY box. A box with words in it stays open: no
// gesture the user did not mean as "save" may commit a comment, and plenty of
// ordinary ones land here — right-clicking your own selection to copy it,
// grabbing the scrollbar to reread the passage, or pressing Clear all and
// then cancelling the confirm.
document.addEventListener("mousedown", function(ev){
  if (!isOpen() || pop.contains(ev.target)) return;
  if (hasText()) return;
  closePop();
});
// iOS Safari fires no mouseup for a touch selection drag, so a mouseup-only
// handler makes the page uncommentable on iPhone and iPad. selectionchange
// fires on every platform; debounce it so it runs once the selection settles.
var selTimer = null;
document.addEventListener("selectionchange", function(){
  if (document.activeElement === txt) return;
  if (editingId !== null) return;
  if (isOpen() && hasText()) return;
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
  pop.classList.remove("editing"); pop.classList.remove("nudge");
  txt.value = ""; lsDel(DRAFT);
}
function discard(){ closePop(); }
// The in-progress note, saved on every keystroke, so a forced refresh reopens
// the box where it was instead of losing what was typed into it.
function saveDraft(){
  if (!isOpen() || !hasText()) { lsDel(DRAFT); return; }
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
    // The comment was deleted elsewhere. Drop the draft rather than leave it
    // to reattach itself to whichever comment is handed that id next.
    if (!c) { lsDel(DRAFT); return; }
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

// ---- destructive controls ------------------------------------------------
// No blocking dialog appears here, and none may be added. The Artifact viewer
// runs the page inside a sandboxed iframe with no `allow-modals` keyword, so
// `window.confirm` returns false without ever asking -- the browser just logs
// "Ignored call to ...". Every delete guarded that way returned early on a
// refusal the reviewer never saw: a dead button in the one place these pages
// are read, and working perfectly in a local tab, which is why it survived.
//
// The guard is in the page instead. A first click arms the button and makes it
// say what a second click will destroy; it disarms after ARM_MS, on Escape, or
// on any re-render. Buttons are focusable, so Enter and Space arm and confirm
// exactly like the pointer does.
var ARM_MS = 4000;
var armedBtn = null, armedLabel = "", armedTimer = 0;
function disarm(){
  if (!armedBtn) return;
  // render() may already have thrown this button away; restoring a detached
  // node is harmless but pointless.
  if (armedBtn.isConnected) { armedBtn.textContent = armedLabel; armedBtn.classList.remove("anarmed"); }
  clearTimeout(armedTimer);
  armedBtn = null; armedLabel = ""; armedTimer = 0;
}
// True only on the confirming click. On any other click it arms `btn` and the
// caller must return without destroying anything.
function arm(btn, label){
  if (armedBtn === btn) { disarm(); return true; }
  disarm();
  armedBtn = btn; armedLabel = btn.textContent;
  btn.textContent = label;
  btn.classList.add("anarmed");
  armedTimer = setTimeout(disarm, ARM_MS);
  return false;
}
// Escape cancels, whether focus sits on the armed button or anywhere else.
// Both listeners are needed: the layer root stops key events from bubbling out
// to the host page, so the document listener never sees a keystroke aimed at
// the button, and a listener on the root alone would miss one aimed outside.
function escDisarm(ev){ if (ev.key === "Escape") disarm(); }
root.addEventListener("keydown", escDisarm);
document.addEventListener("keydown", escDisarm);
// A refused write is the one failure the page must not hide: with the quota
// full, the panel would otherwise count a comment that is already gone.
function persist(){
  unsaved = !lsSet(KEY, JSON.stringify(comments));
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
    // Reopened to reread and closed unchanged: not an edit, so it must not
    // reset the export state and re-arm the unload prompt.
    if (c && c.note === note) { closePop(); return; }
    if (c) c.note = note;
    var m = document.querySelector('mark.note[data-cid="' + editingId + '"]');
    if (m) m.title = note;
  } else if (pending) {
    var id = newId();
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
  // Any armed row button is about to be replaced, and an arm left standing on
  // a list this rebuild has changed would confirm a different comment.
  disarm();
  var list = $("anList"), count = $("anCount");
  badge.textContent = "\uD83D\uDCAC " + comments.length;
  badge.className = unsaved || (dirty && comments.length) ? "warn" : "";
  if (!comments.length) {
    count.textContent = "No comments yet"; count.className = "ancount";
    var empty = document.createElement("p");
    empty.className = "anscope"; empty.textContent = "Select any text above to comment.";
    list.replaceChildren(empty);
    return;
  }
  count.textContent = comments.length + (comments.length === 1 ? " comment" : " comments") +
    (unsaved ? " \u2014 this browser refused to store them, copy them now"
             : dirty ? " \u2014 not yet copied out" : " \u2014 copied out");
  count.className = "ancount" + (unsaved || dirty ? " warn" : "");
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
    // Deleting one comment used to require opening its popup first, which is a
    // detour for the commonest correction. It asks twice, because the note
    // itself is the only copy and there is no undo.
    var x = document.createElement("button");
    x.className = "anbtn ghost tiny danger"; x.textContent = "delete";
    x.onclick = function(){
      if (!arm(x, "click again")) return;
      comments = comments.filter(function(y){ return y.id !== c.id; });
      unwrap(c.id);
      if (editingId === c.id) closePop();
      markDirty(); persist(); render();
    };
    d.append(w, q, n);
    if (!hasMark(c)) { var o = document.createElement("div"); o.className = "orphan"; o.textContent = "quoted text not found on this version of the page"; d.append(o); }
    var acts = document.createElement("div"); acts.className = "anacts";
    acts.append(a, x);
    d.append(acts); frag.appendChild(d);
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
// There is deliberately no download path. The Artifact viewer never grants a
// page download permission, so a Download button was inert exactly where these
// pages are read, while still making every publish warn about an offered file.
// Copy all is the one export, with the textarea below as its fallback.
function openExport(){
  var ta = $("anExportText"); ta.value = exportText();
  $("anExport").style.display = "block";
  ta.focus(); ta.select();
}

// Only a copy that actually happened may clear the export state — otherwise
// the panel says the comments are safely out of the browser, and the unload
// guard stands down, when nothing left it.
$("anCopy").onclick = async function(){
  if (!comments.length) { toast('<span class="anok">nothing to copy</span>', 1600); return; }
  var ok = false;
  try { await navigator.clipboard.writeText(exportText()); ok = true; }
  catch (e) {
    var ta = document.createElement("textarea");
    ta.value = exportText();
    ta.setAttribute("readonly", "");
    ta.style.position = "fixed"; ta.style.top = "0"; ta.style.opacity = "0";
    document.body.appendChild(ta); ta.select();
    try { ok = document.execCommand("copy") === true; } catch (e2) { ok = false; }
    ta.remove();
  }
  // Clipboard refused: fall back to the selectable textarea. Opening it is not
  // exporting -- the state clears when the text is actually copied out of it.
  if (!ok) { openExport(); toast('<span class="anwarn">clipboard blocked \u2014 copy from the box</span>', 4000); return; }
  markClean(); render();
  toast('<span class="anok">copied ' + comments.length + '</span>');
};
$("anExportText").addEventListener("copy", function(){
  markClean(); render();
  toast('<span class="anok">copied ' + comments.length + '</span>');
});
$("anExportClose").onclick = function(){ $("anExport").style.display = "none"; };
$("anClear").onclick = function(){
  if (!comments.length) return;
  // "Not copied out yet" is the whole reason this control asks twice, so the
  // warning goes on the armed button, where it is read, rather than into a
  // dialog the viewer never shows.
  if (!arm(this, (dirty ? "Not copied out yet \u2014 click again to delete "
                        : "Click again to delete ") + comments.length)) return;
  comments.slice().forEach(function(c){ unwrap(c.id); });
  comments = []; markClean(); persist(); render();
};
badge.onclick = function(){ $("anComments").scrollIntoView({ behavior: "smooth", block: "start" }); };

// A host page may bind single-key shortcuts on document or window -- a triage
// console where `d` means delete, a slideshow where `j` means next. Typing a
// note would fire them: the keystroke bubbles out of this textarea and reaches
// those listeners, so the page acts on every letter of the comment.
//
// Attached at the layer root in the BUBBLE phase, which is the only position
// that separates the two. Handlers inside the layer (the textarea's own Enter
// and Escape) sit deeper and have already run; document- and window-level
// handlers sit higher and never see the event. A capture-phase listener on
// window would be too early and would kill this layer's own keys as well.
["keydown", "keypress", "keyup"].forEach(function(type){
  root.addEventListener(type, function(ev){ ev.stopPropagation(); });
});

restoreHighlights();
render();
restoreDraft();
})();
"""
