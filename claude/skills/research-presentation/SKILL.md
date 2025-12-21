---
name: research-presentation
description: Guide for structuring research presentations, slides, and updates. Use when preparing slides, drafting research updates, planning mentor meetings, reviewing presentations, or when user mentions slides, presentations, communicating results, research updates, or mentor meetings.
---

# Research Presentation Skill

This skill provides guidance for structuring research presentations, slide decks, and research updates based on best practices from empirical research communication (LessWrong principles) and AI safety research standards.

## When to Use This Skill

Use this skill when you're:
- **Preparing slides** for mentor meetings or research presentations
- **Drafting research updates** via email or written summaries
- **Planning mentor meetings** and prioritizing discussion topics
- **Reviewing presentations** for clarity, structure, and completeness
- **Selecting visualizations** for communicating experimental results
- **Structuring experimental summaries** for collaborators

**Use for all research communication** where you need to present findings clearly and respect time constraints.

## Core Principles

### 1. Summary-First Structure

**Lead with outcomes, not setup.**

Your audience (mentor, collaborator, PI) manages multiple projects. They need to quickly understand:
- What you tried
- Whether it worked or failed
- What decisions need to be made

**Structure:**
```
Slide 1: Executive Summary
- Recap of previous meeting takeaways
- What you did since then
- Outcome: Success or failure (be explicit)
- Key decision needed (if any)

Slide 2+: Details (only if needed)
```

This allows mentors to:
- Skip familiar context if they remember
- Jump straight to discussion if outcome is clear
- Calibrate how deep to go based on remaining time

### 2. Explicit Success/Failure Framing

**Never leave your mentor guessing whether results are good or bad.**

The type of feedback you receive depends on this:
- **Success** → Sanity checks, next steps, publication strategy
- **Failure** → Debugging, alternative approaches, whether to pivot

**Examples:**
- ✅ "Experiment succeeded: 94% accuracy (baseline: 50%)"
- ✅ "Experiment failed: No separation between conditions (expected >20% gap)"
- ❌ "Results: 52% accuracy" (is this good or bad?)

### 3. Include an Agenda with Time Allocations

**Help your mentor budget attention across topics.**

At the start of your presentation:
```
Agenda (45 min total):
1. Experiment A results - 15 min (PRIORITY)
2. Experiment B debugging - 10 min
3. Next steps discussion - 15 min
4. Admin/logistics - 5 min
```

This enables:
- Prioritizing critical topics
- Deep-diving selectively
- Ensuring important decisions get discussed

### 4. Prioritize by Importance

**Order content by importance, not chronology.**

If the meeting runs short, critical findings should be covered first.

**Priority order:**
1. Blocking decisions needed
2. Surprising results requiring discussion
3. Successful experiments (sanity check)
4. Failed experiments (if debugging needed)
5. Future plans
6. Administrative items

### 5. Always Include Your Prompt

**CRITICAL FOR AI RESEARCH: The prompt defines how you're measuring your metric.**

For any LLM-based experiment:
- **Main slides**: Show truncated prompt (first 2-3 sentences)
- **Appendix**: Include full prompt verbatim
- **Why**: Prompts define what you're actually measuring; without them, results are meaningless

**Example:**
```
Metric: "Refusal rate"
Prompt (truncated): "You are a helpful AI assistant. User: [HARMFUL_REQUEST]..."
[Full prompt in Appendix Slide 12]
```

This prevents:
- Misunderstanding what was measured
- Inability to reproduce results
- Confusion about metric definitions

## Selecting Visualizations for Communication

### Prefer Charts Over Tables

**Convert tables and raw statistics to visual charts wherever possible.**

Tables require cognitive effort to parse and compare values. Charts make patterns, comparisons, and outliers immediately visible.

**When to convert:**
- Comparing 3+ values → Bar chart (with values labeled on bars)
- Showing trends over time/conditions → Line chart
- Displaying distributions → Histogram or violin plot
- Showing proportions → Stacked bar or pie chart (sparingly)

**When tables are acceptable:**
- Exact values matter more than patterns (e.g., hyperparameter settings)
- Only 2-3 values being compared
- Mixed data types (text + numbers)
- Reference/lookup information

**Example transformation:**
```
❌ Table: "Model A: 82%, Model B: 67%, Model C: 91%, Baseline: 50%"
✅ Bar chart: Visual bars with "82%", "67%", "91%", "50%" labeled directly on each bar
```

### Graph Selection Framework

When choosing what to plot, ask:

1. **What story am I telling?**
   - Comparison between methods? → Bar chart with error bars
   - Trend over time/scale? → Line plot
   - Distribution of outcomes? → Violin plot or histogram
   - Relationship between variables? → Scatter plot
   - Many conditions? → Heatmap or grouped bar chart

2. **What's important for understanding?**
   - The main effect (big, clear, front-and-center)
   - Uncertainty (confidence intervals, error bars)
   - Baselines (always show comparison points)
   - Statistical significance (annotate if relevant)

3. **What can I remove without losing meaning?**
   - Simplify, simplify, simplify
   - Remove chart junk (unnecessary gridlines, 3D effects, decorations)
   - Use direct labeling instead of legends when possible
   - Limit colors to 3-4 distinct categories

### Common Experiment Types & Recommended Plots

**Method Comparison:**
- Bar chart with 95% confidence intervals
- Show baseline clearly
- Annotate statistical significance if tested
- Order bars by performance (not alphabetically)

**Ablation Study:**
- Bar chart showing component contributions
- Full model on left, ablations to the right
- Show what each component adds/removes
- Consider waterfall chart for cumulative effects

**Scaling Experiments:**
- Line plot with error bands (not just error bars)
- Log scale if spanning orders of magnitude
- Show compute budget or sample size on x-axis
- Include baseline as horizontal line

