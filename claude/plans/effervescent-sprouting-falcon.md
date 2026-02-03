# Fix ICLR 2026 Workshop Submission Formatting Issues

**Created:** 2026-02-02 22:05 UTC
**Updated:** 2026-02-02 22:07 UTC
**Status:** Ready for implementation

---

## Problem Statement

Formatting issues identified by comparing to reference template at `/Users/yulong/Downloads/iclr2026-trustworthy-ai/iclr2026_conference.tex`:

1. **Figure 1 positioned too high**: The `\begin{figure*}[t]` placement after the abstract is causing Figure 1 to appear above the title/author area
2. **Font mismatch**: Reference template uses `times` package for Times New Roman font, but we're not using it
3. **Package loading order**: Reference loads `iclr2026_conference` very early (line 3), we load it after many other packages which could affect style application

---

## Reference Format

From `/Users/yulong/Downloads/iclr2026-trustworthy-ai/iclr2026_conference.tex`:
- **Package line 3**: `\usepackage{iclr2026_conference,times}` - includes Times font
- **Figure placement**: Figures use `[h]` (here) or `[!ht]` positioning and appear WITHIN sections, not immediately after abstract
- **Document structure**: title → abstract → sections → figures within sections

---

## Solution

**Priority**: Both fixes are CRITICAL for matching the reference template formatting.

### Fix 1: Add Times Font Package (CRITICAL)

**Current** (line ~29 in our file):
```latex
\usepackage{iclr2026_conference}
```

**Fixed**:
```latex
\usepackage{iclr2026_conference,times}
```

**Why**: Reference template line 3 uses `\usepackage{iclr2026_conference,times}`. The `times` package loads Times New Roman as the document font, which is the standard for ICLR submissions.

### Fix 2: Move Figure 1 to Introduction Section (CRITICAL)

**Current structure** (lines 60-95 in our file):
```latex
\maketitle

\begin{abstract}
...
\end{abstract}

\begin{figure*}[t]   ← PROBLEM: [t] places at top of page, can appear above title
...
\end{figure*}

\section{Introduction}
```

**Fixed structure**:
```latex
\maketitle

\begin{abstract}
...
\end{abstract}

\section{Introduction}

\begin{figure*}[!ht]   ← MOVED inside Introduction, changed to [!ht] placement
...
\end{figure*}

As language models become more capable...
```

