---
name: artifact-writing
description: The mechanics of publishing to the Artifact platform — md2review, the annotation and commenting layer, localStorage keys and comment recovery, transcript and code-block rendering, sortable tables, the table of contents, mermaid layout, title-from-H1, republishing in place, org-mismatch recovery and supersedes notes, and the viewer sandbox quirks (no confirm/alert/prompt, no page-initiated downloads). Use when publishing or updating any report, plan, spec, findings page, transcript view or dashboard as an Artifact, when running md2review, when building or debugging a select-to-comment layer, when a republish is refused, or when a control works locally but not in the viewer.
---

# Artifact Writing

This skill is the **mechanics** of the Artifact platform and `md2review` — what the viewer does, what it refuses, and how the annotation layer must be built. It carries no presentation or evidence standards: how a page should read lives in **`~/.claude/checklists/presentation.md`**, and what a results page must show — evidence one click away, provenance, transcript legibility, what the annotation layer is for — lives in **`~/.claude/checklists/results-analysis.md`**. Read the relevant one alongside this file.

Yulong's primary reading surface is the Artifact, not terminal scrollback. For any substantive unit of work — an explanation of how something works, a design or audit, experiment results, a debugging postmortem — publish or update an Artifact and keep the chat reply to BLUF plus what changed plus the link. Inline chat text is for quick answers, status and decisions.

**Deliverables live on disk first.** A page that exists only as a successful `Artifact` call is lost when publishing breaks, so write the Markdown source and the built HTML before publishing, and let the publish be the last step.

## `md2review` builds the page; raw `.md` drops everything

**Markdown artifacts cannot carry JavaScript**, so publishing a spec, report or plan as raw `.md` silently drops the table of contents, the annotation layer and the export guard. Anything meant to be reviewed goes through `md2review <file.md>` and is published as the resulting HTML. Raw `.md` is for pages nobody needs to comment on.

`md2review` takes the document's H1 as the `<title>`, so the H1 is the artifact's name in the gallery and the qualifying detail belongs in the `description` parameter and in the line below the H1 rather than in the H1 itself. What the title should *say* is the heading standard in `~/.claude/checklists/presentation.md`.

## One topic, one living page

Update the existing artifact for the topic in place — same URL, passing `url` when the artifact came from an earlier session — rather than minting a new artifact per session. New URL only on a hard topic pivot.

