# Implementation Plan: ICLR 2026 Trustworthy AI Workshop Submission (REVISED)

**Created:** 2026-02-02 21:30 UTC (Deadline: Feb 2 AoE - TODAY)
**Track:** Long (9 pages, excluding references)
**Workshop:** Inference-Time Safety and Monitoring

---

## Executive Summary

**WHAT WENT WRONG:**
- I edited the existing short `trustworthy-ai.tex` (190 lines, 1 figure) instead of copying the full `main.tex` (1494 lines, 18+ figures)
- Result: 6-page paper missing appendix, most figures, and detailed results

**CORRECTED APPROACH:**
1. **OVERWRITE** trustworthy-ai.tex with the FULL main.tex (1494 lines)
2. Make 5 minimal edits for ICLR style
3. Use symlinks/latexmkrc to reuse figures, .bib, math_commands.tex
4. Compile full paper (no cutting)

**Key edits:**
1. `\usepackage{icml2026}` → `\usepackage{iclr2026_conference}`
2. Replace ICML author block (lines 59-100) with simple ICLR title/author
3. Remove `\vskip -0.2in` spacing
4. Add "inference-time" keywords in 2-3 places
5. `\bibliographystyle{icml2026}` → `\bibliographystyle{iclr2026_conference}`

**Page limit:**
- Workshop limit = **9 pages** (main body only, **excluding references AND appendix**)
- Full main.tex = 30 pages ICML (includes large appendix)
- Main body alone is likely ~8-10 pages → should fit within limit
- ⚠️ **DO NOT CUT ANY CONTENT** - compile the full paper as-is including appendix

---

## Step 1: Copy main.tex Exactly

⚠️ **CRITICAL**: Do NOT edit the existing `trustworthy-ai.tex` in the workshop directory. It's only 190 lines (truncated version). We need the FULL `main.tex` which is 1494 lines.

**Critical Files:**
```bash
# Base directory
cd /Users/yulong/writing/papers/sandbagging-detection/

# OVERWRITE the existing trustworthy-ai.tex with the FULL main.tex
cp -f main.tex workshops/iclr-2026/trustworthy-ai/trustworthy-ai.tex

# Verify you copied the full version
wc -l workshops/iclr-2026/trustworthy-ai/trustworthy-ai.tex  # Should show ~1494 lines, not 190

# Copy ICLR style files from template
cp /Users/yulong/Downloads/iclr2026-trustworthy-ai/iclr2026_conference.sty workshops/iclr-2026/trustworthy-ai/
cp /Users/yulong/Downloads/iclr2026-trustworthy-ai/iclr2026_conference.bst workshops/iclr-2026/trustworthy-ai/
cp /Users/yulong/Downloads/iclr2026-trustworthy-ai/fancyhdr.sty workshops/iclr-2026/trustworthy-ai/
cp /Users/yulong/Downloads/iclr2026-trustworthy-ai/natbib.sty workshops/iclr-2026/trustworthy-ai/

# Copy shared files to directory (don't use latexmkrc)
cp src/math_commands.tex workshops/iclr-2026/trustworthy-ai/
cp main.bib workshops/iclr-2026/trustworthy-ai/
cp src/icml2026.bst workshops/iclr-2026/trustworthy-ai/
```

**Result:** Full paper content ready for minimal edits

---

## Step 2: Minimal Edits to trustworthy-ai.tex

**Edit 1: Change document class/style**
```latex
% Line ~29 - Change from ICML to ICLR
% OLD:
\usepackage{icml2026}

% NEW:
\usepackage{iclr2026_conference}
```

**Edit 2: Update author/title section for ICLR format**

Lines 59-120 have ICML-specific author formatting. Replace the entire block:

```latex
% DELETE lines 59-100 (everything from \icmltitlerunning to \printAffiliationsAndNotice)
% This includes:
%   - \icmltitlerunning{...}
%   - \twocolumn[...]
%   - \icmltitle{...}
%   - \begin{icmlauthorlist}...\end{icmlauthorlist}
%   - \icmlaffiliation{...}
%   - \icmlcorrespondingauthor{...}
%   - \icmlkeywords{...}
%   - \vskip 0.3in
%   - ]
%   - \printAffiliationsAndNotice{}

% REPLACE with ICLR format (insert before line 102 \begin{abstract}):
\title{Same Question, Different Lies: Cross-Context Consistency (C³) for Inference-Time Sandbagging Detection}
\author{Anonymous}

\begin{document}

\maketitle
```

Note: Do NOT add `\iclrfinalcopy` - that's for camera-ready submissions. We want anonymous review submission.

**Edit 3: Remove ICML-specific spacing**
```latex
% Line 120 - Remove ICML vertical skip
% DELETE:
\vskip -0.2in
```

**Edit 4: Add "inference-time" keywords (3-5 places)**

In Abstract (line 108):
```latex
% Change:
a general framework for unsupervised black-box sandbagging detection

% To:
a general framework for unsupervised inference-time black-box sandbagging detection
```

In Introduction (after line 154, before "We develop..."):
```latex
% ADD this paragraph:
Inference-time detection is especially critical for deployment auditing, where safety decisions must be made during evaluation windows measured in days~\citep{phuong2024-dangerous-capabilities}. As a query-based monitoring mechanism, C³ requires no model retraining or white-box access, enabling deployment by external auditors during capability evaluations.
```

