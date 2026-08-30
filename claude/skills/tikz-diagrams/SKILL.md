---
name: tikz-diagrams
description: Draw or revise a conceptual diagram for a LaTeX paper — pipelines, architectures, eval flows, training loops, comparison panels — in Anthropic's pastel minimalist style. Use when a paper or preprint needs a figure that is not a data chart, when adapting a blog-post diagram for NeurIPS/ICML/ICLR, or when an existing TikZ figure needs restyling. Carries 17 pattern skeletons, a semantic colour scheme, the anthropic-tikz style package and 16 reference images to aim at.
---

# Anthropic-Style TikZ Diagrams

Create publication-quality TikZ diagrams in Anthropic's pastel minimalist style for ML papers (NeurIPS, ICML, ICLR).

## Quick Start

1. Read `references/diagram-pattern-catalog.md` to find the closest pattern
2. Check `reference-images/` for visual targets
3. Use `references/anthropic-tikz.sty` for consistent styling — copy it next to your `.tex`
4. Copy skeleton from the catalog, adapt content

## Color Semantics

| Color | Meaning |
|-------|---------|
| softblue | Data, inputs, user messages |
| lavender | Models, AI, assistant |
| peach | Evaluation, metrics, scoring |
| mint | Safety, passing, honest behavior |
| blush | Warning, risk, flagged behavior |
| warmgray | Neutral, system, background |

## Usage in Paper

```latex
\usepackage{anthropic-tikz}  % Copy .sty to paper directory
```

## References

- `references/diagram-pattern-catalog.md` — 17 patterns with TikZ skeletons
- `references/anthropic-tikz.sty` — LaTeX style package
- `references/anthropic-tikz-v3.tex` — 8 working examples
- `reference-images/` — 16 real Anthropic/OAI blog figures as visual targets

## Known Issues

- Examples 2 and 4 in the compiled PDF have rendering issues (see catalog for details)
- Font sizes may need adjustment for conference templates (NeurIPS uses 10pt)

## Reach for a neighbour instead when

- the figure plots **data** rather than a concept — bars, lines, scatter, small multiples: `tufte-data-viz` for the quality pass and the `house-plots` skill for the house palette and matplotlib/PGF setup
- the diagram goes on an **Artifact page** rather than into a paper — mermaid renders natively there with no library, and the built-in `artifact-diagramming` skill covers inline SVG
- the question is what the figure must **say** and where it sits in the argument: `~/.claude/checklists/presentation.md`
- you are checking **arrow anchoring, label placement and spacing floors** on a drawn figure: `house-plots/references/visual-layout-quality.md`
