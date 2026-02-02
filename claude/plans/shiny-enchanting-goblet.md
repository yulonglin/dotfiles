# Plan: Paper Reorganization + Chart Generation (7→5 Pages)

## Overview
Streamline the ICLR 2026 paper from 7 to 5 pages by:
1. Fixing URL formatting in title footnote
2. Installing matplotlib and generating 5 bar charts
3. Moving ~2 pages of content to appendices
4. Replacing tables with bar charts

---

## Task 1: Fix URL Formatting in Title Footnote

**File:** `report/report.tex` (line 48-49)

**Current:**
```latex
\thanks{Research conducted at Technical AI Governance Challenge, 2026. Apart Research sprint and leaderboard available at \url{https://apartresearch.com/sprints/the-technical-ai-governance-challenge-2026-01-30-to-2026-02-01}. Code: \url{https://github.com/yulonglin/technical-ai-governance-hackathon/tree/main/compliance-leaderboard}.}
```

**Change to:**
```latex
\thanks{Research conducted at \href{https://apartresearch.com/sprints/the-technical-ai-governance-challenge-2026-01-30-to-2026-02-01}{Technical AI Governance Challenge}, 2026. Code: \url{https://github.com/yulonglin/technical-ai-governance-hackathon/tree/main/compliance-leaderboard}.}
```

**Rationale:** Cleaner presentation - hyperlink the text instead of showing full URL.

---

## Task 2: Install matplotlib and Generate Bar Charts

**Step 2.1: Add matplotlib to dependencies**
- Already done: `pyproject.toml` line 9 has `matplotlib>=3.8.0`

**Step 2.2: Install matplotlib in venv**
```bash
.venv/bin/python -m pip install matplotlib
```

**Step 2.3: Run chart generation**
```bash
.venv/bin/python report/generate_charts.py
```

**Expected outputs** (5 PNG files in `report/figures/`):
- `chart_1_validation_agreement.png` - Validation metrics by framework
- `chart_2_framework_scores.png` - Framework scores across models
- `chart_3_disclosure_distribution.png` - Distribution of 0-1-2-3 scores
- `chart_4_biosafety_gap.png` - EU CoP vs STREAM gap per model
- `chart_5_agreement_by_level.png` - Validation agreement by score level

---

## Task 3: Move Content to Appendix (~450 lines → 2 pages)

### 3.1 Evidence Examples Section → Appendix F

**Move from main paper (lines 201-228):**
- Section 3.4 Evidence Examples
- Example 1: Thorough Score (Claude Opus 4.5)
- Example 2: Mentioned Score (Gemini 2.5)

**Replace with (in main paper):**
```latex
Evidence examples demonstrating the 0-3 scoring scale are provided in Appendix F.
```

**Add to Appendix F (after line 426):**
```latex
\section{Evidence Examples}
\label{app:evidence-examples}

[Move full content of Section 3.4 here, including both examples with evidence quotes]
```

---

### 3.2 Dual-Use Considerations → Appendix G

**Move from main paper (lines 270-282):**
- Section 4.4 Dual-Use Considerations
- Three bullet points: regulatory capture, performative compliance, information extraction

**Replace with (in main discussion):**
```latex
\subsection{Dual-Use Considerations}
This system has legitimate accountability purposes but also dual-use risks (regulatory capture, performative compliance, information extraction). We recommend use as a diagnostic tool, not compliance certification. See Appendix G for detailed dual-use analysis.
```

**Add to Appendix G (create new section after Appendix F):**
```latex
\section{Dual-Use Considerations}
\label{app:dual-use}

[Move full Dual-Use section content here with expanded discussion]
```

---

### 3.3 Implications Section → Appendix H

**Move from main paper (lines 284-294):**
- Section 4.5 Implications
- Recommendations for developers, regulators, researchers

**Replace with (in Conclusion):**
```latex
The biosafety disclosure gap suggests opportunities for developers to expand biosafety sections, for regulators to include STREAM ChemBio in official guidance, and for researchers to develop better biosafety assessment frameworks. See Appendix H for detailed recommendations.
```

**Add to Appendix H (create new section after Appendix G):**
```latex
\section{Recommendations and Implications}
\label{app:recommendations}

[Move full Implications section content here]
```

---

### 3.4 Condense Validation Results Section

**Current (lines 229-236):**
Full table + detailed metrics

**Replace with:**
```latex
\subsection{Validation Results}

Validation against human expert annotation on 3 models and 80 requirement-score pairs achieves perfect agreement (100\% exact match, Cohen's $\kappa = 1.0$, MAE = 0.0). Agreement holds across all frameworks and score levels. See Appendix D for detailed breakdown.
```

**Keep:** Table in Appendix D (already there)

---

### 3.5 Condense Disclosure Patterns Section

**Current (lines 190-200):**
Detailed percentages for all 4 score levels

**Replace with:**
```latex
\subsection{Disclosure Patterns}

Analyzing 400 requirement-score pairs: most disclosures are Partial (32.5\%) or Mentioned (31.5\%), with 29.2\% Thorough and only 6.8\% Not Mentioned. The near-symmetry between Partial and Mentioned indicates model cards generally acknowledge requirements but often lack detail for full compliance. See Appendix F for detailed distribution.
```

---

### 3.6 Condense Framework-Level Analysis

**Current (lines 174-188):**
Three bullet points with detailed percentages per framework

