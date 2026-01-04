# [Research Task Name] Specification

**Date**: [YYYY-MM-DD]
**Author**: [Your Name]
**DRI (Directly Responsible Individual)**: [Name if different from author]
**Status**: Ideation / Exploration / Understanding / Distillation
**Research Mode**: De-risk Sprint / Extended Project
**Timeline**: [Expected duration]

---

## Quick Start: Most Important Questions

*For rapid project scoping via speech-to-text brain dump. Answer these ~10 questions to capture your core ideas, then use AI to expand into full spec.*

1. **What specific question are you trying to answer?** What would change if you had the answer?

2. **Why should anyone care?** How does this lead to real-world impact? (Your theory of change)

3. **What's your riskiest assumption?** What needs to be true for your approach to work? How will you test it quickly (<1 day)?

4. **What stage are you in?**
   - Ideation: Still choosing the problem
   - Exploration: Don't know the right questions yet, need to play around
   - Understanding: Have hypotheses to test systematically
   - Distillation: Have results to write up

5. **What's your first experiment?** The quickest test that could invalidate your whole approach. What would you learn?

6. **What does success look like?** Specific, measurable outcome in [timeline]. Not "understand X better" but "show Y improves by Z%"

7. **What's your competition?** Strong baselines you must beat. What would a skeptical reviewer compare your work against?

8. **What resources do you need?** Compute (GPUs?), data access, collaborator skills, time budget

9. **What could go wrong?** Top 2-3 risks. For each: How likely? How bad? How will you know early? What's plan B?

10. **Who's your audience?** Conference/journal? Blog post? Policy brief? What decision are they making that your research informs?

**Brain Dump Tips**:
- Talk through these naturally, don't overthink
- Include uncertainties ("I'm not sure but maybe...")
- Mention related work you know about
- Describe your excitement and concerns
- ~20-30 minutes total

---

## 1. Problem Statement & Theory of Change

### Core Research Question
[What specific question are you trying to answer? Be precise, measurable, and action-relevant.
Ask yourself: "If I answer this, what will change?"]

