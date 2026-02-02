# Plan: 4-Page Hackathon Report for Apart Research Technical AI Governance Hackathon

## Overview

Create a 4-page LaTeX hackathon submission report based on the sandbagging detection research paper, emphasizing governance and auditing applications. The report will use the ICLR2026 conference template and adapt the full research paper to meet hackathon requirements.

## Context

- **Source**: Full research paper at `/Users/yulong/projects/sandbagging-detection/paper/main.tex` (39,800 tokens)
- **Paper title**: "Same Question, Different Lies: Cross-Context Consistency (C³) for Black-Box Sandbagging Detection"
- **Core contribution**: C³ detection method - measures consistency across paraphrased questions to detect sandbagging
- **Template**: ICLR2026 format at `/Users/yulong/Downloads/iclr2026/`
- **Target**: 4-page main content + unlimited appendix
- **Output**: Current directory (sleeper-agent-auditor)
- **Special note**: Acknowledge work was done before hackathon but submitted due to governance relevance

## Judging Criteria Alignment

### 1. Impact Potential & Innovation (Target: 4-5/5)

**Strengths to emphasize**:
- Genuinely novel detection method (C³ asymmetry: honest = consistent, sandbagging = inconsistent)
- Directly addresses critical governance gap: capability evaluation verification
- First black-box, zero-shot, unsupervised sandbagging detector
- Exposes fundamental confounds in prior work (lie detectors learn model identity, not sandbagging)

**Framing**:
- "Meta-evaluation tool: evaluates whether evaluations can be trusted"
- EU AI Act, ASL, Preparedness Framework all rely on honest capability reporting
- C³ enables trust-but-verify approach for auditors

### 2. Execution Quality (Target: 4/5)

**Strengths to emphasize**:
- Rigorous experimental design: same-model setup eliminates confounds
- 98 model organisms (65 original + 33 baseline prompts)
- Multiple datasets (GPQA, MATH, USACO)
- Statistical rigor: bootstrap resampling, threshold calibration, effect sizes
- Honest negative results: adversarial strategies reduce detection to 4.7-46%
- Baseline confound analysis (lie detector collapse: 89% → 2%)

### 3. Presentation & Clarity (Target: 4/5)

**Strategies**:
- Lead with the asymmetry insight: "Same question, different lies"
- Include key visualizations: pipeline, distribution separation, defense-in-depth
- Traffic-light verdict: "67% recall at 5% FPR on USACO"
- Honest limitations prominent, not buried
- Clear governance implications

## Report Structure (4 pages + appendix)

### Main Body (4 pages)

**1. Introduction (0.5 pages)**
- Motivation: Governance frameworks rely on honest capability evaluations
- Problem: Models can strategically underperform (sandbagging)
- Existing approaches fail: lie detectors confounded, monitoring unreliable
- Our contribution: C³ - black-box, zero-shot detection via consistency measurement
- Note: Work completed prior to hackathon; submitted for governance relevance

**2. Method (1 page)**
- C³ framework overview (4-step pipeline)
  1. Generate paraphrases (n=10, 28 strategies)
  2. Collect independent responses (no shared context)
  3. Measure consistency (embedding cosine distance)
  4. Classify via bootstrap aggregation
- Figure 1: C³ pipeline diagram (c3_updated2.png)
- Simple instantiation: text-embedding-3-small, mean aggregation
- Threshold calibration: ≤5% FPR on development set

**3. Experimental Design (0.75 pages)**
- Same-model setup (primary): GPT-5-nano honest vs sandbagging
- Model organisms: 65 prompted sandbaggers + 33 baseline
- Datasets: GPQA (198), MATH (2304), USACO (307)
- Baselines: Trusted Monitoring, Lie Detectors, Behavioral Probes
- Primary metric: Recall at 5% FPR

**4. Results (1.25 pages)**
- Main finding: C³ substantially outperforms baselines
  - USACO: 67% recall (vs 2% lie detectors)
  - Baseline collapse analysis (Figure: lie_detector_confound.png)
- Distribution separation (Figure: gpqa_c3_density.png)
  - Cohen's d ≈ 4.0
- Defense-in-depth (Figure: defense_in_depth.png)
  - No single method dominates
  - Complementary coverage
- Cross-capability generalization (Figure: cross_model_generalization.png)
  - 94-100% on GPQA/MATH
- Sample efficiency: k=10 questions practical
- Adversarial strategies: deterministic error recipes evade C³ (4.7-46%)
  - But trusted monitoring compensates
  - Reinforces defense-in-depth

**5. Governance Implications (0.25 pages)**
- Enables external auditors to verify capability claims
- Black-box only (no weight access required)
- Zero-shot (no per-model calibration)
- Defense-in-depth deployment recommended
- Query-intensive (100+ calls) → targeted auditing

**6. Limitations & Future Work (0.25 pages)**
- Task coverage: only evaluated on benchmarks with verifiable answers
- Untested adversaries: no RL-optimized evasion, no gradient-based attacks
- Query cost: 100+ API calls per evaluation
- Unknown scaling: detection difficulty vs model capability
- Defense-in-depth essential, not standalone solution

### Appendix (Unlimited)

**A. Detailed Results**
- Per-prompt breakdown (all model organisms)
- Additional datasets (GSM8K, WMDP fine-tuned sandbaggers)
- Discovered incentive sandbagging (19% recall)
- Threshold sensitivity analysis
- Aggregation method ablation

**B. Baseline Confound Analysis**
- Lie detector detailed failure modes
- Trusted monitoring failure on GPQA
- Behavioral probes admission rates

**C. Model Organisms**
- Full prompt taxonomy (65 original prompts)
- Error strategy categories
- Stealth variants
- Adversarial strategies