**Replace with:**
```latex
\subsection{Framework-Level Analysis}

Disclosure quality varies by framework: EU Code of Practice (64.3\%) shows most consistent disclosure, STREAM ChemBio (59.8\%) reveals a biosafety disclosure gap, and Lab Safety (57.3\%) shows highest variance (35-78\% range). All five models show a consistent pattern: STREAM scores trail EU CoP by average 4.6 percentage points—a systematic gap, not individual weakness. See Appendix F for detailed framework breakdown.
```

---

### 3.7 Remove Figure 7 from Main Text

**Remove (lines 170-177):**
```latex
\begin{figure}[h]
\centering
\includegraphics[width=0.95\linewidth]{figures/figure_7_methodology_page.png}
\caption{...}
\label{fig:methodology-visual}
\end{figure}
```

**Rationale:** Methodology already described in text (Section 2). Move to Appendix E if needed.

---

## Task 4: Replace Tables with Bar Charts

### 4.1 Replace Table 1 (Validation Metrics)

**Current:** `figures/table_1_validation.tex` (lines 232)

**Replace with:**
```latex
\begin{figure}[h]
\centering
\includegraphics[width=0.8\linewidth]{figures/chart_1_validation_agreement.png}
\caption{Validation agreement metrics by framework, showing perfect agreement (100\%) across EU CoP, STREAM ChemBio, and Lab Safety.}
\label{fig:validation-chart}
\end{figure}
```

### 4.2 Replace Figure 3 (Cross-Framework Table)

**Current:** `figures/figure_3_cross_framework_table.tex` (line 166)

**Replace with:**
```latex
\begin{figure}[h]
\centering
\includegraphics[width=0.95\linewidth]{figures/chart_2_framework_scores.png}
\caption{Framework scores across five frontier models. Claude Opus 4.5 leads with 69.6\% overall. Consistent biosafety disclosure gap visible: STREAM scores (red bars) trail EU CoP scores (green bars) by average 4.6pp across all models.}
\label{fig:framework-scores}
\end{figure}
```

### 4.3 Add New Biosafety Gap Chart

**Insert after biosafety discussion (line 185):**
```latex
\begin{figure}[h]
\centering
\includegraphics[width=0.85\linewidth]{figures/chart_4_biosafety_gap.png}
\caption{Biosafety disclosure gap: difference between EU CoP and STREAM ChemBio scores. Positive values (blue) indicate EU CoP leads; negative (red) indicates STREAM leads. Average gap: 4.6 percentage points.}
\label{fig:biosafety-gap}
\end{figure}
```

---

## Task 5: Update Appendix Structure

**New appendix order:**
- Appendix A: Complete 80-Requirement Rubric (existing)
- Appendix B: Pipeline Prompts (existing)
- Appendix C: Model Card Sources (existing)
- Appendix D: Validation Details (existing, keep detailed table)
- Appendix E: Technical Implementation (existing, add pipeline figure if removed from main)
- **Appendix F: Evidence Examples** (NEW - moved from Section 3.4)
- **Appendix G: Dual-Use Considerations** (NEW - moved from Section 4.4)
- **Appendix H: Recommendations and Implications** (NEW - moved from Section 4.5)
- Appendix I: Extended Results (existing F)
- Appendix J: Limitations (existing G, merge with some dual-use content)

---

## Verification

**Step 1: Compile LaTeX**
```bash
cd report
pdflatex report.tex
bibtex report
pdflatex report.tex
pdflatex report.tex
```

**Step 2: Check page count**
```bash
pdfinfo report.pdf | grep Pages
```
- Target: 5 pages (main paper) + appendices
- Current: 7 pages → should reduce to 5

**Step 3: Verify charts generated**
```bash
ls -lh figures/chart_*.png
```
- Should see 5 PNG files, each ~100-300KB

**Step 4: Visual inspection**
- Check that URLs render as hyperlinks, not raw text
- Check that bar charts display clearly
- Check that moved content appears in new appendix sections
- Check that references update correctly (Appendix F, G, H)

---

## Critical Files

**To modify:**
1. `report/report.tex` - Main reorganization
2. `pyproject.toml` - Already has matplotlib

**To execute:**
1. `report/generate_charts.py` - Chart generation script

**Generated outputs:**
1. `report/figures/chart_1_validation_agreement.png`
2. `report/figures/chart_2_framework_scores.png`
3. `report/figures/chart_3_disclosure_distribution.png`
4. `report/figures/chart_4_biosafety_gap.png`
5. `report/figures/chart_5_agreement_by_level.png`

---

## Estimated Savings Breakdown

| Change | Lines Removed | Lines Added | Net Savings |
|--------|---------------|-------------|-------------|
| Evidence Examples → Appendix F | ~28 | ~2 | 26 lines |
| Dual-Use → Appendix G | ~13 | ~4 | 9 lines |
| Implications → Appendix H | ~11 | ~3 | 8 lines |
| Condense Validation | ~9 | ~4 | 5 lines |
| Condense Disclosure Patterns | ~12 | ~5 | 7 lines |
| Condense Framework Analysis | ~8 | ~5 | 3 lines |
| Remove Figure 7 | ~7 | ~0 | 7 lines |
| **Total** | **~88 lines** | **~23 lines** | **~65 lines** |

**Additional space from tables→charts:**
- Table 1: ~15 lines → 8 lines (figure) = 7 lines saved
- Figure 3 table: ~20 lines → 8 lines (figure) = 12 lines saved

**Total savings: ~84 lines ≈ 1.5-2 pages**

This should comfortably bring the paper from 7 to 5 pages while preserving all content in appendices.
