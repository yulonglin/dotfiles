---
name: research-presentation
description: Guide for structuring research presentations, slides, and updates. Use when preparing slides, drafting research updates, planning mentor meetings, reviewing/critiquing presentations for clarity, or when user mentions slides, presentations, communicating results, research updates, or mentor meetings.
---

# Research Presentation Skill

Guide for structuring research presentations, slide decks, and research updates based on best practices from empirical research communication.

## Proactive Critique & Improve (IMPORTANT)

**Critique and improve for clarity** whenever you encounter:
- Slides or presentation drafts
- Research update text or emails
- Plots and visualizations from experiments
- Figure captions or result descriptions

**The paradigm**: Critique for clarity and against the rubrics in this file, then provide concrete improvements. Don't just flag issues - rewrite the unclear text or describe how to fix the plot.

Don't wait to be asked. If you see unclear framing, missing baselines, ambiguous outcomes, or confusing plots - critique it and offer an improved version.

## When to Use This Skill

Use this skill when you're:
- **Preparing slides** for mentor meetings or research presentations
- **Drafting research updates** via email or written summaries
- **Planning mentor meetings** and prioritizing discussion topics
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

## Critique Mode: Reviewing for Clarity

When reviewing a presentation, slides, or research update, **critique systematically and suggest concrete improvements**.

### Critique Framework

For each slide or section, evaluate:

1. **Clarity** - Can someone understand this in 5 seconds?
   - Is the main point immediately obvious?
   - Are there ambiguous phrases that could mean multiple things?
   - Would someone unfamiliar with the project understand the key takeaway?

2. **Structure** - Is information ordered for comprehension?
   - Does it lead with outcomes, not setup?
   - Are related ideas grouped together?
   - Is there unnecessary repetition?

3. **Completeness** - Is context sufficient but not excessive?
   - Are baselines and comparisons included?
   - Is success/failure explicitly stated?
   - Are prompts shown (for AI research)?

4. **Visual clarity** - Do visuals aid or hinder understanding?
   - Can labels be read without squinting?
   - Are error bars / confidence intervals shown?
   - Could any chart be simplified?

### Critique Output Format

```
## Slide X: [Title]

**Issue**: [Describe the clarity problem]
**Why it matters**: [Impact on audience understanding]
**Suggestion**: [Specific rewrite or restructure]

Before: "We got 67% accuracy on the task"
After: "Success: 67% accuracy (baseline 50%, target >60%)"
```

### Common Clarity Issues to Flag

| Issue | Symptom | Fix |
|-------|---------|-----|
| Buried lede | Background before results | Move outcome to first sentence |
| Ambiguous outcome | "We got X%" without context | Add baseline + success threshold |
| Jargon overload | Unexplained acronyms/terms | Define on first use or avoid |
| Dense slides | Wall of text | 3-4 bullet points max, backup slides for details |
| Passive voice | "It was observed that..." | "We found..." or "Model X showed..." |
| Hedging | "Might possibly suggest..." | State claim, then state confidence level |
| Missing "so what" | Results without implications | Add one sentence: what this means for next steps |

### Improvement Workflow

1. **First pass**: Identify structural issues (ordering, missing context)
2. **Second pass**: Flag unclear wording (rewrite ambiguous sentences)
3. **Third pass**: Check visuals (simplify, add labels, fix scales)
4. **Final**: Verify success/failure framing is explicit throughout

### Example Critique

**Original slide:**
> "Experiment Results
> - Ran 500 samples with prompt A
> - Accuracy: 72.3%
> - Some variation observed across categories"

**Critique:**
- **Issue**: Outcome ambiguity - is 72.3% good or bad?
- **Issue**: "Some variation" is vague - what kind? How much?
- **Issue**: No baseline comparison

**Improved:**
> "Experiment Succeeded: 72% accuracy (target: >60%)
> - Prompt A on 500 samples
> - Category breakdown: code (85%) > math (71%) > reasoning (60%)
> - All categories exceeded 50% baseline"

## Integration with Other Tools

- **data-analyst agent**: Creates visualizations (this skill chooses which ones)
- **experiment-designer agent**: Designs experiments (this skill communicates results)
- **research-skeptic agent**: Questions findings (this skill presents them honestly)

## Context Management (CRITICAL)

⚠️ **Use subagents for PDF/slide review** - Exported PDFs can consume the entire context window.

- **Reviewing exported slides**: Use `general-purpose` agent to read PDF and report issues
- **Fixing slide issues**: Use `/fix-slide` command (delegates PDF analysis to subagent)
- **Creating slides directly**: OK in main context, but export/review via subagent
