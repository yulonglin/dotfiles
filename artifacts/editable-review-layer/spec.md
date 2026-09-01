# Artifacts Become Editable As Well As Commentable

Spec for the suggested-edits layer (annotation layer v2) and the committed-HTML convention. Decided with Yulong 2026-09-01; this page is the first artifact published under its own rules.

## Overview

Specs, plans and reports are reviewed as Artifacts, but today the review surface only takes comments. Yulong can say "this paragraph is wrong" and paste the objection back; he cannot say "make it this instead" without writing the replacement into a comment and hoping the session applies it faithfully. This spec adds a **suggest-edit mode** to the md2artifact annotation layer — Google-Docs suggesting mode, adapted to a static sandboxed page — and changes the `artifacts/` convention so that **the built HTML is committed beside the source for all artifacts**, making the repo copy the durable, rebuildable record.

The round-trip this buys: select text on the published page, propose a replacement, export everything as Markdown, paste it into a session; the session applies the edits to the committed source, rebuilds, and republishes at the same URL. The page is the edit surface; the source stays the truth.

Out of scope, deliberately: mechanical patch application (see Requirements — export), overlapping edit ranges, edits spanning block boundaries, native claude.ai comment threads, and any cross-document storage recovery (three attempts documented in `artifact-writing` all lost or leaked data).

## Requirements

### Suggest-edit mode extends the existing box; Comment stays the default

- The select-to-annotate box gains a second mode, **Suggest edit**, reachable by a button in the box. Comment remains the default: select → type → Enter must keep meaning exactly what it means today.
- Entering edit mode pre-fills the textarea with the selected text; the user edits it into the replacement. **The prefill is not user work**: draft autosave and the "non-empty box refuses to close" invariant key on a dirty flag set by the first user modification, not on non-emptiness — otherwise every opened edit box becomes an unclosable phantom draft.
- An empty replacement is a **suggested deletion**, rendered as pure strikethrough. It is reachable only by actively clearing the prefill; that is deliberate.
- Keyboard path completes without a pointer: Enter saves, Shift+Enter newline, Escape discards. Any mode-switch keystroke must be a chord (e.g. Ctrl+E), never a bare letter — the single-key collision inside a textarea is a documented incident.
- A selection overlapping an existing suggested edit is **declined**: the box points at the existing edit instead of opening a second one. Overlapping edits cannot be exported appliably.
- All existing invariants hold unchanged for the new mode: nothing implicit writes, selection events only ever open the box, a press outside closes only an empty (non-dirty) box, destructive controls arm-then-confirm in-page (the viewer has no `confirm`), touch selection via debounced `selectionchange`.

### A saved edit renders as strikethrough plus insertion, and inserted text is invisible to anchoring

- A saved edit renders inline: original text struck through, replacement inserted after it, visually distinct from comment highlights (both theme-aware). Clicking either part reopens the box with the stored replacement for revise or delete.
- **Layer-inserted content is marked and excluded from all quote-scanning.** Re-anchoring of every comment and edit matches against original document text only; text the layer inserted (replacements, UI) must never be scanned. Without this, the first saved edit corrupts the anchors of everything after it.

### Storage stays one localStorage key, entries typed, old data readable

- Entries live in the existing filename-derived key. Each entry carries `type: "comment" | "edit"`; an entry without `type` is a comment, so every page's existing comments load unchanged.
- Edits store the quote, its locating context, and the replacement. Aux keys stay prefix-namespaced; `setItem` failures stay loud.
- `LAYER_VERSION` bumps to `v2`. Pages built before v2 are frozen at v1 per the existing rule — they gain edit mode only on rebuild and republish.

### Export is rendered-text quotes that an LLM session applies — never a mechanical patch

- Copy-all gains a **Suggested edits** section: numbered blocks of `Replace: > quote` / `With: > replacement`, followed by the unchanged comments section. The badge and the unexported-work unload guard count both types.
- The quotes are **rendered text**, and the source is Markdown, so emphasis markers, links and code spans differ between the two. The export therefore does not promise mechanical application: the applying session locates each quote in the source and adapts the markup. Nobody builds a sed loop over this format; a tool that applies these blocks byte-for-byte will corrupt the source.

### The built HTML is committed beside the source, for all artifacts

- `artifacts/<slug>/` now holds the built page (e.g. `<slug>.html`) as a committed file beside `meta.yml` and the source. `build/` remains gitignored scratch. Decided by Yulong 2026-09-01: this applies to **all artifacts**, not only specs and plans; the context-ledger "too large to commit" example in `artifacts/README.md` is superseded and its README rewritten.
- Rebuild and republish update the committed HTML in the same commit as the source change, so the repo copy always matches the published page.
- The publish-path hook (`block_throwaway_artifact_path.sh`) already admits tracked paths; no hook change is required.

### The docs route updates as one pass

- `spec-artifact` gains the round-trip loop (publish → suggest edits → export → session applies → republish, one topic one URL) and a short plan-shape note: plans are mostly generated by sessions via superpowers `writing-plans` (saved under `docs/superpowers/plans/`), and a plan needing Yulong's review publishes the same editable-commentable way — route, don't restate.
- `artifacts/README.md`, `artifacts-sync` (Source column now includes the committed HTML), `artifact-writing` (edit-mode mechanics and invariants), `spec-interview` (tail cross-refs), and the repo `CLAUDE.md` top rule all update to match. Standards live in one place each; the rest route.

## Acceptance Criteria

- In a real browser inside `<iframe sandbox="allow-scripts allow-same-origin">`: select text, switch to Suggest edit, modify the prefill, Enter — the page shows strikethrough plus replacement; reload — the edit re-attaches; click it — the box reopens with the stored replacement; clear to empty and save — pure strikethrough.
- Save an edit early in the page, then confirm a comment anchored **after** it still re-attaches on reload — inserted text is provably excluded from anchoring.
- Copy-all yields Markdown with a Suggested edits section and the comments section; the unload guard blocks until export; a fresh session given the export and the committed source applies every edit correctly.
- Open the edit box, change nothing, click outside — the box closes and no draft or entry is written. Type the letters of any host-page shortcut into the box — page state does not change.
- Existing v1 comments on a rebuilt page load and render unchanged; all existing suites (`test_md2artifact_browser.py`, `test_md2artifact_ios.py`, `test_annotate_html.py`, details/mermaid) stay green, extended with the cases above.
- `artifacts/editable-review-layer/` contains committed source and built HTML; `ARTIFACTS.md` carries the row; the six docs-route files are consistent with each other and with this spec.
