---
name: slidev
description: Slidev deck tooling — build and preview a deck, export it to PDF or PNG, and fix a slide whose content overflows, is cut off, or renders as a blank page. Use when creating or editing slides, when the user mentions Slidev, slides.md, `pages/*.md` slide files, a dev server for slides, presentation export, or a PDF/PNG export of a deck; and equally when a slide overflows its boundaries, text or a table runs off the edge, a page comes out blank, or the user asks to fix, check or clean up slides in an existing deck. Slidev-only: it drives `bunx slidev`, and assumes Slidev's `src:` imports and `---` slide separators.
---

# Slidev

This file is the **tooling** for Slidev decks. What belongs on a slide — one message per slide, the summary-first opening, the agenda, backup slides, and the figure rules — lives in **`~/.claude/checklists/presentation.md`**; read that when the question is about content rather than the toolchain.

**Dev server**: `bunx slidev slides.md`

**Export**: `bunx slidev export slides.md --timeout 120000 --output out.pdf`

Always export from root `slides.md`, not `pages/*.md` — images do not resolve from subpages.

## Never read an export in main context

⚠️ An exported PDF can consume the whole context window. Delegate it: a subagent reads the export and reports back only the issues.

```
Task tool → subagent_type: "general-purpose"
Prompt: "Read [path/to/slides.pdf] and identify: (1) pages with content overflow or cut-off, (2) blank pages. Return a list of page numbers and issues found."
```

PNG exports of a narrow page range are small enough to read directly, which is why the fix workflow below exports images rather than a PDF.

## Fixing overflow or blank slides

The target is the file to **edit** — `slides.md`, or a child deck such as `pages/week-19.md`. If none is given, auto-detect the latest child deck: read the main `slides.md` for its `src:` imports; the **first** `src:` import after the title slide is typically the latest week.

1. **Determine the slide range** for the target file. Count `---` separators in it to get the slide count, then find the page offset from its position among the `src:` imports in `slides.md`. Example: `pages/week-21.md` is the first import after the title slide and holds 14 slides, so the range is `2-15`.

2. **Export that range as PNG images**, which avoids the PDF context bloat:
   ```bash
   mkdir -p ./tmp/slides-images
   bunx slidev export slides.md --format png --output ./tmp/slides-images/slide --range <start>-<end> --timeout 120000
   ```

3. **Read the PNGs** and identify pages where content is cut off (text, tables or callouts extending past the slide boundary) and pages that are blank — a blank page usually means an uncommented `---` between commented-out sections.

4. **Fix overflow** by shrinking type (`<div class="text-sm">` or `text-xs`), reducing grid gaps (`gap-8` → `gap-4`), reducing margins and padding (`mt-4 p-3` → `mt-2 p-2`), condensing verbose text while keeping the key information, or splitting the slide when the content is genuinely too dense. Prefer condensing over splitting, and preserve emphasis — bold, callout boxes.

5. **Fix a blank page** by commenting out the `---` separator that sits between commented sections:
   ```markdown
   <!-- slide content -->

   <!-- --- -->

   <!-- more content -->
   ```

6. **Re-export just the affected pages and verify**:
   ```bash
   bunx slidev export slides.md --format png --output ./tmp/slides-fixed/slide --range <affected-pages> --timeout 120000
   ```
   Read the new PNGs to confirm the issue is gone.

7. **Report** which slides changed and what was done to each.

Image-loading errors and component rendering failures (a `BarChart` that does not draw, say) are a separate class — note them, but do not let them pull the pass away from overflow and blank pages.

## Reach for a neighbour instead when

- the question is **what goes on the slide** — one message per slide, summary slide, agenda, backup slides, figure legibility: `~/.claude/checklists/presentation.md`
- the deck is **Marp**, not Slidev: the `marp-deck` skill
- the deck is a **research update** and you need its structure and narrative: the `research-presentation` skill
- a **chart** is what needs building: `house-plots` for matplotlib figures, the built-in `dataviz` for native SVG
