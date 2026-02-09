# ToC Diagram Polish — Eliminate Overlaps + ICLR

## Context

The timeline-based ToC diagram (v8) is functionally complete but has two issues:
1. **O2/O3/O4 output boxes nearly overlap** — borders touch due to insufficient horizontal spacing
2. **O4 says "Top venue submission"** — user wants it to say "ICLR submission" specifically
3. **Application text** also references "top venue" in several places — update to "ICLR"

## Changes

### 1. Fix O2/O3/O4 horizontal spacing (toc-diagram.tex)

Current positions (all `anchor=west`, `text width=2.8cm`, `inner sep=8pt≈0.28cm`):
- O2: x=5.4 → right edge ≈ 8.76
- O3: x=9.0 → right edge ≈ 12.36 (gap from O2: 0.24cm — too tight)
- O4: x=12.4 (gap from O3: 0.04cm — borders overlap)

**Fix**: Reduce text width to 2.6cm and spread x positions:
- O2: anchor=west at x=5.4 → right edge ≈ 8.56
- O3: anchor=west at x=9.1 → right edge ≈ 12.26 (gap: 0.54cm)
- O4: anchor=west at x=12.8 → right edge ≈ 15.56 (gap: 0.54cm, fits within timeline zone ≤15.6)

### 2. Update O4 text (toc-diagram.tex, line ~110)

Change: `(M6) Top venue \mbox{submission}` → `(M6) ICLR submission`

### 3. Update application text (mats-8.2-extension-plus.md)

Occurrences to update:
- Line 187: "Publication draft (workshop or main conference) submitted" → "Publication submitted to ICLR"
- Line 296: "Publication submitted to a top venue (ICML, NeurIPS, or ICLR workshop)" → "Publication submitted to ICLR"
- Line 347: "Indicator: Submitted to top venue" → "Indicator: Submitted to ICLR"

## Files

- `/Users/yulong/writing/apps/todo/toc-diagram.tex` — O2/O3/O4 spacing + O4 text
- `/Users/yulong/writing/apps/todo/mats-8.2-extension-plus.md` — 3 text updates

## Verification

- `pdflatex toc-diagram.tex` compiles without errors
- Visual check: clear gaps between O2, O3, O4 (no border overlap)
- Grep for "top venue" in both files returns zero hits
- All 12 nodes still present and readable