**Failure Mode Analysis:**
- Confusion matrix or error breakdown
- Highlight where model fails most
- Show representative examples of failures
- Quantify frequency of each failure type

**Hyperparameter Sweeps:**
- Heatmap for 2D sweeps
- Line plot for 1D sweeps
- Highlight optimal region
- Consider showing multiple metrics as small multiples

### Visualization Best Practices

**Statistical Rigor:**
- Always show uncertainty (95% CI or standard error)
- Report sample sizes (n=X)
- Show baselines for comparison
- Indicate if differences are statistically significant
- Don't cherry-pick: show all conditions, or clearly state selection criteria

**Clarity:**
- Large, readable fonts (14pt+ for labels)
- Clear axis labels with units
- Informative title stating the takeaway
- Legends only when necessary (direct labeling preferred)
- Consistent color scheme across slides
- **Always show values directly on bars** (data labels) for easy reading without needing to reference axes

**Honesty:**
- Start y-axis at zero for bar charts (or clearly mark truncation)
- Use appropriate scales (linear vs. log)
- Don't hide negative results
- Show full distributions, not just means
- Flag outliers or data quality issues

## Meeting Preparation Checklist

Before a mentor meeting:

- [ ] **Summary slide ready**: Previous context + outcome + key decision
- [ ] **Agenda with time allocations**: Prioritized by importance
- [ ] **Full prompts included**: Main slide (truncated) + appendix (full)
- [ ] **Visualizations ready**: Simple, clear, with error bars
- [ ] **Success/failure explicit**: No ambiguity about outcomes
- [ ] **Backup slides prepared**: Deep-dive details if needed
- [ ] **Questions identified**: What you're blocked on or uncertain about
- [ ] **Next steps drafted**: What you propose to do next

## Common Mistakes to Avoid

**1. Burying the lede**
- ❌ 10 slides of background before showing results
- ✅ Slide 1 = outcome, Slides 2+ = details

**2. Ambiguous outcomes**
- ❌ "We got 67% accuracy"
- ✅ "Success: 67% accuracy (baseline 50%, target >60%)"

**3. Missing prompts**
- ❌ "We measured refusal rate"
- ✅ "Refusal rate using prompt: [show prompt]"

**4. Unclear visualizations**
- ❌ 8 overlapping lines, tiny font, no error bars
- ✅ 2-3 key comparisons, large fonts, confidence intervals

**5. No time prioritization**
- ❌ Equal time on all topics, run out of time before critical decision
- ✅ Agenda with time allocations, priority-ordered

**6. Overloading with details**
- ❌ Every hyperparameter, every experiment variant
- ✅ Main findings + "details in backup slides if needed"

**7. No baselines**
- ❌ "Method A: 75%"
- ✅ "Method A: 75% (baseline: 50%, SOTA: 82%)"

## Templates

### Research Update Email Template

```
Subject: [Project Name] Update - [Success/Failure] on [Key Experiment]

Hi [Mentor],

Quick update on [project]:

OUTCOME: [Explicit success or failure]
- Tried: [What you did in 1 sentence]
- Result: [Key metric with baseline comparison]
- Interpretation: [What this means]

KEY DECISION NEEDED:
[Specific question or choice point, if any]

NEXT STEPS (if you agree):
1. [Proposed action 1]
2. [Proposed action 2]

Details below / Slides attached.

[Your name]

---
[Detailed findings, visualizations, etc.]
```

### Slide Structure Template

```
Slide 1: Summary
- Last meeting: [key takeaways]
- This sprint: [what you did]
- Outcome: SUCCESS/FAILURE - [1 sentence]
- Decision needed: [if any]

Slide 2: Agenda (30 min)
- Topic A - 10 min [PRIORITY]
- Topic B - 10 min
- Discussion - 10 min

Slide 3-N: Results
[Visualizations with clear titles, error bars, baselines]

Slide N+1: Next Steps
- Proposal 1: [with timeline]
- Proposal 2: [with timeline]
- Open questions

Appendix: Full prompts, detailed methods, backup analyses
```

## Example Interaction

**User:** "I need to prepare slides for my advisor meeting tomorrow. We're discussing my experiments on deception detection."

**Skill Response:**
1. Ask about context:
   - What did you discuss last meeting?
   - What experiments did you run?
   - Did they succeed or fail?
   - What decision needs to be made?

2. Propose structure:
   - Slide 1: Summary (last meeting → what you tried → success/failure → decision needed)
   - Slide 2: Agenda with time allocation
   - Slide 3-4: Key results (1 plot per slide, clear comparisons)
   - Slide 5: Next steps proposal
   - Appendix: Full prompts, detailed methods

3. Review visualizations:
   - Are comparisons clear?
   - Are error bars shown?
   - Are baselines included?
   - Is statistical significance indicated?
   - Are prompts included (for LLM experiments)?

4. Suggest prioritization:
   - What's most important to discuss?
   - What can be skipped if time is short?
   - What needs decision vs. FYI?

## Integration with Other Tools

This skill works alongside:
- **data-analyst agent**: Creates visualizations (this skill chooses which ones for communication)
- **experiment-designer agent**: Designs experiments (this skill communicates results)
- **research-skeptic agent**: Questions findings (this skill presents findings honestly)
- **paper-writer agent**: Writes papers (this skill handles informal updates/presentations)

## Further Reading

- LessWrong: "Tips on Empirical Research" (https://www.lesswrong.com/posts/i3b9uQfjJjJkwZF4f)
- Tufte, Edward: "The Visual Display of Quantitative Information"
- Few, Stephen: "Show Me the Numbers"
- Advice on research communication from AI safety researchers