**D. Paraphrasing Strategies**
- 28 strategies across 5 categories
- Example paraphrases

**E. Implementation Details**
- Embedding model choice
- Bootstrap parameters (1000 iterations, k=10)
- API call structure (separate instances)

**F. Limitations & Dual-Use Considerations** (per hackathon requirements)
- False positives/negatives: 5% FPR by design, recall varies 4.7-95%
- Dual-use risk: Could train better sandbaggers using C³ as fitness signal
- Mitigation: Detection methods already public in research literature
- Net assessment: Defensive value >> offensive risk
- Responsible disclosure: Would contact providers before publishing discoveries

## Critical Files to Create/Copy

1. **report.tex** (main report file)
   - Based on iclr2026_conference.tex structure
   - 4-page main body
   - Appendix sections

2. **report.bib** (bibliography)
   - Copy relevant entries from main.bib
   - Add hackathon-specific citations if needed

3. **figures/** (directory)
   - Copy from /Users/yulong/projects/sandbagging-detection/paper/figures/
   - Required figures:
     - c3_updated2.png (pipeline)
     - gpqa_c3_density.png (distribution)
     - defense_in_depth.png (complementary methods)
     - cross_model_generalization.png (cross-capability)
     - lie_detector_confound.png (baseline failure)
     - gpqa_k_sweep_per_prompt.png (sample efficiency)

4. **Template files** (copy from /Users/yulong/Downloads/iclr2026/)
   - iclr2026_conference.sty
   - iclr2026_conference.bst
   - fancyhdr.sty
   - natbib.sty
   - math_commands.tex

5. **Makefile** (for building)
   - pdflatex report.tex
   - bibtex report
   - pdflatex report.tex (twice)

## Writing Approach

### Phase 1: Setup (15 minutes)
1. Copy ICLR2026 template files to current directory
2. Copy required figures from sandbagging-detection/paper/figures/
3. Create report.tex skeleton with sections
4. Copy relevant bibliography entries to report.bib

### Phase 2: Content Adaptation (2 hours)
1. **Introduction**: Adapt from paper intro, emphasize governance angle
   - Add hackathon disclaimer: "Work completed prior to event; submitted for governance relevance"
   - Reframe motivation around EU AI Act, ASL, Preparedness Framework
   - Lead with asymmetry insight

2. **Method**: Condense from 4 pages to 1 page
   - Keep 4-step pipeline clear
   - Include pipeline figure
   - Cut mathematical details (move to appendix)
   - Emphasize zero-shot, black-box nature

3. **Experimental Design**: Compress from 3 pages to 0.75 pages
   - Keep same-model setup explanation (key to avoiding confounds)
   - Summarize model organisms
   - List datasets with sample counts
   - Mention baselines briefly

4. **Results**: Compress from 8 pages to 1.25 pages
   - Lead with main finding (67% vs 2%)
   - Include 3-4 key figures
   - Emphasize baseline confound discovery
   - Brief mention of adversarial evasion
   - Defense-in-depth takeaway

5. **Governance Implications**: New section (0.25 pages)
   - External auditor capabilities
   - Trust-but-verify approach
   - Deployment recommendations
   - Practical constraints (query cost)

6. **Limitations**: Condense from 2 pages to 0.25 pages
   - Keep honest about adversarial evasion
   - Task coverage limitations
   - Untested adversaries
   - Defense-in-depth necessity

### Phase 3: Appendix (1 hour)
- Copy detailed results tables
- Full prompt catalogue
- Detailed baseline analysis
- Implementation details
- Limitations & dual-use section (mandatory per hackathon rules)

### Phase 4: Polish (30 minutes)
- Check 4-page limit (excluding appendix)
- Verify all figures render correctly
- Proofread for governance framing consistency
- Ensure limitations are prominent
- Add hackathon disclaimer in clear location

## Page Budget Breakdown

| Section | Target Pages | Key Content |
|---------|-------------|-------------|
| Introduction | 0.5 | Motivation, contribution, hackathon note |
| Method | 1.0 | 4-step pipeline, Figure 1, instantiation |
| Experimental Design | 0.75 | Same-model setup, organisms, datasets |
| Results | 1.25 | Main findings, 4-5 figures, baselines, adversarial |
| Governance Implications | 0.25 | Auditor capabilities, deployment |
| Limitations & Future Work | 0.25 | Honest negative results, open problems |
| **Total** | **4.0** | Main body |
| Appendix | Unlimited | Detailed results, prompts, analysis |

## Key Messages for Hackathon Judges

1. **Innovation**: C³ asymmetry is genuinely novel; baseline confound discovery is important
2. **Impact**: Addresses critical governance gap in capability evaluation verification
3. **Execution**: Rigorous experimental design, honest limitations, defense-in-depth insight
4. **Presentation**: Clear governance framing, visual results, prominent limitations
5. **Honesty**: Work done before hackathon, adversarial evasion acknowledged, defense-in-depth essential

## Verification Steps

Before considering complete:
1. PDF compiles successfully
2. Main body ≤ 4 pages (excluding references and appendix)
3. All figures display correctly
4. Hackathon disclaimer present and clear
5. Limitations section prominent (not buried)
6. Dual-use considerations in appendix
7. Governance framing consistent throughout
8. Bibliography complete and formatted correctly

## Next Steps After Report Completion

1. Generate PDF: `make` or `pdflatex report.tex && bibtex report && pdflatex report.tex && pdflatex report.tex`
2. Verify page count
3. Optional: Copy to /Users/yulong/Downloads/iclr2026/ if needed for submission
4. Optional: Create presentation slides if required
5. Optional: Record demo video (per judging criteria)
