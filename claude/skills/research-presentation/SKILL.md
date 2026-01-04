---
name: research-presentation
description: Guide for structuring research presentations, slides, and updates. Use when preparing slides, drafting research updates, planning mentor meetings, reviewing presentations, or when user mentions slides, presentations, communicating results, research updates, or mentor meetings.
---

# Research Presentation Skill

Guide for structuring research presentations, slide decks, and research updates based on best practices from empirical research communication.

## When to Use This Skill

Use this skill when you're:
- **Preparing slides** for mentor meetings or research presentations
- **Drafting research updates** via email or written summaries
- **Planning mentor meetings** and prioritizing discussion topics
- **Reviewing presentations** for clarity, structure, and completeness
- **Selecting visualizations** for communicating experimental results

## Core Principles

### 1. Summary-First Structure

**Lead with outcomes, not setup.**

Your audience manages multiple projects. They need to quickly understand:
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

### 2. Explicit Success/Failure Framing

**Never leave your mentor guessing whether results are good or bad.**

- **Success** → Sanity checks, next steps, publication strategy
- **Failure** → Debugging, alternative approaches, whether to pivot

**Examples:**
- ✅ "Experiment succeeded: 94% accuracy (baseline: 50%)"
- ✅ "Experiment failed: No separation between conditions (expected >20% gap)"
- ❌ "Results: 52% accuracy" (is this good or bad?)

### 3. Include an Agenda with Time Allocations

```
Agenda (45 min total):
1. Experiment A results - 15 min (PRIORITY)
2. Experiment B debugging - 10 min
3. Next steps discussion - 15 min
4. Admin/logistics - 5 min
```

### 4. Prioritize by Importance

**Order content by importance, not chronology.**

**Priority order:**
1. Blocking decisions needed
2. Surprising results requiring discussion
3. Successful experiments (sanity check)
4. Failed experiments (if debugging needed)
5. Future plans
6. Administrative items

### 5. Always Include Your Prompt

**CRITICAL FOR AI RESEARCH: The prompt defines what you're measuring.**

- **Main slides**: Show truncated prompt (first 2-3 sentences)
- **Appendix**: Include full prompt verbatim

## Graph Selection Framework

When choosing what to plot, ask:

1. **What story am I telling?**
   - Comparison between methods? → Bar chart with error bars
   - Trend over time/scale? → Line plot
   - Distribution of outcomes? → Violin plot or histogram
   - Relationship between variables? → Scatter plot

2. **What's important for understanding?**
   - The main effect (big, clear, front-and-center)
   - Uncertainty (confidence intervals, error bars)
   - Baselines (always show comparison points)

3. **What can I remove without losing meaning?**
   - Remove chart junk (unnecessary gridlines, 3D effects)
   - Use direct labeling instead of legends when possible
   - Limit colors to 3-4 distinct categories

**Prefer charts over tables** - Tables require cognitive effort to parse; charts make patterns immediately visible.

## Meeting Preparation Checklist

- [ ] **Summary slide ready**: Previous context + outcome + key decision
- [ ] **Agenda with time allocations**: Prioritized by importance
- [ ] **Full prompts included**: Main slide (truncated) + appendix (full)
- [ ] **Visualizations ready**: Simple, clear, with error bars
- [ ] **Success/failure explicit**: No ambiguity about outcomes
- [ ] **Backup slides prepared**: Deep-dive details if needed
- [ ] **Questions identified**: What you're blocked on or uncertain about
- [ ] **Next steps drafted**: What you propose to do next

## Reference Files

- **`references/templates.md`** - Email and slide structure templates, example interaction
- **`references/visualization-guide.md`** - Experiment types, recommended plots, best practices
- **`references/common-mistakes.md`** - 7 common mistakes to avoid

## Integration with Other Tools

- **data-analyst agent**: Creates visualizations (this skill chooses which ones)
- **experiment-designer agent**: Designs experiments (this skill communicates results)
- **research-skeptic agent**: Questions findings (this skill presents them honestly)
