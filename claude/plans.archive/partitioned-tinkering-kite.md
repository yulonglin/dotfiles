# Hackathon Report Plan: AI Safety Compliance Leaderboard

**Goal**: Create a 4-page technical report using ICLR 2026 template targeting maximum judging scores across Impact/Innovation, Execution Quality, and Presentation/Clarity.

---

## Report Structure Overview

### Main Body (4 pages target)
1. **Introduction** (0.5 pages)
   - Problem: AI Lab Watch shutdown + EU Code of Practice enforcement need
   - Challenge: Manual compliance monitoring doesn't scale
   - Contribution: First automated, evidence-based, cross-framework compliance scoring
   - Preview: Leaderboard findings

2. **Methodology** (1.5 pages)
   - Framework operationalization (80 requirements across EU CoP, STREAM, Lab Safety)
   - 3-stage pipeline: claim extraction → scoring → aggregation
   - Validation framework with human agreement metrics

3. **Results** (1.0 page)
   - Leaderboard rankings (Claude Opus 4.5 leads at 69.6%)
   - Framework-specific findings (STREAM biosafety gap identified)
   - Evidence examples with quotes
   - Validation results

4. **Discussion & Limitations** (0.75 pages)
   - Key findings: biosafety disclosure gap, cross-framework variation
   - Limitations: measures disclosure quality not actual compliance, LLM scoring variability
   - Dual-use considerations: gaming risks, regulatory misuse potential
   - System limitations: snapshot data, no longitudinal tracking yet

5. **Conclusion** (0.25 pages)
   - Achievement: scalable transparency monitoring
   - Key finding: biosafety disclosure needs improvement
   - Future: longitudinal tracking, expanded frameworks

### Appendices (unlimited pages)
- A: Complete 80-requirement rubric with scoring guidance
- B: Pipeline prompts (Stage A claim extraction, Stage B scoring)
- C: Model card sources (URLs, snapshot dates)
- D: Validation details (metrics breakdown, disagreement analysis)
- E: Technical implementation (caching, JSON parsing, async concurrency)
- F: Extended results (requirement-level breakdown, statistical analysis)
- G: Limitations of automated scoring (failure modes, edge cases)

---

## Key Figures & Tables

**Main Body Visuals:**

1. **Figure 1** (Introduction): Leaderboard grid screenshot
   - Shows 5 models with rank badges and framework scores (circular gauges)
   - Demonstrates working system and cross-framework variation
   - **ACTION NEEDED**: Request screenshot from user

2. **Figure 2** (Methodology): Pipeline architecture flowchart
   - 3 stages with example inputs/outputs
   - **ACTION**: Create diagram from pipeline.py description

3. **Figure 3** (Results): Cross-framework heatmap
   - 5 models × 3 frameworks with color coding
   - **ACTION**: Create from leaderboard.csv data

4. **Table 1** (Methodology): Validation metrics summary
   - Exact agreement, within-1 agreement, Cohen's kappa, MAE
   - **ACTION**: Compute from validation/human_scores.csv

**Additional Score Visualizations (create all, select best for main body):**

5. **Category breakdown**: Models × Categories (Transparency, Copyright, Security, etc.)
   - **ACTION**: Extract category-level scores from scores.json
   - **Use case**: Shows where disclosure gaps exist beyond framework level

6. **Score distribution histogram**: Frequency of scores (0, 1, 2, 3) across all requirements
   - **ACTION**: Aggregate score counts from scores.json
   - **Use case**: Reveals scoring patterns (e.g., most are partial/2, few thorough/3)

7. **Requirement-level heatmap**: All 80 requirements × 5 models
   - **ACTION**: Create dense heatmap from scores.json
   - **Use case**: Complete picture (likely too dense for main body → Appendix F)

**Selection Strategy**: After creating all visualizations, include in main body those that:
- Add new insights beyond what text/tables convey
- Are visually clear and not overwhelming
- Support judging criteria (show execution quality, reveal patterns)
- Fit within 4-page constraint

**Optional if Space Permits:**
- Box: Example requirement with 4-level scoring (from requirements.json)
- Box: Evidence example with verbatim quote (from scores.json)

---

## Screenshot Requests for User

**Priority 1 (Essential for Figure 1):**
- **Leaderboard Grid**: Full browser window showing main leaderboard page with colorful grid view
  - Must show: All 5 models, rank badges, circular framework gauges
  - Ensure grid is fully rendered (CSS/animations loaded)

**Priority 2 (Useful for appendices/optional figures):**
- **Model Detail Page**: Claude Opus 4.5 deep dive with expanded evidence quotes
- **Validation UI**: Disagreement review interface showing human vs LLM scores
- **Methodology Page**: Framework cards with official links

---

## Content Mapping to Judging Criteria

### Impact & Innovation (Target: 4-5/5)
**Innovation Claims:**
- First automated cross-framework compliance measurement
- Evidence-based scoring (not binary) with quote span extraction
- Addresses AI Lab Watch shutdown gap with scalable alternative

**Impact Demonstration:**
- Scalability: Re-scores on model card updates automatically
- Extensibility: Open-source rubric enables community extension
- Policy relevance: STREAM biosafety disclosure gap finding

### Execution Quality (Target: 4-5/5)
**Methodology Rigor:**
- 80 requirements with detailed 4-level scoring guidance
- 3-stage pipeline with evidence justification at each step
- Validation framework with Cohen's kappa and agreement metrics

**Technical Sophistication:**
- 100 concurrent async API calls with caching
- Robust JSON parsing with multi-level fallbacks
- Quote span extraction with character offsets