**Changes**:
- Move entire `\begin{figure*}...\end{figure*}` block from after `\end{abstract}` to after `\section{Introduction}`
- Change placement from `[t]` to `[!ht]` (override LaTeX's placement rules, try "here" first, then "top")

**Why**: Reference template places figures WITHIN sections, not between abstract and first section. The `[t]` placement can cause the figure to float above the title in two-column layouts.

---

## Implementation Steps

### Step 1: Add Times Font Package

**File**: `/Users/yulong/writing/papers/sandbagging-detection/workshops/iclr-2026/trustworthy-ai/trustworthy-ai.tex`

Find line containing:
```latex
\usepackage{iclr2026_conference}
```

Replace with:
```latex
\usepackage{iclr2026_conference,times}
```

### Step 2: Move Figure 1 Block

**File**: Same file as above

**Part A - Find and note the figure block**:
The figure block to move starts at approximately line 89:
```latex
\begin{figure*}[t]
\centering
\includegraphics[width=\textwidth]{figures/c3_updated2.png}
\caption{\textbf{C³ detection pipeline.} Given a question, we generate $n$ semantically equivalent paraphrases...}
\label{fig:c3_diagram}
\end{figure*}
```

**Part B - Delete from current location**:
Delete the entire block from its current position (between `\end{abstract}` and `\section{Introduction}`)

**Part C - Insert after Introduction**:
Find the line:
```latex
\section{Introduction}
```

Immediately after this line (before any paragraph text starts), insert:
```latex
\begin{figure*}[!ht]
\centering
\includegraphics[width=\textwidth]{figures/c3_updated2.png}
\caption{\textbf{C³ detection pipeline.} Given a question, we generate $n$ semantically equivalent paraphrases ($n=10$ for MATH/USACO, $n=5$ for GPQA) that vary the evaluation context (e.g., benchmark framing, unmonitored signals, sandbagging awareness). Each paraphrase is sent to a \emph{separate model instance} to prevent coordination. Models produce 5-sentence explanations, which are embedded using OpenAI's text-embedding-3-small. Per-question consistency is the mean pairwise cosine distance across embeddings; model-level classification aggregates scores via bootstrap resampling (k=10 questions). Sandbagging models show higher inconsistency because strategic choices about \emph{how} to appear weak vary across contexts.}
\label{fig:c3_diagram}
\end{figure*}
```

**Note**: Changed `[t]` to `[!ht]` in the placement specifier.

### Step 3: Recompile PDF

```bash
cd /Users/yulong/writing/papers/sandbagging-detection/workshops/iclr-2026/trustworthy-ai

# Clean old build
rm -f trustworthy-ai.aux trustworthy-ai.bbl trustworthy-ai.blg trustworthy-ai.log trustworthy-ai.pdf

# Full compilation (3 passes + bibtex)
pdflatex -interaction=nonstopmode trustworthy-ai.tex
bibtex trustworthy-ai
pdflatex -interaction=nonstopmode trustworthy-ai.tex
pdflatex -interaction=nonstopmode trustworthy-ai.tex
```

### Step 4: Verify Results

Check the generated PDF:
- [ ] Figure 1 appears AFTER the "Introduction" section heading
- [ ] Figure 1 does NOT appear above the title/author
- [ ] Font is Times New Roman (compare body text to reference template PDF)
- [ ] Page count remains ~37 pages
- [ ] No compilation errors in log
- [ ] All other figures still render correctly

---

## Files to Modify

- `/Users/yulong/writing/papers/sandbagging-detection/workshops/iclr-2026/trustworthy-ai/trustworthy-ai.tex`

---

## Detailed Verification

### Visual Comparison with Reference

**To verify formatting matches reference template:**

1. **Compile reference template for comparison**:
   ```bash
   cd /Users/yulong/Downloads/iclr2026-trustworthy-ai
   pdflatex iclr2026_conference.tex
   ```

2. **Compare PDFs side-by-side**:
   - Open both PDFs
   - Check: Font (Times New Roman in both)
   - Check: Title/author formatting
   - Check: Abstract formatting
   - Check: Figure placement (within sections, not floating above title)
   - Check: Section heading styles
   - Check: Citation formatting

3. **Specific checks**:
   - **Page 1 of our PDF**: Title should appear at top, abstract below, then "Introduction" section, then Figure 1
   - **Font test**: Body text should use serifs (Times), not sans-serif
   - **Figure caption**: Should appear BELOW figure, in smaller font
   - **Two-column layout**: Content should span both columns properly

### Verification Checklist

After implementation, verify:
- [ ] Figure 1 appears AFTER "Introduction" section heading (not before)
- [ ] Figure 1 does NOT appear above title/author/abstract
- [ ] Font is Times New Roman (serif body text)
- [ ] PDF compiles without errors
- [ ] Page count ~37 pages (unchanged)
- [ ] No other figures displaced
- [ ] Title/author/abstract formatting matches reference
- [ ] Section headings match reference style (small caps, correct size)

---

## Notes

- The `figure*` environment spans both columns in a two-column layout
- The `[!ht]` placement means: override normal float placement rules, try "here" first, then "top of page"
- Moving the figure into the Introduction section ensures it appears after the title/abstract area
- The `times` package loads Times New Roman font, which is standard for ICLR and most academic conferences
- These are the ONLY two changes needed to match the reference template - our other package usage is valid for our paper's features (algorithms, colored boxes, etc.)

## Expected Outcome

After these fixes:
- PDF will have Times New Roman font throughout (matching reference)
- Figure 1 will appear after Introduction heading, in proper position
- All other content unchanged
- Page count ~37 pages (same as before)
- Formatting will match ICLR 2026 conference style requirements
