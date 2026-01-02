# Fix Slide Overflow

Identify and fix slides with content overflow in Slidev presentations.

## Arguments

$ARGUMENTS should be the path to the slides file (e.g., `slides.md` or `pages/week-19.md`). If not provided, ask the user.

## Workflow

1. **Export to PDF** to identify cut-off content:
   ```bash
   bunx slidev export $ARGUMENTS --timeout 120000 -o tmp/overflow-check.pdf
   ```

2. **Analyze PDF** - Read the exported PDF and identify pages where content is cut off (text/tables/callouts extending beyond slide boundaries)

3. **Fix overflows** using these patterns:
   - Wrap content in `<div class="text-sm">` or `text-xs` for smaller text
   - Reduce grid gaps: `gap-8` → `gap-4`
   - Reduce margins/padding: `mt-4 p-3` → `mt-2 p-2`
   - Condense verbose text while preserving key information
   - Split into multiple slides if content is too dense

4. **Re-export and verify** all content now fits:
   ```bash
   bunx slidev export $ARGUMENTS --timeout 120000 -o tmp/overflow-fixed.pdf
   ```

5. **Report** which slides were fixed and what changes were made.

## Notes

- Image errors or component rendering issues (e.g., BarChart) are separate from overflow - note them but focus on text/table overflow
- Prefer condensing text over splitting slides when possible
- Preserve key information and emphasis (bold, callout boxes)
