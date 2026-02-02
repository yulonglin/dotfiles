# Fix Figure Reference Mismatches in Report

## Problem

The LaTeX report references chart files that don't exist:
- References `chart_3_disclosure_distribution.png` → doesn't exist
- References `chart_4_biosafety_gap.png` → doesn't exist

The actual chart files are:
- `chart_3_overall_rankings.png` (exists, shows 7 models)
- `chart_4_framework_gap.png` (exists, shows STREAM vs EU CoP)
- `chart_5_lab_safety_gap.png` (exists, shows lab safety gap)

Also, some text still says "five models" when it should say "seven models".

## Solution

Update LaTeX references to point to the correct existing chart files and fix model count inconsistencies.

## Implementation Steps

### 1. Fix Figure References in report.tex

**Change chart_4 reference (line ~183):**
```latex
# FROM:
\includegraphics[width=0.85\linewidth]{figures/chart_4_biosafety_gap.png}

# TO:
\includegraphics[width=0.85\linewidth]{figures/chart_4_framework_gap.png}
```

**Change chart_3 reference (line ~194):**
```latex
# FROM:
\includegraphics[width=0.85\linewidth]{figures/chart_3_disclosure_distribution.png}

# TO:
\includegraphics[width=0.85\linewidth]{figures/chart_3_overall_rankings.png}
```

### 2. Update Figure Captions to Match Charts

**Update caption for chart_3 (line ~195-197):**
The caption should describe the overall rankings chart, not a distribution chart.

```latex
# FROM (mismatched caption):
\caption{Distribution of disclosure quality across 400 requirement-score pairs...}

# TO (matches chart_3_overall_rankings.png content):
\caption{Overall disclosure quality rankings across seven frontier models, showing Claude Opus 4.5 leading at 80.0\% and substantial variance (42.5 percentage point range).}
```

The caption for chart_4 is already correct for the framework gap chart.

### 3. Fix "Five Models" → "Seven Models"

**Line ~154:**
```latex
# FROM:
...displaying all five frontier models...

# TO:
...displaying all seven frontier models...
```

**Line ~159 (Figure caption):**
```latex
# FROM:
\caption{...showing five frontier models...}

# TO:
\caption{...showing seven frontier models...}
```

### 4. Recompile PDF

```bash
cd /Users/yulong/projects/technical-ai-governance-hackathon/compliance-leaderboard/report
pdflatex -interaction=nonstopmode report.tex
pdflatex -interaction=nonstopmode report.tex  # Run twice for references
```

### 5. Commit Changes

```bash
git add report/report.tex report/report.pdf
git commit -m "Fix figure references and model count in report

- Update chart_3 reference: disclosure_distribution → overall_rankings
- Update chart_4 reference: biosafety_gap → framework_gap
- Fix captions to match actual chart content
- Update 'five models' → 'seven models' throughout
- Recompile PDF with correct figure references"
```

## Critical Files

- `/Users/yulong/projects/technical-ai-governance-hackathon/compliance-leaderboard/report/report.tex` (main file to edit)
- `/Users/yulong/projects/technical-ai-governance-hackathon/compliance-leaderboard/report/figures/` (existing correct charts)

## Verification

After implementation:
1. ✓ PDF compiles without "missing figure" errors
2. ✓ All charts display correctly in PDF
3. ✓ Figure captions accurately describe chart content
4. ✓ All references to model count say "seven"
5. ✓ Visual inspection: charts appear with correct captions

## Why This Works

The charts already have the correct data (7 models from current leaderboard.csv). We're just fixing the LaTeX to reference the correct filenames and updating text to match reality.

No chart regeneration needed - the existing charts are correct!