**Edit 5: Fix bibliography style**
```latex
% Line 541 - change bibliography style
\bibliographystyle{iclr2026_conference}  % was: icml2026
```

**That's it for content edits. Now we need to handle the page limit.**

**That's it. No content cutting - compile the full paper.**

---

## Step 3: Fix Figure Paths

**Problem:** Figures currently use relative path `figures/` which won't work from workshop subdirectory.

**Solution:** Copy figures directory OR create symlink

**Option A: Symlink (cleaner)**
```bash
cd workshops/iclr-2026/trustworthy-ai/
ln -s ../../../figures figures
```

**Option B: Copy figures (safer for compilation)**
```bash
mkdir -p workshops/iclr-2026/trustworthy-ai/figures/
cp figures/*.png workshops/iclr-2026/trustworthy-ai/figures/
```

**Verify figures exist in main.tex:**
- `c3_updated2.png` - C³ pipeline (Figure 1) - CRITICAL
- `defense_in_depth.png` - Defense in depth
- `gpqa_c3_density.png` - Score distributions
- `lie_detector_confound.png` - Identity confound - CRITICAL
- `gpqa_k_sweep_per_prompt.png` - Sample efficiency
- Plus all other figures referenced

**No changes to .tex file needed** - paths stay as `figures/filename.png`

---

## Step 4: Compilation

**Commands:**
```bash
cd /Users/yulong/writing/papers/sandbagging-detection/workshops/iclr-2026/trustworthy-ai/

# Clean previous build
rm -f trustworthy-ai.aux trustworthy-ai.bbl trustworthy-ai.blg trustworthy-ai.log trustworthy-ai.pdf

# Compile (3 passes for cross-references)
pdflatex trustworthy-ai.tex
bibtex trustworthy-ai
pdflatex trustworthy-ai.tex
pdflatex trustworthy-ai.tex

# Check page count
echo "Page count:"
tail -20 trustworthy-ai.log | grep "Output written"
```

**Expected outcome:**
- PDF compiles successfully
- All ~18 figures render correctly
- All citations resolve
- No compilation errors
- Page count: **likely 20-30 pages** (main.tex is 30 pages in ICML format, mostly appendix)
- User will handle any content decisions about workshop page limits

---

## Step 5: Verification Checklist

After compilation, verify:

**Page Count:**
- [ ] Main body (before appendix) ≤ 9 pages
- [ ] Appendix and references don't count toward limit
- [ ] Report total page count for user's information

**Figures:**
- [ ] Figure 1 (c3_updated2.png) renders - C³ pipeline diagram
- [ ] lie_detector_confound.png renders - CRITICAL for baseline analysis
- [ ] defense_in_depth.png renders
- [ ] All other figures from main.tex render correctly
- [ ] All figures have white backgrounds

**Citations:**
- [ ] Bibliography compiles (no "undefined citation" errors)
- [ ] Uses iclr2026_conference.bst style

**Content:**
- [ ] Abstract includes "inference-time" keyword
- [ ] Introduction mentions deployment/monitoring context
- [ ] Anonymous (no author names visible)

**Formatting:**
- [ ] No overfull hbox warnings > 10pt
- [ ] Two-column layout
- [ ] ICLR conference style applied

---

## Step 6: Final Summary Document

Create submission-ready summary:

**workshops/iclr-2026/trustworthy-ai/SUBMISSION_READY.md:**
- PDF location and page count
- Workshop theme alignment
- Key changes from main.tex
- Figures included
- Compilation status
- OpenReview submission instructions

---

## Summary of Changes from Main Paper

**Minimal edits only:**

1. **Style change**: `icml2026` → `iclr2026_conference`
2. **Author format**: ICML multi-author block → ICLR simple anonymous
3. **Keywords added**: 3-5 mentions of "inference-time" for workshop theme
4. **Bibliography style**: `icml2026.bst` → `iclr2026_conference.bst`

**Content preserved (ALL of main.tex):**
- ✅ All sections: Introduction, Method, Results, Limitations, Related Work, Conclusion
- ✅ All ~18 figures (c3_updated2.png, lie_detector_confound.png, etc.)
- ✅ All results tables and detailed experimental sections
- ✅ Impact Statement
- ✅ Full Appendix section (doesn't count toward 9-page limit)

**Expected compilation:** 20-30 pages total (main body ~8-10 pages + appendix ~12-20 pages)
**Fits within workshop limit:** Yes (9 pages for main body, appendix excluded)

---

## Critical Files Summary

**To modify:**
- `workshops/iclr-2026/trustworthy-ai/trustworthy-ai.tex` (4 edits only)

**To copy:**
- From `/Users/yulong/Downloads/iclr2026-trustworthy-ai/`: style files
- From project root: `main.tex`, `main.bib`, `src/math_commands.tex`
- From `figures/`: all PNG files OR create symlink

**Final directory structure:**
```
workshops/iclr-2026/trustworthy-ai/
├── trustworthy-ai.tex              # Main paper (main.tex with 4 edits)
├── trustworthy-ai.pdf              # Compiled output
├── iclr2026_conference.sty         # ICLR style
├── iclr2026_conference.bst         # ICLR bibliography
├── fancyhdr.sty, natbib.sty        # Supporting
├── math_commands.tex               # Shared notation
├── main.bib                        # Bibliography
└── figures/                        # Symlink or copy of ../../../figures/
    ├── c3_updated2.png
    ├── lie_detector_confound.png
    └── [all other figures]
```
