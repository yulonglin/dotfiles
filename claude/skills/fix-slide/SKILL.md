---
name: fix-slide
description: Identify and fix slides with content overflow or blank pages in Slidev presentations.
---

# Fix Slide Issues

Identify and fix slides with content overflow or blank pages in Slidev presentations.

## Arguments
The skill accepts a file to **edit** (e.g., `slides.md` or `pages/week-19.md`).

**If not provided**, auto-detect the latest child slide deck:
1. Read the main `slides.md` to find `src:` imports
2. The **first** `src:` import (after the title slide) is typically the latest week
3. Use that file as the target (e.g., `pages/week-21.md`)

## Context Management (CRITICAL)

⚠️ **Use a subagent to analyze the PDF** - PDFs can consume the entire context window.

```
Task tool → subagent_type: "general-purpose"
Prompt: "Read tmp/slide-check.pdf and identify: (1) pages with content overflow/cut-off, (2) blank pages. Return a list of page numbers and issues found."
```

## Workflow

1. **Determine slide range** for the target file:
   - Count slide separators (`---`) in the target file to get slide count
   - Find the page offset by checking which `src:` import it is in `slides.md`
   - Example: If `pages/week-21.md` is the first import after title slide, and has 14 slides, export range `2-15`

2. **Export as PNG images** for targeted analysis (avoids PDF context bloat):
   ```bash
   mkdir -p tmp/slides-images
   bunx slidev export slides.md --format png --output tmp/slides-images/slide --range <start>-<end> --timeout 120000
   ```

3. **Analyze images directly** - Read the PNG files to identify:
   - Pages where content is cut off (text/tables/callouts extending beyond slide boundaries)
   - **Blank pages** (may indicate uncommented `---` between commented sections)

4. **Fix overflows** using these patterns:
   - Wrap content in `<div class="text-sm">` or `text-xs` for smaller text
   - Reduce grid gaps: `gap-8` → `gap-4`
   - Reduce margins/padding: `mt-4 p-3` → `mt-2 p-2`
   - Condense verbose text while preserving key information
   - Split into multiple slides if content is too dense

5. **Fix blank pages** - Comment the `---` separator between commented sections:
   ```markdown
   <!-- slide content -->
   
   <!-- --- -->
   
   <!-- more content -->
   ```

6. **Re-export and verify** (just the affected slides):
   ```bash
   bunx slidev export slides.md --format png --output tmp/slides-fixed/slide --range <affected-pages> --timeout 120000
   ```
   Read the fixed PNG files to confirm the issue is resolved.

7. **Report** which slides were fixed and what changes were made.

## Notes

- Image errors or component rendering issues (e.g., BarChart) are separate - note them but focus on overflow/blank issues
- Prefer condensing text over splitting slides when possible
- Preserve key information and emphasis (bold, callout boxes)