### Theory of Change
[How will answering this question lead to real-world impact? What's your causal chain from research → knowledge → action → impact?]

### Why This Matters (Motivation)
[Brief context about importance. Address: Why should anyone care? What problem does this solve? How does it fit the bigger picture?]

### Is This the Right Question?
- [ ] **Action-relevant**: Would the answer change any important decisions?
- [ ] **Neglected**: Are others already solving this well?
- [ ] **Tractable**: Can we make meaningful progress in [timeline]?
- [ ] **Important**: Does this matter for [specific impact area]?

### Success Criteria (Measurable)
- [ ] [Specific claim we'll have evidence for]
- [ ] [Concrete metric or threshold we'll achieve]
- [ ] [Deliverable that demonstrates understanding]

## 2. Critical Assumptions to Validate

### Core Assumptions
[List assumptions that, if false, would invalidate your approach]
1. **Assumption**: [What needs to be true]
   - **Why critical**: [What fails if this is false]
   - **Validation method**: [How to test quickly]
   - **Backup plan**: [What to do if false]

2. **Assumption**: [What needs to be true]
   - **Why critical**: [What fails if this is false]
   - **Validation method**: [How to test quickly]
   - **Backup plan**: [What to do if false]

### Known Failure Modes to Avoid
- [ ] **Scaling/Bitter Lesson**: Is my approach robust to scale, or fighting fundamental trends?
- [ ] **Unrealistic Assumptions**: Am I assuming things that won't hold in practice?
- [ ] **Cherry-picking**: Am I designing experiments that could mislead through selection?
- [ ] **Weak Baselines**: Do I have strong baselines that actually test my contribution?

## 3. Research Stages & Technical Approach

### Current Stage: [Ideation/Exploration/Understanding/Distillation]

### Stage-Specific Plan

#### Exploration Phase (Gain Surface Area)
**North Star**: Maximize information gain per unit time
- [ ] Quick experiments to test core assumptions (<1 day feedback loops)
- [ ] Explore multiple hypotheses in parallel
- [ ] Keep highlights doc of interesting observations
- [ ] Visual exploration of data/results from many angles

#### Understanding Phase (Test Hypotheses)
**North Star**: Find convincing evidence for specific claims
- [ ] Design experiments that distinguish between hypotheses
- [ ] Implement strong baselines for comparison
- [ ] Quantitative evaluation with statistical rigor (p < 0.001 for exploratory)
- [ ] Systematic ablation studies

#### Key Technical Components
1. **[Component 1]**: [Why needed + quick validation test]
2. **[Component 2]**: [Why needed + quick validation test]
3. **[Component 3]**: [Why needed + quick validation test]

### Data Requirements
- **Source & Quality**: [Where from? How reliable? Biases?]
- **Size for Signal**: [Minimum N for statistical power]
- **Preprocessing**: [What's needed? How long?]
- **Access**: [Any blockers? IRB? Compute?]

## 4. De-risking & Experimental Design

### Information-Theoretic Prioritization
[Order experiments by information gain per unit time]

| Experiment | Info Gain | Time | Priority | Status |
|------------|-----------|------|----------|---------|
| [Quick test of core assumption] | High | 2h | 1 | [ ] |
| [Baseline implementation] | Medium | 1d | 2 | [ ] |
| [Full implementation] | Low | 1w | 3 | [ ] |

### Minimal Viable Experiments
1. **[Core assumption test]**:
   - **What we'll learn**: [Specific hypothesis validation]
   - **Quick implementation**: [Minimal code/setup needed]
   - **Success criteria**: [Clear yes/no signal]

### Strong Baselines Required
- **Baseline 1**: [Why it's the right comparison + implementation plan]
- **Baseline 2**: [Why it's the right comparison + implementation plan]
- **Ceiling Analysis**: [Upper bound on possible performance]

### Evaluation Framework
1. **Distinguishing Evidence**: What results would convince a skeptic?
   - Result A supports Hypothesis 1 but not Hypothesis 2
   - Result B supports Hypothesis 2 but not Hypothesis 1

2. **Statistical Rigor**:
   - Significance threshold: p < 0.001 (exploratory)
   - Sample size calculation: [N needed for power]
   - Multiple hypothesis correction if applicable

3. **Sanity Checks**:
   - [ ] Results reproducible with different seeds
   - [ ] No dependence on initialization order
   - [ ] Performance degrades gracefully with less data

## 5. Implementation Plan (Following Stochastic Decision Process)

### Guiding Principle: Reduce Uncertainty at Maximum Rate

### Phase 1: De-risk Core Ideas (<1 week)
**Goal**: Fail fast on fundamental assumptions
- [ ] Implement minimal test of key technical insight
- [ ] Verify data has properties we need
- [ ] Check computational feasibility
- [ ] Prototype reveals no fundamental blockers
**Exit criteria**: Core approach is viable or pivot needed

### Phase 2: Rapid Prototyping (1-2 weeks)
**Goal**: Get to working implementation ASAP
- [ ] Implement simplest version that could work
- [ ] Use existing tools/libraries maximally
- [ ] Focus on end-to-end pipeline over perfection
- [ ] Daily experiments with tight feedback loops
**Exit criteria**: Have results to analyze, even if rough

### Phase 3: Systematic Evaluation (1-2 weeks)
**Goal**: Build scientific case
- [ ] Implement all baselines properly
- [ ] Run experiments with proper statistics
- [ ] Systematic ablations and sensitivity analysis
- [ ] Address most likely criticisms preemptively
**Exit criteria**: Confident in claims with evidence

### Phase 4: Distillation & Communication (1 week)
**Goal**: Compress into clear narrative
- [ ] Identify 1-3 key claims supported by evidence
- [ ] Create compelling figures
- [ ] Write clear, accessible explanation
- [ ] Package code for reproducibility
**Exit criteria**: Others can understand and build on work

## 6. Resource Planning & Constraints

### Time Budget (Be Realistic!)
- **Total timeline**: [X weeks/months]
- **Weekly hours available**: [Realistically, 20-30h focused work]
- **Key deadline**: [Conference/thesis/etc]
- **Buffer for unexpected**: 30% extra time minimum

### Computational Requirements
- **Experiments < 1 day**: Critical for fast iteration
- **Memory**: [RAM/VRAM needs]
- **Storage**: [Including checkpoints/logs]
- **Parallelization**: [How many experiments simultaneously?]

### Human Resources
- **DRI**: [Who makes final decisions?]
- **Collaborators**: [Who does what?]
- **Advisors/Mentors**: [Weekly check-ins?]
- **External experts**: [Who to consult on what?]

## 7. Risk Analysis & Mitigation

### Research Risk Matrix

| Risk | Probability | Impact | Mitigation | Early Warning Sign |
|------|------------|---------|------------|-------------------|
| Core assumption false | Medium | High | Quick validation experiment | Initial tests fail |
| Compute insufficient | Low | High | Profile early, have backup | Early runs OOM |
| No improvement over baseline | Medium | Medium | Strong baselines, multiple approaches | Early results flat |
| Results not reproducible | Low | High | Version control, seeds, logs | Variance too high |

### Go/No-Go Decision Points
1. **After Phase 1**: If core assumption false → Pivot or abort
2. **After Phase 2**: If no signal over baseline → Try alternative approach
3. **After Phase 3**: If claims not supported → Reduce scope or extend timeline

## 8. Truth-Seeking & Quality Checks

### Research Integrity Checklist
- [ ] **No P-hacking**: Decided on metrics before seeing results
- [ ] **No Cherry-picking**: Reporting all relevant experiments
- [ ] **Strong Baselines**: Honestly tried to make baselines work well
- [ ] **Acknowledged Limitations**: Clearly stated where approach fails
- [ ] **Reproducible**: Another researcher could replicate from writeup

### During Research
- [ ] **Daily Hypothesis Log**: Writing down what I expect before experiments
- [ ] **Failure Documentation**: Recording what didn't work and why
- [ ] **Assumption Tracking**: Listing what could invalidate results
- [ ] **External Validation**: Getting skeptical feedback from others

### Red Team Your Own Work
1. **Alternative Explanations**: What else could explain these results?
2. **Robustness Checks**: Does it work with different seeds/data splits/hyperparameters?
3. **Limiting Cases**: Where does the approach break down?
4. **Skeptic's View**: What would a harsh reviewer say?

## 9. Output & Dissemination Plan

### Target Audience & Venue
- **Primary audience**: [Researchers/practitioners/policymakers in X]
- **Publication venue**: [Conference/journal/blog/preprint]
- **Submission deadline**: [Date - work backwards!]
- **Backup venues**: [Alternative options]

### Key Deliverables
1. **For Researchers**:
   - [ ] Clean, documented, runnable code
   - [ ] Clear writeup of method and findings
   - [ ] Reproduction package with data/configs

2. **For Practitioners**:
   - [ ] 2-page executive summary
   - [ ] Implementation guide
   - [ ] Limitations and when (not) to use

3. **For Broader Audience**:
   - [ ] Blog post or Twitter thread
   - [ ] Key visualizations
   - [ ] One-paragraph summary

### Research Artifacts to Create
```
outputs/
├── paper/
│   ├── main.tex
│   ├── figures/
│   └── supplementary/
├── code/
│   ├── README.md
│   ├── requirements.txt
│   ├── experiments/
│   └── notebooks/
├── results/
│   ├── final_results.json
│   ├── ablation_studies/
│   └── statistical_tests/
└── dissemination/
    ├── blog_post.md
    ├── slides.pdf
    └── executive_summary.pdf
```

## 10. Learning & Iteration

### Weekly Reviews
- **What went well?** [Practices to continue]
- **What was slow?** [Bottlenecks to address]
- **What surprised me?** [Update assumptions]
- **What would I do differently?** [Process improvements]

### Post-Project Retrospective
1. **Technical Lessons**: What did I learn about the problem domain?
2. **Process Lessons**: What research practices worked well?
3. **Communication Lessons**: What was hard to explain?
4. **Future Directions**: What questions did this raise?

### Knowledge Capture
- [ ] Update team knowledge base with lessons learned
- [ ] Create reusable code components
- [ ] Document dead ends to save future time
- [ ] Share tacit knowledge in accessible format

---

## Quick Reference: Research Best Practices Applied

**From Truth-Seeking:**
- Design experiments to falsify, not confirm
- Track pre/post-hoc analysis separately
- Report all relevant results, not just successes

**From Moving Fast:**
- <1 day experiment loops whenever possible
- Fail fast on core assumptions
- Implement quick and dirty first, polish later

**From Prioritization:**
- Always optimize for information gain per time
- Have clear go/no-go decision points
- Cut features ruthlessly to meet deadlines

**From Clear Thinking:**
- State assumptions explicitly
- Quantify uncertainty where possible
- Compare against strong alternatives fairly

---

*Remember: The goal is truth-seeking and impact, not just publication. This spec is a tool for clear thinking, not bureaucracy. Adapt as needed for your specific research context.*