**When the in-place update is refused**, most often an org mismatch (`org_mismatch`, "caller org does not match owner org", or "this Artifact is in another of the user's organizations", which appears when the session's auth org changed after first publication, e.g. after a `/model` switch between differently-billed models), retry once. If it fails again, do **not** pass `contract: 'latest'` to force it — that silently changes the published page's runtime semantics to buy a cosmetic update.

**Publish a new artifact in the current org — that is the default, not a question to raise** (Yulong, 2026-08-28). Don't stop to ask about `/login` versus forking; build the new artifact and hand over its URL, noting the old link is stale. A new file path is required, since republishing the same file path re-targets the old unreachable URL and fails again — `cp` the built HTML to a new path and publish that with no `url`. Put a supersedes note at the top of the new page: what it supersedes, a link to the superseded URL, and why the URL moved. Update every in-repo link. Keep the old page rather than deleting it — its comment threads are the user's work — but treat it as archived. The one exception is the user explicitly saying they will `/login` to recover the old URL.

**Never republish over a page the user may have annotated without saying so first.** `localStorage` survives a redeploy at the same URL, but the anchors the highlights attach to may not, so treat highlight loss as expected on republish.

## The annotation layer: comments are the user's work

Losing a comment is the worst failure the page can have. The shape: select text, a box appears, type, Enter saves; comments persist in `localStorage`, the collected comments are listed at the end of the page, and one button copies them all to the clipboard **as Markdown** Yulong can paste straight back into a session. `md2review` implements all of this; the rules below matter when building, debugging or reviewing a select-to-comment layer.

- **A comment stays readable and editable after it is written** — clicking its highlight reopens it with the existing text, to reread, revise or delete. A note that survives only as a `title` tooltip is effectively gone the moment it is written.
- **Unexported comments block destructive transitions**: track whether anything changed since the last copy or export, and guard `beforeunload` while it has.
- **A half-typed note is already the user's work**: autosave it as a draft on every keystroke and reopen the box on it, so a forced refresh costs nothing.
- **Derive the storage key from the filename, not the title**, so a retitled republish still finds the comments, and namespace every auxiliary key with a **prefix** — with `key + "-draft"`, a page genuinely titled "Spec-draft" shares a key with the draft of a page titled "Spec", and one silently deletes the other. Never let a failed write pass in silence: `setItem` throws on a full quota, so a swallowed failure leaves the panel counting a comment that is already gone.
- **Recovering comments you are not certain are this page's is worse than showing none.** Three mechanisms were built here and all three came out for losing or leaking data: a rolling backup key resurrected comments the user had deliberately cleared, permanently flagged unexported; an IndexedDB mirror let a save that raced its own asynchronous recovery destroy the comments it was recovering; and a scan of neighbouring `localStorage` keys, gated on one quote of the candidate list matching this page, adopted a *different* document's notes — a confidential comment from one review page was reproduced onto an unrelated one, then written into its storage and its exports. Any cross-document guess needs the user to confirm it, not a heuristic. Only the state's own key, and formats every deployed generation can read, are safe to load unprompted.
- **Say "exported" only when something was actually exported.** `navigator.clipboard.writeText` rejects under permissions and `execCommand("copy")` returns `false`; a handler that ignores both reports success and stands the unload guard down while nothing left the browser. Opening a textarea is not an export either — clear the state on the textarea's `copy` event.

**The comment bar is exactly Copy all and Delete all, plus edit and delete on each comment** — no download button, because the Artifact viewer never grants a page download permission, so the button is inert exactly where these pages are read while still making every publish warn that the page offers a file. Copy falls back to a selectable textarea when the clipboard is refused. Two controls the reader can trust beat four where two are inert.

**Select → type → Enter is the whole workflow.** The keyboard path has to complete without touching a button: Enter saves, Shift+Enter is a newline, Escape discards. When the buttons are read at all, the primary one comes first in DOM order (which is also tab order), and the destructive one is pushed away from it. A box whose leading control is Cancel puts the least likely action under the cursor.

**Nothing implicit may write a comment.** Auto-saving a half-typed note when the user "clicks away" sounds protective and is not: the gestures that land outside the box are ordinary ones — right-clicking your own selection to copy it, grabbing the scrollbar to reread the passage, pressing a destructive button and then cancelling its confirm. Each of those committed a comment the reviewer had not finished writing. A press outside closes an **empty** box and leaves a non-empty one open; the words stay on screen, and the keystroke draft covers the refresh. For the same reason, a control that would overwrite unsaved text must decline and point at it rather than replace it.

**Touch selection needs `selectionchange`, not `mouseup`.** iOS Safari fires no `mouseup` for a touch selection drag, so a `mouseup`-only annotation layer leaves every iPhone and iPad reader unable to comment at all — and it looks fine on the desktop where it was built. Any select-to-comment page must open its note box from a debounced `selectionchange`, must not steal focus on touch (focusing a field while iOS shows its selection handles drops the selection), and must re-attach highlights on load from the stored quotes, because a reload rebuilds the page and Safari discards background tabs freely. `md2review` does all three; `tests/test_md2review_ios.py` guards them.

**A selection event may open the note box; it must never close it.** Opening the box focuses its textarea, and focusing collapses the document selection — so a handler that closes on "the selection went away" closes the box it just opened, one debounce later. That is the flicker where a box appears and vanishes as you select. Make opening and closing asymmetric: selection events only open, and only Save, Cancel/Escape or a press outside close. The corollary is that the box must survive anything the browser does to the selection behind it, which means a typed note is never discarded by an event the user did not cause — on a press outside, save it rather than drop it. This is behaviour no string match can check, so it is guarded in a real browser by `tests/test_md2review_browser.py`; the same tests fail against the pre-fix layer, which is what makes them worth having.

**Escape the non-ASCII in an injected layer.** The layer lands in host pages whose charset it does not control, and a page served without `charset=utf-8` is decoded as latin-1, so a raw 💬 or curly quote in a JavaScript string reaches the reader as mojibake (the badge rendered as `ðŸ'¬`). Spell them as `\uD83D\uDCAC` and `\u201C` instead — an escape survives either decoding. `tests/test_annotate_html.py` holds the layer's strings to ASCII, exempting comments, where nothing renders them and readable prose is worth more.

**Single-key shortcuts must not fire while the reader is typing.** The comment box is a `<textarea>` inside the annotation layer, so a host page that guards only `INPUT` lets every letter of a note double as a command — on the context-ledger page, typing `d` in a comment marked the selected row *drop*. Two defences, both cheap:

- The layer stops its own key events at its root in the **bubble** phase, so handlers bound on `document` or `window` never see them. Bubble at the layer root is the one position that works: handlers *inside* the layer (the textarea's Enter and Escape) sit deeper and have already run, while a capture listener on `window` would fire too early and kill the layer's own keys.
- The host page still guards independently — `INPUT`, `TEXTAREA`, `SELECT`, `isContentEditable`, and anything inside `[data-annotation-layer]` — because a page may bind its own capture-phase listeners, which no bubble-phase stop can reach.

Test it by typing the shortcut letters into a real comment box and asserting the page state did not change. A page whose shortcuts are only tested outside the comment box has not been tested.

## The viewer sandbox refuses modals and downloads

**`confirm`, `alert` and `prompt` do not exist in the Artifact viewer.** The viewer renders the page inside a sandboxed iframe with no `allow-modals` keyword, so `window.confirm` returns false without ever asking — Chrome only logs `Ignored call to 'confirm()'. The document is sandboxed`. A destructive control that returns early on that refusal is a dead button in the one place the page is actually read. This bit three controls at once: **Delete all** and the per-comment **delete** in the annotation layer, and a **Reset marks** button in the host page itself — so it is a rule about every control on every artifact, not a quirk of the layer. Guard destructive controls in the page instead: the button arms on the first click, says what the second click will destroy, and disarms on a timeout, on Escape, or on any re-render. Never stub `window.confirm` to test such a path — the stub supplies the dialog the viewer never will, so it hides exactly this bug. Test the control inside `<iframe sandbox="allow-scripts allow-same-origin">`, which is what the viewer does.

The viewer also grants no download permission, so a page-initiated file save is inert — see the comment bar above.

**Every control on the page is exercised before publishing**, in a real browser, including the destructive ones: reset, delete-all, per-item delete, copy, and each filter and sort. A button that renders is not a button that works — the shortcut collision above shipped in a page whose keyboard path had been tested only where no comment box was open.

## Rendering mechanics

**Transcripts.** The full text sits in a collapsed `<details>` beside the excerpt (the *why* is in `~/.claude/checklists/results-analysis.md`); inside it, visually locate the excerpt the prose is about with a `<mark>`, a coloured left border or a boxed span, so expanding the section shows immediately where the fragment sits in context. Keep the role palette theme-aware. Long transcripts scroll inside their own container (`overflow-x: auto`, bounded `max-height`), never the page body.

**Enumerated instances.** Where a page lists many samples, episodes or runs, give each collapsed row a compact per-step strip in its header — one cell per step (attempt, turn, retry, epoch), coloured by that step's outcome plus a label — so recovery, degradation and "it failed the same way ten times" are visible before anything is opened.

**Code blocks — style every `<pre>`, not just the one you were looking at.** A rule keyed to the class you happened to use (`pre.body`) leaves every other `<pre>` on the page with browser-default `white-space: pre`, so an embedded file's long lines run straight out of the container with no scrollbar and the block looks broken the first time anyone expands it. Give `pre` itself `white-space: pre-wrap`, `word-break: break-word`, `overflow-x: auto` and a bounded `max-height`, then specialise. The same trap catches tables, `<img>` and anything else wide enough to escape.

**Truncated embeds.** Pages that inline a file usually cap its length. A file trimmed silently reads as complete and misleads whoever quotes it — state the cap and how much is missing, right where the content ends.

**Table of contents.** Fixed on the left for any page that scrolls past a couple of screens, with the current position indicated. It must not steal width from the content on narrow viewports — collapse it to a top bar, a toggle, or hide it under a breakpoint.

**Sortable, filterable tables.** Clicking a column label sorts, again reverses, a third time returns to the natural order; the caret opens the value menu. Sorting flattens any grouping — a sort the reader asked for must not be silently confined inside buckets — and it conflicts with hand-ordering, so a page offering both must say so rather than appear to ignore a drag. Provide one **Clear sort & filters** control: filters that cannot be cleared in one action strand the reader in an empty table. What the menu must contain — distinct values with live counts, All/None, numeric columns banded rather than listing every integer — is the standard in `~/.claude/checklists/results-analysis.md`.

**Mermaid layout.** Favour vertical space: `flowchart TD` over `LR`, and the equivalent orientation choice for other diagram types. TD alone is not enough — several siblings at one rank still render wide, so stack them with invisible `~~~` links and wrap long labels with `<br/>`. Keep explicit spaces in the text around joins and keep each node's label on ONE source line: labels assembled across source lines, or tight against `<br/>`, render as words concatenated without spaces. Scrolling vertically is easy; panning horizontally is not.

## Reach for a neighbour instead when

- the question is **what the page should say or show** — headings, plots, attention, collapse-by-default, terminology: `~/.claude/checklists/presentation.md`
- the page reports a **run**: evidence one click from every aggregate, provenance, transcript legibility, the per-finding shape, what the annotation layer is *for* — `~/.claude/checklists/results-analysis.md`
- the numbers need **statistical machinery** — intervals, nulls, chance correction, slicing: the `results-artifact` skill
- it is a **spec or plan**: the `spec-artifact` skill
- the draft is finished and the risk is being **misread**: the `reduce-ambiguity` skill, run once per page
- the page is published and needs **recording or reconciling** in `ARTIFACTS.md`: the `artifacts-sync` skill
- the sentences themselves are the problem: `~/.claude/checklists/writing.md`
- a chart is going on the page: the built-in `dataviz` skill (`house-plots` is for papers)

## Why this file is thin

Five checklists hold the standards; skills route to them. This one keeps only what is true of the Artifact platform and `md2review` specifically — the quirks no checklist should have to carry. See `~/.claude/checklists/README.md`.
