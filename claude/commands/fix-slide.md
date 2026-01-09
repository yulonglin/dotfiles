# Fix Slide Issues

Identify and fix slides with content overflow or blank pages in Slidev presentations.

## Arguments

$ARGUMENTS should be the path to the slides file (e.g., `slides.md` or `pages/week-19.md`). If not provided, ask the user.

**Important**: If checking a `pages/*.md` file, export from `slides.md` instead to correctly resolve images in `public/`. Exporting directly from subpages causes image resolution failures.

## Workflow

1. **Export to PDF** to identify issues:
   ```bash
   bunx slidev export $ARGUMENTS --timeout 120000 --output tmp/slide-check.pdf
   ```

2. **Analyze PDF** - Read the exported PDF and identify:
   - Pages where content is cut off (text/tables/callouts extending beyond slide boundaries)
   - **Blank pages** (may indicate uncommented `---` between commented sections)

3. **Fix overflows** using these patterns:
   - Wrap content in `<div class="text-sm">` or `text-xs` for smaller text
   - Reduce grid gaps: `gap-8` → `gap-4`
   - Reduce margins/padding: `mt-4 p-3` → `mt-2 p-2`
   - Condense verbose text while preserving key information
   - Split into multiple slides if content is too dense

4. **Fix blank pages** - Comment the `---` separator between commented sections:
   ```markdown
   <!-- slide content -->
   
   <!-- --- -->
   
   <!-- more content -->
   ```

5. **Re-export and verify**:
   ```bash
   bunx slidev export $ARGUMENTS --timeout 120000 --output tmp/slide-fixed.pdf
   ```

6. **Report** which slides were fixed and what changes were made.

## Notes

- Image errors or component rendering issues (e.g., BarChart) are separate - note them but focus on overflow/blank issues
- Prefer condensing text over splitting slides when possible
- Preserve key information and emphasis (bold, callout boxes)