**Findings Strength:**
- Concrete cross-framework patterns (EU CoP most disclosed, STREAM has gaps)
- Evidence-quoted scores enable auditability
- Validation quantifies reliability boundaries

### Presentation & Clarity (Target: 4-5/5)
**Visual Communication:**
- Figure 1 immediately shows working system and results
- Figure 2 makes complex pipeline understandable
- Figure 3 reveals cross-framework patterns at a glance

**Writing Clarity:**
- Concrete examples: requirement scoring levels, evidence quotes
- Clear problem statement: AI Lab Watch gap + EU enforcement need
- Honest limitations build credibility

---

## Critical Files Reference

**For Data/Results:**
- `/Users/yulong/projects/technical-ai-governance-hackathon/compliance-leaderboard/results/leaderboard.csv` - Rankings and scores
- `/Users/yulong/projects/technical-ai-governance-hackathon/compliance-leaderboard/results/scores.json` - Detailed evidence (1.2MB)
- `/Users/yulong/projects/technical-ai-governance-hackathon/compliance-leaderboard/validation/human_scores.csv` - Validation data

**For Methodology:**
- `/Users/yulong/projects/technical-ai-governance-hackathon/compliance-leaderboard/data/rubrics/requirements.json` - Complete rubric (95KB, 80 requirements)
- `/Users/yulong/projects/technical-ai-governance-hackathon/compliance-leaderboard/src/pipeline.py` - Pipeline architecture (423 lines)

**Template:**
- `/Users/yulong/Downloads/iclr2026/iclr2026_conference.tex` - LaTeX template
- `/Users/yulong/Downloads/iclr2026/iclr2026_conference.pdf` - Compiled example

**Target Directory:**
- `/Users/yulong/writing/brainstorming/ideas/20260131-204007-technical-ai-governance-hackathon-projects/` - Output location

---

## Implementation Steps

### Step 1: Copy and Set Up LaTeX Project
1. Copy ICLR template files from `/Users/yulong/Downloads/iclr2026/` to target directory
2. Rename `iclr2026_conference.tex` → `compliance_leaderboard_report.tex`
3. Update title and abstract placeholders

### Step 2: Request Screenshots from User
- Ask user to take **leaderboard grid screenshot** (Priority 1)
- Provide clear instructions: "Navigate to main leaderboard page, ensure grid fully renders, full browser window"

### Step 3: Create Figures and Visualizations
- Generate Figure 2 (pipeline flowchart) from pipeline.py description
- Generate Figure 3 (cross-framework heatmap) from leaderboard.csv data
- Compute Table 1 (validation metrics) from human_scores.csv
- **Create additional score visualizations** (category breakdown, score distribution, requirement heatmap)
- **Select 3-4 best visualizations** for main body based on clarity and insight
- Move remaining visualizations to appendices

### Step 4: Write Main Content Sections
- Introduction: Problem statement + contribution + preview
- Methodology: Framework operationalization + pipeline + validation
- Results: Rankings + framework patterns + evidence examples + validation
- Discussion: Findings + limitations (measurement, dual-use, system) + conclusion

### Step 5: Write Appendices
- Appendix A: Full rubric from requirements.json
- Appendix B: Pipeline prompts (extract from pipeline.py or ask user)
- Appendix C: Model card sources from data/model_cards/sources.json
- Appendices D-G: Extended content as outlined

### Step 6: Compile and Review
- Compile LaTeX to verify 4-page main body target
- Check figures render correctly
- Review against judging criteria checklist
- Adjust spacing/content if over/under 4 pages

---

## Space Management Strategies

**If Over 4 Pages:**
1. Move methodology details to appendix (e.g., full prompt text)
2. Reduce Results section: fewer evidence examples, move extended results to Appendix F
3. Tighten Discussion: bullet lists instead of prose for limitations
4. Use dense figure captions to reduce body text

**If Under 4 Pages:**
1. Add second evidence example (high-scoring + low-scoring)
2. Expand Discussion with deeper analysis of findings
3. Add Related Work subsection in Introduction
4. Include more validation details in main body

---

## Verification Checklist

### Content Completeness
- [ ] All 3 judging criteria explicitly addressed
- [ ] Limitations & Dual-Use section included (required)
- [ ] Evidence-based claims (no unsubstantiated assertions)
- [ ] Clear problem statement with governance context
- [ ] Validation results with agreement metrics

### Technical Accuracy
- [ ] All numbers match leaderboard.csv exactly
- [ ] Rubric examples from requirements.json
- [ ] Pipeline description matches pipeline.py implementation
- [ ] Model count accurate (5 models in current leaderboard)

### Presentation Quality
- [ ] 3 figures in main body (leaderboard, pipeline, heatmap)
- [ ] 1 table in main body (validation metrics)
- [ ] Figure captions are descriptive and standalone
- [ ] Section numbering correct
- [ ] References formatted consistently

### LaTeX Compilation
- [ ] PDF compiles without errors
- [ ] Main body ≈4 pages (±0.25 pages acceptable)
- [ ] Appendices correctly labeled (A, B, C...)
- [ ] Figures display at appropriate size
- [ ] No overfull hbox warnings (text overflow)

---

## Open Questions for User

None currently - plan is complete pending screenshot request.

---

## Next Steps After Plan Approval

1. **Immediate**: Request leaderboard grid screenshot from user
2. **Parallel**: Set up LaTeX project in target directory, create figures 2-3 and table 1
3. **Sequential**: Write sections (Introduction → Methodology → Results → Discussion → Appendices)
4. **Final**: Compile, review, adjust spacing, verify against checklist

Estimated time: 3-4 hours for initial draft, 1-2 hours for revision after review.
