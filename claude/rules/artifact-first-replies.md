# Artifact-First Replies

Yulong's primary reading surface is the Artifact, not terminal scrollback. For any substantive unit of work — an explanation of how something works, a design or audit, experiment results, a debugging postmortem — publish or update an Artifact and keep the chat reply to BLUF + what changed + the link. Inline chat text remains for answers to quick questions, status, and decisions.

What belongs in the artifact, whenever the content has the corresponding shape:

- **Mermaid diagrams** for mechanisms and flows (mind `markdown-style.md`: one source line per label, explicit spaces around `<br/>`).
- **Plots** for results (house style: pastelplot/anthroplot).
- **Code snippets** for anything code-mechanical, with the load-bearing lines visually highlighted (e.g. `<mark>` or a colored span), not whole-file dumps.
- **Representative transcripts** for eval/monitor work, again with the relevant spans highlighted.

## Transcripts: excerpt in focus, full text one click away

An excerpt alone is unfalsifiable — the reader cannot tell what was cropped, and cropping is where selection bias hides. So never ship only the excerpt. Every transcript, prompt, or model output shown in an artifact carries **the full text in a collapsed `<details>` right beside it**, defaulting closed so the page still reads as an argument rather than a log dump.

Inside the full text, the excerpt that the surrounding prose is about MUST be visually located — a `<mark>`, a colored left border, or a boxed span — so expanding the section shows immediately where the quoted fragment sits in context, rather than making the reader search for it.

**Colour by speaker, consistently within a page**: user/prompt, assistant/model, tool or harness feedback, and error output each get their own background or left-border colour, with a small role label. Reasoning (`<think>`, CoT) is a distinct role from the final answer and must be visually separable — that distinction is usually the point of the analysis. Keep the palette theme-aware like the rest of the page, and never encode role by colour alone: the role label carries it for anyone who can't distinguish the hues.

Long transcripts scroll inside their own container (`overflow-x: auto`, bounded `max-height`), never the page body.

## Every repeated unit collapses, and its outcome shows while collapsed

Whenever a page enumerates many instances of the same thing — samples, episodes, trajectories, runs, files, findings — **each instance is independently collapsible**, not just the transcript nested inside it. A page with twenty samples must be skimmable as twenty closed rows.

The collapsed row is the summary, so it has to carry the outcome: **status at a glance, without expanding.** Pass/fail/error, or whatever the analogous outcome is, belongs in the closed header as a coloured pill plus a word. For anything with a sequence of steps (attempts, turns, retries, epochs), put a **compact per-step strip** in the header too — one cell per step, coloured by that step's outcome — so trends across the sequence are visible before anything is opened. Recovery, degradation, and "it failed the same way ten times" are all things the reader should see without clicking.

Never encode outcome by colour alone: pair it with a label or letter.

## Navigation for anything long

Any page that scrolls past a couple of screens gets a **table of contents fixed on the left**, listing sections and the enumerated instances, with the current position indicated. It must not steal width from the content on narrow viewports — collapse it to a top bar, a toggle, or hide it under a breakpoint.

## Reviewable pages

**Every spec, plan and report is published as an Artifact — a spec that exists only as a file in `specs/` is not delivered.** The Markdown stays in `specs/` as the version-controlled source; the Artifact is the copy Yulong reads and annotates. Specs are written to be argued with, and a file in a folder cannot be argued with — you cannot select a paragraph and say "no, not this". So the closing reply to any spec work carries the link, not just the path. One spec keeps one link: update the same Artifact in place (pass `url` from a later session) rather than minting a new one per revision.

**Markdown artifacts cannot carry JavaScript**, so publishing a spec, report or plan as raw `.md` silently drops the table of contents, the annotation layer and the export guard. Anything meant to be *reviewed* goes through `md2review <file.md>` first and gets published as the resulting HTML. Raw `.md` is for pages nobody needs to comment on.

Give the page a real name — `md2review` takes the document's H1 as the `<title>`, so the H1 is the artifact's name in the gallery, not a caption. A short noun phrase; put the explaining sentence in the line below it.

**The Artifact viewer blocks any page-initiated file save**, so `md2review`'s "Export text" cannot hand over a `.md` file. It already falls back to a selectable textarea, so the export still works — only the file save is dropped. "Copy all" and "Export text" are both fine; say which, rather than claiming the button is dead.

**Touch selection needs `selectionchange`, not `mouseup`.** iOS Safari fires no `mouseup` for a touch selection drag, so a `mouseup`-only annotation layer leaves every iPhone and iPad reader unable to comment at all — and it looks fine on the desktop where it was built. Any select-to-comment page must open its note box from a debounced `selectionchange` too, must not steal focus on touch (focusing a field while iOS shows its selection handles drops the selection), and must re-attach highlights on load from the stored quotes, because a reload rebuilds the page and Safari discards background tabs freely. `md2review` does all three as of 2026-08-18; `tests/test_md2review_ios.py` guards them.

When the page exists for Yulong to react to — findings, transcripts, drafts, specs, anything he will have opinions about — make it **annotatable**: select text, attach a comment, and a single button that copies every comment to the clipboard as Markdown he can paste back. Persist comments in `localStorage` so closing the tab does not lose them, and show the collected comments at the end of the page.

**Comments are the user's work, and losing them is the worst failure the page can have.** Three consequences, all mandatory:

- **A comment stays readable and editable after it is written.** Clicking its highlight reopens it with the existing text, so it can be reread, revised or deleted. A note that survives only as a `title` tooltip is effectively gone the moment it is written.
- **Unexported comments block destructive transitions.** Track whether anything has changed since the last copy/export and guard `beforeunload` while it has. Offer a file download beside clipboard copy, because clipboard can silently fail under permissions.
- **Never republish over a page the user may have annotated without saying so first.** Before updating an artifact that has a comment affordance, tell them it is about to change and let them export. `localStorage` survives a redeploy at the same URL, but the anchors the highlights attach to may not, so treat highlight loss as expected on republish.

Update the existing artifact for the topic in place (same URL — pass `url` when the artifact came from an earlier session) rather than minting a new artifact per session; one topic = one living page. New URL only on a hard topic pivot.

Possible future enforcement (not yet wired): a hook on Artifact publish / session Stop that nudges when substantive work ends without an artifact update. Wiring hooks requires an interactive session with access to hook config; do it via hookify when asked.
