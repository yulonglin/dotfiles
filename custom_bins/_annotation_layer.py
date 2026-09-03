"""The md2artifact annotation layer, as one shared block of CSS + HTML + JS.

This is the single copy of the select-to-comment layer that
the `artifact-writing` skill requires on every reviewable page. Two
callers use it:

- `md2artifact` renders Markdown into a page and appends the layer.
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
- an end-of-page "Your comments" panel with three controls: Copy all
  (Markdown, `> quote`), Delete copied, and Delete all. There is no download button: the
  Artifact viewer blocks any page-initiated file save, so one was a button
  that did nothing wherever these pages are read. When the clipboard itself
  refuses, Copy all opens a selectable textarea as its fallback — that box is
  still here, it just has no button of its own. Both routes out are therefore
  clipboard copies, and only a copy that actually happened clears the "not yet
  copied out" state;
- per-comment export state. A copy that actually happened stamps `copiedAt` on
  the comments it carried, and the page-level "not copied out yet" is derived
  from whether any comment lacks one; the legacy `an-dirty:` key is still
  written in lockstep for tabs running an older layer. Editing a comment drops
  its stamp, because the copy that happened carried the previous wording.
  "Delete copied" prunes the stamped set, so the next Copy all sends only fresh
  feedback. There is deliberately NO "delete the uncopied" counterpart: every
  comment predating this key reads as uncopied, so that button would have wiped
  every existing page the first time it ran. On upgrade, comments are stamped
  only when the legacy key reads an explicit "0" -- evidence that a copy really
  happened. A missing key is not evidence and is left alone;
- every destructive control in the comments panel asks twice in the page
  itself, never through a blocking dialog. (The one exception is the Delete
  inside the note popup, which acts on a single comment the user has just
  opened and is reached only for a comment that already exists -- the popup's
  CSS hides it while composing, and it sits at the far end of the row so it is
  never the near miss. The list's own per-row delete does arm.) The Artifact viewer runs the page in a sandboxed iframe
  with no `allow-modals` keyword, so `window.confirm` returns false without
  ever asking and the browser only logs "Ignored call to ...". A delete
  guarded that way is a dead button exactly where these pages are read;
- a `beforeunload` guard while comments exist that have not been copied out,
  which also saves the draft on the way out. It no longer attempts a download,
  and it protects an ordinary tab rather than a published page: the same
  sandbox that suppresses `confirm` excludes the document from unload
  prompting, so the comments' real safety net is that they are already in
  localStorage;
- a fixed count badge that jumps to the panel.

Layer v2 adds a second mode, **Suggest edit**, to the same box. Comment stays
the default, so select-type-Enter means exactly what it meant before. The
additions, all of which the tests guard:

- the box carries two mode buttons above the textarea. Entering edit mode
  pre-fills the textarea with the selection; the user edits it into the
  replacement. The prefill is NOT user work: draft autosave and the "a box with
  words in it refuses to close" invariant key on a `dirty` flag set by the
  first user modification, never on non-emptiness, because otherwise every
  opened edit box is an unclosable phantom draft. Mode resets to Comment on
  every fresh selection, so the default cannot go sticky;
- an empty replacement is a suggested deletion, rendered as pure strikethrough.
  It is reachable only by actively clearing the prefill, which is deliberate;
- a saved edit renders the original struck through with the replacement
  inserted after it, in the good/insert colour rather than the comment
  highlight's yellow. Clicking either part reopens the box on the stored
  replacement. Its Delete arms first, unlike a comment's -- a replacement is
  written text plus an anchor, and there is no undo;
- **layer-inserted text is marked `data-an-inserted` and excluded from every
  quote scan.** Re-anchoring matches original document text only. Without this
  the first saved edit corrupts the anchor of every comment after it: the
  replacement's words are searched too, so a later quote matches inside the
  insertion and the highlight lands early in the page in the wrong place;
- a selection overlapping an existing edit is declined -- the box points at
  that edit instead of opening a second one, because overlapping edits cannot
  be exported appliably;
- entries gained `type: "comment" | "edit"`. An entry with no `type` is a
  comment, so every page's existing comments load unchanged; the key, the bare
  array and the loud `setItem` failure are all as they were. Edits store the
  quote, its section, and the replacement;
- Copy all gains a numbered "Suggested edits" section of `Replace:` /`With:`
  blockquotes, before the unchanged comments section. The quotes are RENDERED
  text while the source is Markdown, so the export promises no mechanical
  application: a session locates each quote in the source and adapts the
  markup. A page with no edits exports exactly what it did under v1.

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

LAYER_VERSION = "v2"
MARKER_OPEN = f"<!-- annotation-layer {LAYER_VERSION} -->"
MARKER_CLOSE = "<!-- /annotation-layer -->"
ROOT_ATTR = "data-annotation-layer"

# Accepts this module's marker and the earlier hand-ported spelling
# (`<!-- annotation-layer -->`, no version) so pages patched before the CLI
# existed are recognised rather than double-injected.
_PRESENT_RE = re.compile(
    r"<!--\s*annotation-layer(\s+v\d+)?\s*-->|" + re.escape(ROOT_ATTR) + r"=",
)
# Matches ANY version's open marker, not this module's. Pinned to MARKER_OPEN,
# `strip_layer` stopped matching the moment LAYER_VERSION was bumped, so
# `--force` on a deployed page of the previous version stripped nothing and
# injected a second layer: two scripts, two note boxes, two writers of one key.
_BLOCK_RE = re.compile(
    r"<!--\s*annotation-layer(?:\s+v\d+)?\s*-->.*?" + re.escape(MARKER_CLOSE) + r"\n?",
    re.S,
)
_BODY_CLOSE_RE = re.compile(r"</body\s*>", re.I)


def has_layer(page: str) -> bool:
    """Whether the page already carries an annotation layer of any version."""
    return _PRESENT_RE.search(page) is not None


def strip_layer(page: str) -> str:
    """Remove a layer injected by this module, of any version.

    A hand port that carries no closing marker is left alone: there is nothing
    to bound the removal with, and guessing an end would eat the page.
    """
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
/* A suggested edit must not read as a comment highlight: the original is
   struck rather than filled, and the replacement carries the insert colour. */
mark.anedit{background:transparent;color:var(--an-soft);text-decoration:line-through;
 text-decoration-color:var(--an-bad);text-decoration-thickness:2px;cursor:pointer;border-radius:2px}
.anins{background:var(--an-good-bg);color:var(--an-good);border-bottom:2px solid var(--an-good);
 border-radius:2px;padding:0 .12em;cursor:pointer}
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
.anbtn[disabled]{opacity:.42;cursor:default}
/* A copied comment is marked by taking its accent AWAY, never by adding a
   chip: after the first round most of the list is copied, so anything
   additive becomes noise on the majority. The fresh ones keep the accent and
   are what the eye lands on. */
.cmt.ancopied{border-left-color:var(--an-rule)}
/* An armed control must not look like the button that just did nothing, so it
   fills: the second click is visibly a different act from the first. */
.anbtn.anarmed,.anbtn.ghost.danger.anarmed,.anbtn.ghost.tiny.danger.anarmed{
 background:var(--an-bad);color:#fff;border-color:var(--an-bad)}
.anbtn.tiny{padding:.12rem .5rem;font-size:.76rem;margin-top:.4rem}
#anPop:not(.editing) #anDelete{display:none}
/* The mode strip is deliberately NOT in .anrow: Save has to stay the first
   control of that row, which is also its tab order. */
.anmodebar{display:flex;gap:.3rem;margin-bottom:.45rem}
.anmode{flex:1;background:transparent;color:var(--an-soft);border:1px solid var(--an-rule);
 border-radius:5px;padding:.22rem .5rem;font:inherit;font-size:.78rem;font-weight:600;cursor:pointer}
.anmode.ansel{background:var(--an-accent);color:#fff;border-color:var(--an-accent)}
/* Reopening an existing note is not the place to change what it is. */
#anPop.editing .anmodebar{display:none}
.cmt.ansuggest{border-left-color:var(--an-good)}
.cmt .q.struck{text-decoration:line-through}
.cmt .ins{color:var(--an-good)}
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
<p class="anscope">Select any text on this page to attach a note, then press Enter. Switch the box to <strong>Suggest edit</strong> to propose replacement wording instead. Both are saved in this browser and survive a refresh or a republish of this page &mdash; copy them to keep them anywhere else.</p>
<div class="anbar">
  <span class="ancount" id="anCount">No comments yet</span>
  <button class="anbtn" id="anCopy">Copy all</button>
  <button class="anbtn ghost danger" id="anClearCopied">Delete copied</button>
  <button class="anbtn ghost danger" id="anClear">Delete all</button>
  <span id="anToast"></span>
</div>
<div id="anList"></div>
</section>
<div id="anPop" role="dialog" aria-label="Comment">
  <div class="anmodebar" role="group" aria-label="Annotation mode">
    <button class="anmode ansel" type="button" id="anModeComment" aria-pressed="true">Comment</button>
    <button class="anmode" type="button" id="anModeEdit" aria-pressed="false">Suggest edit</button>
  </div>
  <textarea id="anTxt" placeholder="What do you think?"></textarea>
  <div class="anrow">
    <button class="anbtn" id="anSave">Save</button>
    <button class="anbtn ghost" id="anCancel">Cancel</button>
    <button class="anbtn ghost danger" id="anDelete">Delete</button>
  </div>
  <div class="anhint"><kbd>Enter</kbd> saves &middot; <kbd>Shift</kbd>+<kbd>Enter</kbd> newline &middot; <kbd>Esc</kbd> discards &middot; <kbd>Ctrl</kbd>+<kbd>E</kbd> switches mode</div>
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

var comments = readComments(), unsaved = false;
comments.forEach(function(c){ if (!c.id) c.id = newId(); });

// Per-comment export state. `copiedAt` is stamped only where the page-level
// flag was cleared before -- a clipboard write that resolved, or a real copy
// event on the fallback textarea -- so its absence means "never left this
// browser". The asymmetry is deliberate: an unstamped comment can never fall
// into the delete-copied set, so a miss costs one redundant copy rather than
// a page of lost notes. That is also why there is no "delete the uncopied"
// action: every comment predating this key reads as uncopied, so such a
// button would have wiped every existing page on first run.
function isCopied(c){ return !!c.copiedAt; }
function copiedSet(){ return comments.filter(isCopied); }
function freshCount(){ return comments.length - copiedSet().length; }
function isDirty(){ return freshCount() > 0; }
// The legacy page-level key is still written, in lockstep, because a stale tab
// running an older layer reads it and would otherwise raise or stand down its
// unload guard against state it cannot see.
function syncLegacyFlag(){ lsSet(DIRTY, isDirty() ? "1" : "0"); }

// One-time migration for comments written before `copiedAt` existed. Without
// it every upgraded page announces "N of N not yet copied out" and re-arms the
// unload guard for someone who copied everything out yesterday: a false alarm
// on every page in existence, which is how a warning stops being read.
// The legacy flag is EVIDENCE, not an inference -- an explicit "0" was written
// by a copy that actually happened. A key that is MISSING is not evidence and
// is left alone, so absence can never manufacture a safe state.
(function migrateFromLegacyFlag(){
  if (lsGet(DIRTY) !== "0" || !comments.length) return;
  var now = Date.now(), touched = false;
  comments.forEach(function(c){ if (!c.copiedAt) { c.copiedAt = now; touched = true; } });
  if (touched) persist();
})();
var pop = $("anPop"), txt = $("anTxt"), badge = $("anBadge");
var pending = null, editingId = null;
// The box has two modes and one dirty flag. `dirty` is set by the first user
// modification and by nothing else: an edit box OPENS with the selection
// already in its textarea, so keying the draft autosave and the "a box with
// words in it refuses to close" invariant on non-emptiness would turn every
// opened edit box into an unclosable phantom draft nobody typed.
var mode = "comment", dirty = false;
// An entry written before v2 carries no `type`, so absence means comment.
function isEdit(c){ return c && c.type === "edit"; }
function bodyOf(c){ return isEdit(c) ? (c.replacement || "") : (c.note || ""); }

window.addEventListener("pagehide", saveDraft);
document.addEventListener("visibilitychange", function(){
  if (document.visibilityState === "hidden") saveDraft();
});
window.addEventListener("beforeunload", function(e){
  saveDraft();
  if (!isDirty() || !comments.length) return;
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
// `focus` is false on the touch path, where focusing a field while iOS shows
// its selection handles collapses the selection.
function nudge(focus){
  if (focus !== false) txt.focus();
  pop.classList.add("nudge");
  setTimeout(function(){ pop.classList.remove("nudge"); }, 700);
}
// Applies a mode WITHOUT touching the textarea. The prefill belongs to the
// user-driven switch below; the restore paths (an existing entry, a recovered
// draft) supply their own text and must not have it overwritten.
function setModeState(next){
  mode = next;
  var isE = mode === "edit";
  $("anModeComment").classList.toggle("ansel", !isE);
  $("anModeEdit").classList.toggle("ansel", isE);
  $("anModeComment").setAttribute("aria-pressed", isE ? "false" : "true");
  $("anModeEdit").setAttribute("aria-pressed", isE ? "true" : "false");
  txt.placeholder = isE ? "Replacement text; an empty box suggests deleting it"
                        : "What do you think?";
}
// The user-driven switch rewrites the textarea, so it declines while there are
// unsaved words and points at them instead, exactly as a second highlight
// click does. Reopening an existing entry is not the place to change its kind,
// so the strip is hidden then and this is a no-op.
function switchMode(next){
  if (mode === next || editingId !== null) return;
  if (dirty) { nudge(); return; }
  setModeState(next);
  txt.value = (next === "edit" && pending) ? pending.quote : "";
  dirty = false;
  txt.focus();
}
$("anModeComment").onclick = function(){ switchMode("comment"); };
$("anModeEdit").onclick = function(){ switchMode("edit"); };

function openEdit(c, anchor, focus){
  if (isOpen() && editingId !== c.id && dirty) { nudge(focus); return; }
  editingId = c.id; pending = null;
  setModeState(isEdit(c) ? "edit" : "comment");
  txt.value = bodyOf(c);
  dirty = false;
  pop.classList.add("editing");
  placePop(anchor ? anchor.getBoundingClientRect() : { left: 16, top: 100, bottom: 100 });
  if (focus !== false) txt.focus();
}
// Both parts of a suggested edit carry the entry id, as a comment highlight
// does, so clicking the strikethrough or the replacement reopens the same box.
document.addEventListener("click", function(ev){
  var m = ev.target.closest && ev.target.closest("[data-cid]");
  if (!m || pop.contains(ev.target)) return;
  var c = comments.find(function(x){ return x.id === Number(m.dataset.cid); });
  if (!c) return;
  ev.preventDefault(); openEdit(c, m);
});

// Wraps a range in a highlight. surroundContents refuses a range that crosses
// element boundaries, so fall back to lifting the contents out and wrapping.
function wrapRange(range, id, title, cls){
  var m = document.createElement("mark");
  m.className = cls || "note"; m.title = title; m.dataset.cid = String(id);
  try { range.surroundContents(m); }
  catch (e) { m.appendChild(range.extractContents()); range.insertNode(m); }
  return m;
}
// The ONE place the replacement span is created, rewritten or removed. Three
// call sites need it (save a new edit, revise one, restore one on load) and
// they drift apart if each does its own DOM work: an edit revised to empty has
// to lose its span and become pure strikethrough again.
function renderEditInline(c){
  var m = document.querySelector('mark.anedit[data-cid="' + c.id + '"]');
  if (!m) return;
  m.title = c.replacement ? "suggested: " + c.replacement : "suggested deletion";
  var s = document.querySelector('span.anins[data-cid="' + c.id + '"]');
  if (!c.replacement) { if (s) s.remove(); return; }
  if (!s) {
    s = document.createElement("span");
    s.className = "anins"; s.dataset.cid = String(c.id);
    // The marker docTextNodes() looks for. Without it the first saved edit
    // corrupts the anchor of every comment after it, because the replacement's
    // words join the text that quotes are searched in.
    s.setAttribute("data-an-inserted", "1");
    m.parentNode.insertBefore(s, m.nextSibling);
  }
  s.textContent = c.replacement;
}
// Every text node of the page, skipping the layer's own UI, existing
// highlights, and anything the layer itself put on the page. Re-anchoring
// matches ORIGINAL document text only.
function docTextNodes(){
  var host = document.querySelector(".doc") || document.querySelector("main") || document.body;
  var walker = document.createTreeWalker(host, NodeFilter.SHOW_TEXT, { acceptNode: function(n){
    var p = n.parentNode;
    if (!p || !p.closest) return NodeFilter.FILTER_ACCEPT;
    if (p.closest("mark.note") || p.closest("mark.anedit") || p.closest("[data-an-inserted]") ||
        p.closest("[data-annotation-layer]") || p.closest("script,style")) return NodeFilter.FILTER_REJECT;
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
    if (document.querySelector('mark[data-cid="' + c.id + '"]')) return;
    var r = rangeForQuote(c.quote);
    if (!r) { missed++; return; }
    try {
      if (isEdit(c)) { wrapRange(r, c.id, "", "anedit"); renderEditInline(c); }
      else wrapRange(r, c.id, c.note, "note");
    } catch (e) { missed++; }
  });
  return missed;
}
function hasMark(c){ return !!document.querySelector('mark[data-cid="' + c.id + '"]'); }
// A selection touching an existing suggested edit, if there is one. Overlapping
// edits cannot be exported appliably, and a quote that spans inserted text can
// never be re-anchored, so such a selection is declined rather than annotated.
function editOverlapping(range){
  var els = document.querySelectorAll('mark.anedit[data-cid], span.anins[data-cid]');
  for (var i = 0; i < els.length; i++) {
    var el = els[i], hit = false;
    try { hit = range.intersectsNode(el); } catch (e) { hit = false; }
    if (!hit) continue;
    var cid = Number(el.dataset.cid);
    var c = comments.find(function(x){ return x.id === cid; });
    if (c) return { entry: c, el: el };
  }
  return null;
}

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
  // Open on some other selection the user has MODIFIED: leave it be rather
  // than throwing away work. The test is `dirty`, not non-emptiness: an
  // untouched prefilled edit box yields to a fresh selection, and a dirty
  // EMPTY edit box (a pending deletion) is work and must not be overwritten.
  if (isOpen() && dirty) return true;
  var range = sel.getRangeAt(0), rect = range.getBoundingClientRect();
  // Overlaps an existing suggested edit: point at that edit rather than open a
  // second box on the range.
  var hit = editOverlapping(range);
  if (hit) { openEdit(hit.entry, hit.el, autofocus); nudge(autofocus); return true; }
  editingId = null; pop.classList.remove("editing");
  // Comment is the default on every fresh selection. A mode that stayed where
  // it was last left would silently change what select-type-Enter means.
  setModeState("comment");
  pending = { quote: text, where: sectionOf(sel.anchorNode), range: range.cloneRange() };
  placePop(rect);
  txt.value = "";
  dirty = false;
  if (autofocus) txt.focus();
  return true;
}
// Synchronous, so the focus stays inside the user gesture — Safari only
// raises the soft keyboard for a focus() called within one.
document.addEventListener("mouseup", function(ev){
  if (pop.contains(ev.target)) return;
  if (ev.target.closest && ev.target.closest("[data-cid]")) return;
  clearTimeout(selTimer);
  openForSelection(true);
});
// A press outside closes a box the user has not modified. A box with words the
// user put there stays open: no gesture the user did not mean as "save" may
// commit anything, and plenty of ordinary ones land here — right-clicking your
// own selection to copy it, grabbing the scrollbar to reread the passage, or
// pressing Clear all and then cancelling the confirm.
//
// The test is the dirty flag, NOT emptiness, because an edit box opens with
// the selection already in it. Keyed on emptiness, opening one and changing
// your mind would leave a box that cannot be dismissed.
document.addEventListener("mousedown", function(ev){
  if (!isOpen() || pop.contains(ev.target)) return;
  if (dirty) return;
  closePop();
});
// iOS Safari fires no mouseup for a touch selection drag, so a mouseup-only
// handler makes the page uncommentable on iPhone and iPad. selectionchange
// fires on every platform; debounce it so it runs once the selection settles.
var selTimer = null;
document.addEventListener("selectionchange", function(){
  if (document.activeElement === txt) return;
  if (editingId !== null) return;
  // Same test as openForSelection: modified work stays, an untouched prefill
  // does not hold the page hostage.
  if (isOpen() && dirty) return;
  clearTimeout(selTimer);
  selTimer = setTimeout(function(){ openForSelection(false); }, 250);
});

txt.addEventListener("keydown", function(ev){
  if (ev.key === "Enter" && !ev.shiftKey && !ev.altKey && !ev.isComposing) { ev.preventDefault(); save(); }
  else if (ev.key === "Escape") { ev.preventDefault(); discard(); }
  // A CHORD, never a bare letter. A single-key binding on a control that lives
  // inside a textarea fires on the note being typed: on the context-ledger
  // page, `d` in a comment marked the selected row dropped.
  else if ((ev.ctrlKey || ev.metaKey) && (ev.key === "e" || ev.key === "E")) {
    ev.preventDefault(); switchMode(mode === "edit" ? "comment" : "edit");
  }
});
// The user touched the text: from here the box holds work, whether or not the
// prefill it opened with is still in it.
txt.addEventListener("input", function(){ dirty = true; saveDraft(); });
document.addEventListener("keydown", function(ev){
  if (ev.key === "Escape" && isOpen() && document.activeElement !== txt) discard();
});

function closePop(){
  // #anDelete is one element reused by every entry: an arm left live here
  // would confirm on the next opened entry's first click.
  disarm();
  pop.style.display = "none"; pending = null; editingId = null;
  pop.classList.remove("editing"); pop.classList.remove("nudge");
  setModeState("comment"); dirty = false;
  txt.value = ""; lsDel(DRAFT);
}
function discard(){ closePop(); }
// The in-progress note, saved on every keystroke, so a forced refresh reopens
// the box where it was instead of losing what was typed into it.
// `dirty` gates this, not emptiness: an edit box opens pre-filled with the
// selection, and autosaving that would leave a draft nobody typed, which then
// reopens the box on the next load for a note that was never begun.
// In edit mode an EMPTY dirty box is meaningful: the prefill was cleared to
// suggest a deletion, and a refresh before Enter must bring that back. In
// comment mode an empty box is nothing to keep.
function saveDraft(){
  if (!isOpen() || !dirty || (!hasText() && mode !== "edit")) { lsDel(DRAFT); return; }
  lsSet(DRAFT, JSON.stringify({
    note: txt.value, editingId: editingId, mode: mode,
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
    openEdit(c, document.querySelector('mark[data-cid="' + c.id + '"]'));
    txt.value = d.note; dirty = true;
    return;
  }
  var r = rangeForQuote(d.quote);
  if (!r) return;
  var sel = window.getSelection();
  if (sel) { try { sel.removeAllRanges(); sel.addRange(r); } catch (e) {} }
  editingId = null; pop.classList.remove("editing");
  setModeState(d.mode === "edit" ? "edit" : "comment");
  pending = { quote: d.quote, where: d.where || sectionOf(r.startContainer), range: r.cloneRange() };
  placePop(r.getBoundingClientRect());
  // Restored words ARE user work, whatever they started as.
  txt.value = d.note; dirty = true;
}
function unpackDraft(){
  var d = null; try { d = JSON.parse(lsGet(DRAFT) || "null"); } catch (e) {}
  if (!d || typeof d.note !== "string") return null;
  // An empty note is a draft only for an edit that still knows its target: a
  // pending deletion of `quote`, or a revision of an existing edit.
  if (!d.note.trim() && !(d.mode === "edit" && (d.quote || d.editingId != null))) return null;
  return d;
}
// These keep their names and every existing call site; what changed is that
// the state lives on the comments now and the page-level key is derived from
// it. Renaming them to say "copied out" is a separate no-behaviour commit.
function markDirty(){ syncLegacyFlag(); }
// A snapshot of exactly what went into the copied text, so a comment edited
// while an async clipboard write was in flight is not stamped as copied. The
// copy carried the OLD wording; the comment now holds new wording that has
// never left the page, and stamping it would put unsent words in the
// delete-copied set.
function copySnapshot(){
  return comments.map(function(c){
    return { id: c.id, where: c.where, quote: c.quote, note: bodyOf(c) };
  });
}
function markClean(snap){
  var now = Date.now(), by = {};
  (snap || copySnapshot()).forEach(function(x){ by[x.id] = x; });
  comments.forEach(function(c){
    var x = by[c.id];
    if (x && x.where === c.where && x.quote === c.quote && x.note === bodyOf(c)) c.copiedAt = now;
  });
  persist(); syncLegacyFlag();
}

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
var WARN_CHANGED = '<span class="anwarn">the comments changed \u2014 nothing deleted</span>';
var armedBtn = null, armedLabel = "", armedTimer = 0, armedBinding = null;
function disarm(){
  if (!armedBtn) return;
  // render() may already have thrown this button away; restoring a detached
  // node is harmless but pointless.
  if (armedBtn.isConnected) { armedBtn.textContent = armedLabel; armedBtn.classList.remove("anarmed"); }
  clearTimeout(armedTimer);
  armedBtn = null; armedLabel = ""; armedTimer = 0; armedBinding = null;
}
// What an arm was armed AGAINST: the exact comments, plus enough of their
// content to notice a change. A second tab's write can land inside the four
// seconds an arm is live, and the `storage` handler only rebuilds when no note
// is open -- so the confirming click has to prove the set is still the one the
// label described, rather than trust that nothing moved under it.
function bindingOf(list){
  return list.map(function(c){
    return c.id + ":" + (c.copiedAt || 0) + ":" + bodyOf(c).length + ":" + c.quote.length;
  }).join(",");
}
// True only on the confirming click, and only while the set it was armed
// against is unchanged. On any other click it arms `btn` and the caller must
// return without destroying anything.
function arm(btn, label, binding){
  if (armedBtn === btn) {
    var stale = armedBinding !== null && armedBinding !== binding;
    disarm();
    if (stale) { render(); toast(WARN_CHANGED, 4000); return false; }
    return true;
  }
  disarm();
  armedBtn = btn; armedLabel = btn.textContent;
  armedBinding = binding === undefined ? null : binding;
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
  var s = document.querySelector('span.anins[data-cid="' + id + '"]');
  if (s) s.remove();
  var m = document.querySelector('mark[data-cid="' + id + '"]');
  if (m) { while (m.firstChild) m.parentNode.insertBefore(m.firstChild, m); m.remove(); }
}

function save(){
  if (mode === "edit") { saveEdit(txt.value.trim()); return; }
  var note = txt.value.trim();
  if (!note) { closePop(); return; }
  if (editingId !== null) {
    var c = comments.find(function(x){ return x.id === editingId; });
    // Reopened to reread and closed unchanged: not an edit, so it must not
    // reset the export state and re-arm the unload prompt.
    if (c && c.note === note) { closePop(); return; }
    // The copy that happened carried the previous wording, so the stamp no
    // longer describes this comment. Without this, "delete copied" destroys
    // the only copy of the edit and the next Copy all silently omits it.
    if (c) { c.note = note; delete c.copiedAt; }
    var m = document.querySelector('mark.note[data-cid="' + editingId + '"]');
    if (m) m.title = note;
  } else if (pending) {
    var id = newId();
    try { wrapRange(pending.range, id, note, "note"); } catch (e) {}
    comments.push({ id: id, type: "comment", where: pending.where, quote: pending.quote, note: note });
  }
  markDirty(); persist(); render(); closePop();
  var sel = window.getSelection(); if (sel) sel.removeAllRanges();
}
// An empty replacement is a suggested DELETION, so there is no empty-means-
// cancel shortcut here: the comment path's `if (!note) closePop()` would throw
// away exactly the edit the reader worked to express.
function saveEdit(replacement){
  if (editingId !== null) {
    var c = comments.find(function(x){ return x.id === editingId; });
    if (c && c.replacement === replacement) { closePop(); return; }
    if (c) { c.replacement = replacement; delete c.copiedAt; renderEditInline(c); }
  } else if (pending) {
    // The prefill is not user work: an untouched box saves nothing, so Enter
    // on a box still holding the selection verbatim is a close, not an entry
    // proposing to replace the text with itself.
    if (!dirty) { closePop(); return; }
    var id = newId();
    var fresh = { id: id, type: "edit", where: pending.where,
                  quote: pending.quote, replacement: replacement };
    try { wrapRange(pending.range, id, "", "anedit"); } catch (e) {}
    comments.push(fresh);
    renderEditInline(fresh);
  }
  markDirty(); persist(); render(); closePop();
  var sel = window.getSelection(); if (sel) sel.removeAllRanges();
}

$("anCancel").onclick = discard;
$("anDelete").onclick = function(){
  if (editingId === null) { closePop(); return; }
  var id = editingId;
  var c = comments.find(function(x){ return x.id === id; });
  // A comment's Delete stays immediate -- the popup's CSS hides it while
  // composing, it sits at the far end of the row, and it acts on one note the
  // reader has just opened. A suggested edit arms first: it is written
  // replacement text plus an anchor, and one stray click takes both.
  if (isEdit(c) && !arm(this, "click again")) return;
  comments = comments.filter(function(x){ return x.id !== id; });
  unwrap(id);
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
  // Kept in step with the list on every rebuild, and disabled rather than
  // hidden: a control that vanishes and reappears is harder to aim at than one
  // that greys out, and its count is the only place the copied total is shown.
  var nCopied = copiedSet().length, clearCopied = $("anClearCopied");
  clearCopied.textContent = "Delete copied (" + nCopied + ")";
  clearCopied.disabled = !nCopied;
  var fresh = freshCount();
  badge.textContent = "\uD83D\uDCAC " + comments.length;
  badge.className = unsaved || (isDirty() && comments.length) ? "warn" : "";
  if (!comments.length) {
    count.textContent = "No comments yet"; count.className = "ancount";
    var empty = document.createElement("p");
    empty.className = "anscope"; empty.textContent = "Select any text above to comment.";
    list.replaceChildren(empty);
    return;
  }
  // Once the list can be part copied and part not, a single verdict is a lie
  // for one half of it. The split form appears only when the list is actually
  // mixed, so the common uniform cases stay as short as they were. The same
  // applies to the noun: "N comments" is wrong for half a mixed page, and the
  // plain wording is kept for the comment-only page, which is most of them.
  var nEdits = comments.filter(isEdit).length;
  var what = nEdits
    ? comments.length + (comments.length === 1 ? " item (" : " items (") +
      nEdits + (nEdits === 1 ? " suggested edit)" : " suggested edits)")
    : comments.length + (comments.length === 1 ? " comment" : " comments");
  count.textContent = what +
    (unsaved ? " \u2014 this browser refused to store them, copy them now"
             : !fresh ? " \u2014 copied out"
             : fresh === comments.length ? " \u2014 not yet copied out"
             : " \u2014 " + fresh + " of " + comments.length + " not yet copied out");
  count.className = "ancount" + (unsaved || isDirty() ? " warn" : "");
  var frag = document.createDocumentFragment();
  comments.forEach(function(c){
    var d = document.createElement("div");
    d.className = "cmt" + (isCopied(c) ? " ancopied" : "") + (isEdit(c) ? " ansuggest" : "");
    var w = document.createElement("div"); w.className = "where"; w.textContent = c.where;
    var q = document.createElement("div");
    q.className = isEdit(c) ? "q struck" : "q";
    q.textContent = "\u201C" + c.quote + "\u201D";
    var n = document.createElement("div");
    if (isEdit(c)) {
      n.className = "ins";
      n.textContent = c.replacement
        ? "\u2192 " + c.replacement
        : "\u2192 delete this text";
    } else n.textContent = c.note;
    var a = document.createElement("button"); a.className = "anbtn ghost tiny"; a.textContent = "edit";
    a.onclick = function(){
      var m = document.querySelector('mark[data-cid="' + c.id + '"]');
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

function markdown(list){
  return list.map(function(c){
    return "- **" + c.where + "** \u2014 " + c.note + "\n  > " + c.quote.replace(/\n/g, "\n  > ");
  }).join("\n");
}
// Numbered, so a session applying them can say which one it could not place.
function editMarkdown(list){
  return list.map(function(c, i){
    return (i + 1) + ". **" + c.where + "**" +
      "\n   Replace:\n   > " + c.quote.replace(/\n/g, "\n   > ") +
      "\n   With:" + (c.replacement
        ? "\n   > " + c.replacement.replace(/\n/g, "\n   > ")
        : " _(nothing \u2014 delete this text)_");
  }).join("\n\n");
}
// The quotes are RENDERED text and the source is Markdown, so emphasis
// markers, links and code spans differ between the two. The note below says so
// in the export itself, because the export leaves this page and is read
// without it. Nobody builds a sed loop over this format.
var APPLY_NOTE = "These quotes are the page's RENDERED text; the source is Markdown. " +
  "Locate each quote in the source and adapt the markup \u2014 do not apply these " +
  "blocks byte-for-byte.";
// A page with no suggested edits exports exactly what it did under v1: no
// headings appear, so every existing paste-into-a-session habit still works.
function exportText(){
  var edits = comments.filter(isEdit);
  var notes = comments.filter(function(c){ return !isEdit(c); });
  var out = "# Comments \u2014 " + document.title + "\n\n";
  if (edits.length) {
    out += "## Suggested edits\n\n" + APPLY_NOTE + "\n\n" + editMarkdown(edits) + "\n\n";
    if (notes.length) out += "## Comments\n\n";
  }
  return out + (notes.length ? markdown(notes) + "\n" : "");
}
function toast(html, ms){ var t = $("anToast"); t.innerHTML = html; setTimeout(function(){ t.innerHTML = ""; }, ms || 1800); }
// There is deliberately no download path. The Artifact viewer never grants a
// page download permission, so a Download button was inert exactly where these
// pages are read, while still making every publish warn about an offered file.
// Copy all is the one export, with the textarea below as its fallback.
// What the textarea currently holds. The box can sit open while the page is
// edited behind it, so the copy event stamps the snapshot the text was built
// from, not whatever the list happens to be when the user finally hits copy.
var exportSnap = null;
function openExport(){
  var ta = $("anExportText"); ta.value = exportText();
  exportSnap = copySnapshot();
  $("anExport").style.display = "block";
  ta.focus(); ta.select();
}

// Only a copy that actually happened may clear the export state — otherwise
// the panel says the comments are safely out of the browser, and the unload
// guard stands down, when nothing left it.
$("anCopy").onclick = async function(){
  if (!comments.length) { toast('<span class="anok">nothing to copy</span>', 1600); return; }
  var ok = false;
  // Both taken before the await: the clipboard promise can resolve after an
  // edit has landed, and the text that went out is this one.
  var snap = copySnapshot(), text = exportText();
  try { await navigator.clipboard.writeText(text); ok = true; }
  catch (e) {
    var ta = document.createElement("textarea");
    ta.value = text;
    ta.setAttribute("readonly", "");
    ta.style.position = "fixed"; ta.style.top = "0"; ta.style.opacity = "0";
    document.body.appendChild(ta); ta.select();
    try { ok = document.execCommand("copy") === true; } catch (e2) { ok = false; }
    ta.remove();
  }
  // Clipboard refused: fall back to the selectable textarea. Opening it is not
  // exporting -- the state clears when the text is actually copied out of it.
  if (!ok) { openExport(); toast('<span class="anwarn">clipboard blocked \u2014 copy from the box</span>', 4000); return; }
  markClean(snap); render();
  toast('<span class="anok">copied ' + comments.length + '</span>');
};
$("anExportText").addEventListener("copy", function(){
  // A copy of PART of the box carried part of the Markdown, so it did not
  // take every comment out of the browser. Stamping them all would drop
  // comments the user never copied into the "Delete copied" set, which is now
  // a set something deletes. The whole-blob case is the normal one: the box
  // opens with everything already selected.
  var ta = this;
  if (ta.selectionStart !== 0 || ta.selectionEnd !== ta.value.length) {
    toast('<span class="anwarn">partial copy \u2014 nothing marked copied out</span>', 4000);
    return;
  }
  markClean(exportSnap); render();
  toast('<span class="anok">copied ' + comments.length + '</span>');
});
$("anExportClose").onclick = function(){ $("anExport").style.display = "none"; };
// The safe prune, and the reason the literal request was inverted: this
// deletes only what a copy actually carried out of the browser, so the next
// Copy all sends fresh feedback rather than re-sending an actioned list.
$("anClearCopied").onclick = function(){
  var set = copiedSet();
  if (!set.length) return;
  if (!arm(this, "Click again to delete " + set.length + " copied out", bindingOf(set))) return;
  var doomed = {};
  set.forEach(function(c){ doomed[c.id] = true; unwrap(c.id); });
  comments = comments.filter(function(c){ return !doomed[c.id]; });
  if (editingId !== null && doomed[editingId]) closePop();
  persist(); syncLegacyFlag(); render();
};
$("anClear").onclick = function(){
  if (!comments.length) return;
  // "Not copied out yet" is the whole reason this control asks twice, so the
  // warning goes on the armed button, where it is read, rather than into a
  // dialog the viewer never shows.
  // The armed label carries the warning, because the dialog that would
  // otherwise carry it never appears in the viewer. Naming the unsent count
  // separately from the total is the whole point: "delete all 12" and "3 of
  // these have never left this browser" are different facts.
  var fresh = freshCount();
  var warn = fresh
    ? fresh + " not yet copied out \u2014 click again to delete all " + comments.length
    : "All copied out \u2014 click again to delete all " + comments.length;
  if (!arm(this, warn, bindingOf(comments))) return;
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
