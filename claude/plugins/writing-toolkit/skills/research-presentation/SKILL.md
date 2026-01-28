---
name: research-presentation
description: Guide for structuring research presentations, slides, and updates.
---

# Research Presentation Skill

Guide for communicating research results - both slides/presentations and publication figures.

## Context Detection (IMPORTANT)

**Load the appropriate reference based on context:**

| Context | Reference to Load | Don't Load |
|---------|-------------------|------------|
| "slides", "presentation", "meeting", "update", "slidev" | `templates.md`, `common-mistakes.md`, `GUIDE.md` | `paper-figures.md` |
| "figure", "plot", "paper", "publication", "matplotlib" | `paper-figures.md`, `anthroplot.py` | templates, slidev content |
| "visualization", "chart", "graph" (general) | `visualization-guide.md` | context-specific refs |

**Do not load paper-figures.md for slides work, and vice versa.**

## Reference Files

- **`~/.claude/skills/research-presentation/GUIDE.md`** - Detailed critique framework and core principles.
- **`references/paper-figures.md`** - Publication figures: matplotlib, anthroplot, PDF export, LaTeX
- **`references/templates.md`** - Email and slide structure templates
- **`references/visualization-guide.md`** - Plot type selection, best practices (shared)

## Proactive Critique & Improve

**Critique and improve for clarity** whenever you encounter slides, research updates, or plots. Don't wait to be asked.

See `GUIDE.md` for the full Critique Framework and Core Principles.

## Integration with Other Tools

- **data-analyst agent**: Creates visualizations
- **experiment-designer agent**: Designs experiments
- **research-skeptic agent**: Questions findings

## Context Management (CRITICAL)

⚠️ **Use subagents for PDF/slide review** - Exported PDFs can consume the entire context window.

- **Reviewing exported slides**: Use `general-purpose` agent to read PDF and report issues
- **Fixing slide issues**: Use `/fix-slide` command (delegates PDF analysis to subagent)
- **Creating slides directly**: OK in main context, but export/review via subagent