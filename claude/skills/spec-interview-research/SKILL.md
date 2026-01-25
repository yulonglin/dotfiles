---
name: spec-interview-research
description: Interview-based spec development for research experiments. Iteratively questions user about hypotheses, variables, baselines, and resources before writing a complete research specification.
---

# Research Spec Interview

Collaborative interview to develop comprehensive research specifications. Unlike product spec interviews, this focuses on scientific rigor: hypotheses, variables, confounds, baselines, and reproducibility.

## When to Use

- Starting a new research experiment
- Designing A/B tests or ablation studies
- Planning model evaluations or benchmark runs
- Any work requiring statistical validity and reproducibility

## Process

### 1. Introduction
Explain the interview process:
- "I'll ask questions across 15 research categories"
- "We'll start high-level, then drill down on critical decisions"
- "I'll challenge assumptions to strengthen the design"
- "Resource validation runs inline during the interview"

### 2. Conduct Interview

Reference the **research-interview-guide.md** for 15 question categories.

**Interview flow:**
1. **Start high-level**: Get research question, motivation, main hypotheses
2. **Ask 2-4 focused questions per round**: Don't overwhelm with all questions at once
3. **Drill down strategically**: Spend more time on critical variables and confounds
4. **Challenge constructively**:
   - "Why baseline X instead of Y?"
   - "What if confound Z explains your results?"
   - "How confident are you in this assumption?"
5. **Inline resource validation** (Category 11):
   - When discussing resources, check system capabilities immediately
   - Run: `sysctl hw.physicalcpu hw.memsize` (macOS) or `nproc && free -h` (Linux)
   - Compare to stated requirements, warn if insufficient
   - Format: "System has X cores / Y GB, you need A cores / B GB - ✓/⚠"
6. **Iterate until checklist complete**: Ensure all blocking items covered

**Categories to cover** (see research-interview-guide.md for detailed questions):
1. Research Question & Motivation
2. Hypotheses & Falsification
3. Independent Variables (high-level → drill down)
4. Dependent Variables & Metrics
5. Control Variables
6. Confounding Variables
7. Models & Hyperparameters
8. Baselines & Comparisons
9. Datasets
10. Graphs & Visualizations
11. Resources & Validation (inline check)
12. Sample Size & Power
13. Performance & Caching
14. Error Handling & Retries
15. Reproducibility

### 3. Generate Spec

Once interview complete, write spec to `specs/research-interview-$(utc_date).md` using **research-spec-template.md**.

**Spec requirements:**
- Fill all template sections based on interview responses
- Include resource validation results (✓/⚠ marks)
- Complete validation checklist at end
- Keep spec focused (~100-150 lines)
- Use exact user terminology and values

### 4. Review & Iterate

Present spec to user:
- "I've drafted a research spec based on our discussion"
- "Review the validation checklist - any blocking items missing?"
- "What needs clarification or adjustment?"

Make revisions as needed.

## Output Location

`specs/research-interview-DD-MM-YYYY.md` (using current UTC date)

## Key Principles

- **Scientific rigor**: Hypotheses must be falsifiable
- **Explicit assumptions**: Challenge vague or implicit assumptions
- **Resource realism**: Validate requirements against available resources
- **Reproducibility first**: Seeds, versions, logging planned upfront
- **Minimize confounds**: Identify and control alternative explanations

## Example Interaction

```
User: "I want to test if chain-of-thought improves reasoning"