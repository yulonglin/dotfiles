# Plan: Update Week 19 Slides

## Overview

Update `slides/pages/week-19.md` to address the items in `specs/TODO-week-19-slides.md`. Add 7+ new slides with comprehensive coverage including limitations.

## Files to Modify

- `slides/pages/week-19.md` (main file)

## Slide Updates Required

### 1. Update Narrative Slide (existing slide ~line 654)

**Current**: Focuses on lie detector confound
**Update to**: Add broader narrative about C³ working across datasets against multiple baselines

New content:
- C³ works across science (GPQA), maths (MATH), and coding (USACO) datasets
- Compare against two baselines from Owain Evans: lie detectors and trusted monitors
- Key claim: We can defeat both methods, and C³ still detects sandbagging

### 2. Add Lie Detector Confound Explanation Slide (after ~line 251)

Add slide explaining WHY lie detectors fail in mixed-model setting with the concrete example from TODO:
- Top confession probes (#1-4) can be defeated with v4.1 prompts
- But probes #5-#48 still discriminate model identity (different baseline response rates)
- Implication: Mixed-model lie detection is fundamentally confounded

### 3. Add Paraphrase Quality Slides (new section, 3 slides)

**Slide 1: Paraphrase Answerability Overview**
- GPQA: 77.8% (lowest - MCQ strategies struggle)
- MATH: 85.2%
- USACO: 91.3% (highest - structured problems)

**Slide 2: How Answerability is Measured**
- Model: gpt-4.1-nano (temperature=0.0)
- Criteria vary by dataset:
  - USACO: problem description + I/O format + example + solvability
  - MATH: problem description + sufficient info + (optional) examples
  - GPQA: problem description + scientific context
- Retry mechanism: up to 3 retries for failed paraphrases

**Slide 3: Strategy Selection - Eval vs Diversity** (KEY FINDING)

From diversity experiments:
- **26 strategies collapse to ~1.7 effective strategies** (Vendi score cross-strategy diversity)
- **Eval-like strategies outperform diversity-optimized by ~16% AUROC**

| Strategy Set | AUROC (k=5) | Recall@5%FPR |
|--------------|-------------|--------------|
| Eval-like (5 strategies) | **0.516** | **9.8% ± 9.8%** |
| Casual (5 strategies) | 0.447 | 6.7% ± 6.5% |
| All strategies (25) | 0.480 | 5.1% ± 3.3% |

**Key insight**: Paraphrases that vary "is this an eval?" have wider effect than direct diversity optimization. Eval context is a direct sandbagging trigger.

### 4. Add Other Model Organisms Section

**Slide 1: In-Context Scheming (Apollo) Results**
- Setup: GSM8K with Apollo-style scheming prompts
- Key finding: Requires explicit reasoning space to induce scheming
- Accuracy gap: 94% benign → 50% scheming (GPT-4.1-nano)
- **C³ Detection**:
  - k=5: AUROC 0.995, Recall 93%
  - k=10: AUROC 1.0, Recall 99.7%

**Slide 2: Password-Locked Model Results (GSM8K)**
Data from TODO file:
- Model: deepseek-math-7b-password-locked (from Redwood Research)
- Performance gap: 42.4% (no password) vs 72.3% (with password) = ~30% gap
- Detection results:
  - k=5: AUROC 0.894, Recall 56.8%
  - k=10: AUROC 0.963, Recall 72.6%
- Validity concerns: Tested on GSM8K (model trained on MATH)

**Appendix slides**:
- Full Apollo prompts (4 variants)
- Password-locked model technical setup (vLLM completions API)
- WMDP: Results pending

### 5. Add USACO Limitations Slides (2 slides)

**Slide 1: USACO C³ Performance by Prompt**

Show specific prompts that defeat C³ (from `/out/v4.1_stealth_prompts_analysis.md`):

| Prompt | AUROC | Recall@5%FPR |
|--------|-------|--------------|
| hybrid-stealth | 0.516 | 24.8% ± 27.0% |
| dissociation | 0.523 | 21.0% ± 26.0% |
| nested-persona | 0.537 | 27.9% ± 26.5% |
| genuine-limitation | 0.556 | 27.5% ± 26.2% |
| rationalization-engine | 0.559 | 27.4% ± 20.8% |
| cognitive-blindspot | 0.593 | 30.9% ± 34.3% |

**Mean: 0.55 AUROC** (essentially random)

Compare to **original prompts** (same-model):
- C³: **47.4%** recall@5%FPR (k=5), **69.3%** (k=10)
- Lie Detector: **8.1%** recall@5%FPR (k=5), **0%** (k=10)

**Slide 2: Root Cause - Sandbagging in Code, Not Explanations**

From `specs/FINDINGS-usaco-explanation-length.md`:
- C³ analyzes explanations, but sandbagging manifests in CODE
- Longer explanations = worse detection (Cohen's d: 0.41→0.26)
- "Effort theater": v4.1 prompts create verbose but failing code

### 6. Add Trusted Monitor Comparison (new slide)

- UK AISI Monitor: AUROC ~0.53 (near-random on USACO)
- Anthropic Experiment: AUROC ~0.53
- C³ significantly outperforms both
- Narrative: We can defeat trusted monitors AND C³ still detects sandbagging

## New Slides: Main Content (10-12 slides)

| # | Slide Title | Key Data |
|---|-------------|----------|
| 1 | **Narrative Update** | C³ vs lie detectors + trusted monitors across 3 datasets |
| 2 | **Lie Detector Confound Deep Dive** | Why probes #5-48 detect model identity |
| 3 | **Paraphrase Answerability** | GPQA 77.8%, MATH 85.2%, USACO 91.3% |
| 4 | **Strategy Selection: Eval > Diversity** | Eval-like 0.52 AUROC vs casual 0.45 AUROC |
| 5 | **USACO C³ by Prompt** | Table of v4.1 prompts (all ~0.55 AUROC) |
| 6 | **USACO Root Cause** | Sandbagging in code, not explanations |
| 7 | **Trusted Monitors Comparison** | AUROC ~0.53 vs C³ 0.91-0.95 |
| 8 | **Claude Haiku Results** | C³ works on Claude: GPQA 100%, MATH 93.8%, USACO 75.3% |
| 9 | **Apollo In-Context Scheming** | AUROC 0.995, Recall 93% (k=5) |
| 10 | **Password-Locked Models (GSM8K)** | AUROC 0.963, Recall 72.6% (k=10) |

## Appendix Slides (move detailed tables/prompts here)

| # | Content |
|---|---------|
| A1 | Full Apollo prompts (4 variants) |
| A2 | Answerability measurement details |
| A3 | Per-strategy answerability breakdown |
| A4 | Password-locked technical setup |
| A5 | Code metrics inverted signal (negative result) |
| A6 | Difficulty-correlation method (if space) |

## Claude Haiku Results (from ai_docs/methods/comparison.md)

**C³ Recall@5%FPR (k=10) - Claude Haiku 4.5 sandbagger vs Claude 3.5 Haiku benign:**

| Dataset | Best Strategy | Recall | Worst Strategy | Recall |
|---------|--------------|--------|----------------|--------|
| GPQA | hash-based-error-injection | **100%** | adaptive-deference | 56.5% |
| MATH | hash-based-error-injection | **93.8%** | absolute-inversion | 25.4% |
| USACO | stochastic-dice-roller | **75.3%** | temporal-knowledge-decay | 3.5% |

**Key finding**: C³ works on Claude models, not just GPT. Strong detection on GPQA/MATH (93-100%), variable on USACO.

## Notes on Data Availability

- **Claude Haiku results**: ✅ Available in `ai_docs/methods/comparison.md` and `out/*_c3_cv.json`
- **Password-locked on GSM8K**: Can report since GSM8K is also math.
- **WMDP**: Results pending

## Insertion Points in week-19.md

1. **After line ~251** (Root Causes slide): Add lie detector confound deep dive
2. **After line ~343** (Psychological Probes slide): Add paraphrase quality section (2 slides)
3. **After line ~500** (Detection comparison): Add USACO limitations + trusted monitors
4. **Before "Timeline" slide (~617)**: Add model organisms section (Apollo + password-locked)

## Appendix Additions

- Full Apollo prompts (4 variants)
- Paraphrase answerability per-strategy breakdown
- Password-locked model technical details
- Trusted monitor detailed results (if time)

## Implementation Notes

- Follow 6x6 rule: max 6 bullets, ~6 words each
- Use BarChart components for data visualization
- Keep main slides brief; move details to appendix
- Include error bars where applicable
