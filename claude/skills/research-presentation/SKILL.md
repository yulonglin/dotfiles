---
name: research-presentation
description: Guide for structuring research presentations, slides, and updates. Use when preparing slides, drafting research updates, planning mentor meetings, reviewing/critiquing presentations for clarity, or when user mentions slides, presentations, communicating results, research updates, or mentor meetings.
---

# Research Presentation Skill

Guide for communicating research results - both slides/presentations and publication figures.

## Context Detection (IMPORTANT)

**Load the appropriate reference based on context:**

| Context | Reference to Load | Don't Load |
|---------|-------------------|------------|
| "slides", "presentation", "meeting", "update", "slidev" | `templates.md`, `common-mistakes.md` | `paper-figures.md` |
| "figure", "plot", "paper", "publication", "matplotlib" | `paper-figures.md`, `anthroplot.py` | templates, slidev content |
| "visualization", "chart", "graph" (general) | `visualization-guide.md` | context-specific refs |

**Do not load paper-figures.md for slides work, and vice versa.**

## Reference Files

- **`references/paper-figures.md`** - Publication figures: matplotlib, anthroplot, PDF export, LaTeX
- **`references/anthroplot.py`** - Anthropic styling module (copy into projects)
- **`references/templates.md`** - Email and slide structure templates
- **`references/visualization-guide.md`** - Plot type selection, best practices (shared)
- **`references/common-mistakes.md`** - Common presentation mistakes

Also see: `~/.claude/ai_docs/anthroplot.md` for quick color reference.

---

# SLIDES & PRESENTATIONS

Use this section for mentor meetings, research updates, slide preparation.

## Proactive Critique & Improve

**Critique and improve for clarity** whenever you encounter:
- Slides or presentation drafts
- Research update text or emails
- Plots and visualizations from experiments
- Figure captions or result descriptions

Don't wait to be asked. If you see unclear framing, missing baselines, ambiguous outcomes - critique it and offer an improved version.

## Core Principles

### 1. Summary-First Structure

**Lead with outcomes, not setup.**

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

1. Blocking decisions needed
2. Surprising results requiring discussion
3. Successful experiments (sanity check)
4. Failed experiments (if debugging needed)
5. Future plans
6. Administrative items

### 5. Always Include Your Prompt (AI Research)

- **Main slides**: Show truncated prompt (first 2-3 sentences)
- **Appendix**: Include full prompt verbatim

## Graph Selection Framework

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

- [ ] Summary slide ready: Previous context + outcome + key decision
- [ ] Agenda with time allocations: Prioritized by importance
- [ ] Full prompts included: Main slide (truncated) + appendix (full)
- [ ] Visualizations ready: Simple, clear, with error bars
- [ ] Success/failure explicit: No ambiguity about outcomes
- [ ] Backup slides prepared: Deep-dive details if needed
- [ ] Questions identified: What you're blocked on or uncertain about
- [ ] Next steps drafted: What you propose to do next

## Critique Framework

For each slide or section, evaluate:

1. **Clarity** - Can someone understand this in 5 seconds?
2. **Structure** - Is information ordered for comprehension?
3. **Completeness** - Is context sufficient but not excessive?
4. **Visual clarity** - Do visuals aid or hinder understanding?

### Critique Output Format

```
## Slide X: [Title]

**Issue**: [Describe the clarity problem]
**Why it matters**: [Impact on audience understanding]
**Suggestion**: [Specific rewrite or restructure]

Before: "We got 67% accuracy on the task"
After: "Success: 67% accuracy (baseline 50%, target >60%)"
```

### Common Clarity Issues

| Issue | Fix |
|-------|-----|
| Buried lede | Move outcome to first sentence |
| Ambiguous outcome | Add baseline + success threshold |
| Jargon overload | Define on first use or avoid |
| Dense slides | 3-4 bullet points max |
| Passive voice | "We found..." not "It was observed..." |
| Missing "so what" | Add one sentence: implications |

---

# PAPER FIGURES

For publication-quality figures, load `references/paper-figures.md`.

**Quick setup:**
```python
# Option 1: Style file (simple)
import matplotlib.pyplot as plt
plt.style.use('path/to/anthropic.mplstyle')

# Option 2: Full module (with helpers)
import anthroplot
anthroplot.set_defaults(pretty=True)
```

**Key points:**
- Use matplotlib, not Plotly, for papers (PDF/LaTeX compatibility)
- Always export as PDF with `bbox_inches='tight'`
- See `~/.claude/ai_docs/anthroplot.md` for colors

---

## Integration with Other Tools

- **data-analyst agent**: Creates visualizations (see `ai_docs/anthroplot.md` for styling)
- **experiment-designer agent**: Designs experiments (this skill communicates results)
- **research-skeptic agent**: Questions findings (this skill presents them honestly)

## Context Management (CRITICAL)

⚠️ **Use subagents for PDF/slide review** - Exported PDFs can consume the entire context window.

- **Reviewing exported slides**: Use `general-purpose` agent to read PDF and report issues
- **Fixing slide issues**: Use `/fix-slide` command (delegates PDF analysis to subagent)
- **Creating slides directly**: OK in main context, but export/review via subagent
