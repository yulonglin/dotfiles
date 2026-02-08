# TikZ Theory of Change Diagram for MATS 8.2

## Context
The MATS 8.2 Extension Plus application (due today) requires a one-page PDF Theory of Change diagram. The application text is complete; this is the final artifact. The diagram uses `anthropic-tikz-kit` at `/Users/yulong/Downloads/anthropic-tikz-kit/` for styles and compilation.

Content framing: "consistency-based detection" as the research program, not "C3" specifically. C3 is the current best instantiation, but the ToC should survive if C3 doesn't generalize to research sabotage — the core bet is that consistency signals (behavioral variation across contexts) are a robust detection primitive, and new consistency-based methods can be developed for multi-turn/sabotage settings even if C3's specific implementation needs adaptation.

## Design Principles (from /frontend-design + /ui-ux-pro-max critique)

1. **2-color system** — Activity nodes use `softblue` accent; everything else uses warm neutrals (`warmgray`, `cream`, `lavender`). No 6-color rainbow. The 3 activity streams get subtle differentiation via border weight or icon, not separate fill colors.
2. **Size hierarchy** — Activity nodes are largest (they're what you're doing). Outputs are medium. Outcomes + longer-term are smallest (they're consequences, not actions). This creates natural left-heavy visual weight matching the causal direction.
3. **Column-level flow arrows** — One thick arrow between each column pair (Activities→Outputs→Outcomes→Longer-term) using `arrthick`. Specific node-to-node connections shown as thin `arrbase` lines only where the mapping isn't obvious (e.g., Stream 2 specifically feeds Benchmarks). Eliminates spaghetti.
4. **Indicators inside nodes** — Each node has title on top line, indicator as smaller `annot`-styled text on second line. No separate annotation nodes below. Keeps everything compact.
5. **Proportional column widths** — Activities column is widest (most text). Outputs slightly narrower. Outcomes narrower still. Longer-term narrowest. Approximate x-positions: 0, 7, 13, 18.
6. **Vertical centering** — Each column vertically centered around the same midpoint, not top-aligned. The 2-node right column doesn't float at the top.

## Diagram Structure

**Layout**: Left-to-right flow, landscape letter, one page.

```
  ACTIVITIES (M1-6)        OUTPUTS (M3-6)        OUTCOMES (M6-12)      LONGER-TERM (M12+)
┌──────────────────┐    ┌────────────────┐     ┌───────────────┐     ┌───────────────┐
│ Validate &       │    │ Technical      │     │ Lab adoption  │     │ Safety cases  │
│ Harden           │    │ Report (M3)    │     │               │     │               │
│ Consistency      │    │ ···indicator···│     │ ··indicator·· │     │ ··indicator·· │
│ Methods          │    ├────────────────┤     ├───────────────┤     ├───────────────┤
├──────────────────┤    │ Sabotage       │     │ Auditor       │     │ Sustained     │
│ Extend to        │══> │ Benchmarks     │ ══> │ adoption      │ ══> │ direction     │
│ Research         │    │ (M4-5)        │     │               │     │               │
│ Sabotage         │    │ ···indicator···│     │ ··indicator·· │     │ ··indicator·· │
├──────────────────┤    ├────────────────┤     ├───────────────┤     └───────────────┘
│ Adoption &       │    │ Detection      │     │ Community     │
│ Dissemination    │    │ Toolkit (M5)   │     │ benchmarks    │
│                  │    │ ···indicator···│     │ ··indicator·· │
└──────────────────┘    ├────────────────┤     └───────────────┘
                        │ Publication    │
                        │ (M6)          │
                        │ ···indicator···│
                        └────────────────┘
```

`══>` = thick column-level flow arrows (arrthick)
Plus selective thin arrows for non-obvious connections.

## 12 Nodes

### Activities (3 nodes, left column — `bluebox`, largest)
1. **Validate & Harden Consistency Methods**: Stress-test consistency-based detection on frontier models, adversarial strategies, and confounders (C3 as starting point, develop variants as needed)
2. **Extend to Research Sabotage**: Design sabotage model organisms, build benchmarks, adapt consistency-based detection to multi-turn agentic settings (new methods if C3 doesn't directly transfer)
3. **Adoption & Dissemination**: Present at UK AISI, engage frontier lab safety teams, iterate on toolkit based on practitioner feedback

### Outputs (4 nodes — `graybox`, medium)
A. **Technical Report** (M3): Robustness findings for consistency-based detection + adoption recommendations
   - Indicator: "Delivered to UK AISI + 1 lab"
B. **Sabotage Benchmarks** (M4-5): Research sabotage benchmark suite + detection results (consistency-based and complementary methods)
   - Indicator: "Above chance at 5% FPR"
C. **Detection Toolkit** (M5): Open-source toolkit implementing consistency-based detection for auditors and labs
   - Indicator: "1 external team runs independently"
D. **Publication** (M6): Submitted to top venue
   - Indicator: "Top venue submission"

### Outcomes (3 nodes — `creambox`, smaller)
1. **Lab adoption**: Frontier labs integrate consistency-based monitoring into automated research pipelines
   - Indicator: "1 lab evaluates toolkit"
2. **Auditor adoption**: External auditors add consistency-based methods to evaluation protocols
   - Indicator: "AISI/METR incorporates methods"
3. **Community benchmarks**: Independent teams use research sabotage benchmarks
   - Indicator: "2+ teams use benchmarks"

### Longer-term (2 nodes — `lavbox`, smallest)
4. **Safety cases**: Consistency-based detection contributes to safety cases for deploying AI in research automation
   - Indicator: "Cited in RSP/ASL docs"
5. **Sustained direction**: Researcher placement at safety org or founding of focused research group
   - Indicator: "Placement or org founding"

## Arrow Strategy

**Column-level (thick, `arrthick`):**
- One arrow from Activities column to Outputs column
- One arrow from Outputs column to Outcomes column
- One arrow from Outcomes column to Longer-term column

**Selective node-to-node (thin, `arrbase`):**
- "Extend to Sabotage" → Benchmarks (specific: sabotage work produces the benchmarks)
- "Adoption & Dissemination" → Report, Toolkit (specific: practitioner feedback shapes these)
- Benchmarks → Community benchmarks (specific: direct adoption path)

This gives ~6 arrows total instead of ~15. The column arrows carry the main causal story; node arrows add specificity only where needed.

## Color Palette (simplified)

| Element | Fill | Border | Style |
|---------|------|--------|-------|
| Activities | `softblue` | `deepblue` | `bluebox` |
| Outputs | `warmgray` | `lightgray` | `graybox` |
| Outcomes | `cream` | `deeppeach!50` | `creambox` |
| Longer-term | `lavender` | `deeplavender` | `lavbox` |
| Column headers | — | — | `heading` style |
| Indicators | — | — | `annot` style (inside node) |

4 fills total. Warm progression left-to-right (blue → gray → cream → lavender).

## Implementation Plan

### Step 1: Copy style file
```bash
cp /Users/yulong/Downloads/anthropic-tikz-kit/anthropic-tikz.sty /Users/yulong/writing/apps/todo/
```

### Step 2: Create `/Users/yulong/writing/apps/todo/toc-diagram.tex`
- `\documentclass[tikz,border=5pt]{standalone}` with landscape letter geometry workaround
- Actually: use `\documentclass{article}` with `geometry` package for `landscape,letterpaper,margin=1cm`
- `\usepackage{anthropic-tikz}` (local copy)
- Single `tikzpicture` environment
- Column headers at y=top using `heading` style with timeline labels
- Nodes positioned absolutely:
  - Activities: x=0, y stacked with ~2cm gaps, `text width=4.5cm`
  - Outputs: x=7, y stacked with ~1.5cm gaps, `text width=3.5cm`
  - Outcomes: x=13, y stacked with ~1.5cm gaps, `text width=3.2cm`
  - Longer-term: x=18, y stacked with ~2cm gaps, `text width=3cm`
- Each node: title in `\textbf{}`, indicator below in `{\scriptsize\color{medgray} ...}`
- 3 thick column arrows using `arrthick`
- ~3 thin specific arrows using `arrbase`
- No legend needed — the column headers ARE the legend (color + label)

### Step 3: Compile and iterate
```bash
cd /Users/yulong/writing/apps/todo && pdflatex toc-diagram.tex && open toc-diagram.pdf
```
- Check readability at print size (all text ≥8pt equivalent)
- Check arrows don't overlap nodes
- Check vertical balance across columns
- Ensure fits on one page

## Pre-diagram: Fix related work references in application

Before building the diagram, update the "existing work" section (`mats-8.2-extension-plus.md` lines 89-95) with full links and correct author attributions (paper bib = ground truth):

| Current text | Fix |
|---|---|
| "Benton et al., 2025" | → "Taylor et al., 2025" + link `https://arxiv.org/abs/2512.07810` |
| "Scheurer et al., 2024" | + link `https://arxiv.org/abs/2410.21514` |
| "Jenner et al., ongoing" | → "Hebbar, 2025" + link `https://blog.redwoodresearch.org/p/how-can-we-solve-diffuse-threats` |
| "Control-Z (Greenblatt et al., 2025)" | → "Ctrl-Z" + link `https://arxiv.org/abs/2504.10374` |
| "Trusted monitoring (Greenblatt et al., 2024)" | + link `https://arxiv.org/abs/2312.06942` |
| "Exploration hacking (Brown, Jang, and Falk, MATS 8/8.1)" | → "Braun, Jang, and Falk" + link `https://arxiv.org/abs/2506.14261` |

Must stay within 1,400 character limit after adding links. Run character count verification after edits.

## Files
- **Edit**: `/Users/yulong/writing/apps/todo/mats-8.2-extension-plus.md` — fix related work references
- **Create**: `/Users/yulong/writing/apps/todo/toc-diagram.tex`
- **Copy**: `anthropic-tikz.sty` → `/Users/yulong/writing/apps/todo/`

## Verification
- `pdflatex` compiles without errors
- Output is one landscape page
- All 12 nodes visible with readable titles + indicators
- 3 thick column arrows show left-to-right causal flow
- Selective thin arrows add specificity without clutter
- Size hierarchy: activity nodes visibly larger than outcome nodes
- Vertical centering looks balanced across columns
