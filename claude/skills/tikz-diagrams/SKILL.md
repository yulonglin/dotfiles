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

## Check Before Shipping

Every TikZ figure is test-compiled in a scratch document that loads the paper's class and `.sty` files (fonts and `\linewidth` must match), then checked two ways before it goes into the paper. `figcheck-pdf test.pdf` fails on overlapping text and on text running past the page box, and must print 0 problems. It reads text only, so a label hidden under a filled shape, or clipped away by the picture's own clip path, is not its job and still needs the render below. Then render the page (`mutool draw -r 150 -o page.png test.pdf 1`) and look for: arrow heads that miss their box or arrows with no visible length (keep at least 6 pt clear between source and target edges); a label word wrapped or hyphenated onto a second line (widen the box or shorten the label; two-line labels are two deliberate phrases, never a broken word); text touching its own box border or another label (2 pt clearance); stacks whose offsets read as a rendering smudge (use about 0.09 cm, three layers, opaque). One vocabulary per role across the figure, matching the paper's terms (a diagram that says judge, evaluator and monitor for one model is three names for one box), and one shape or glyph per role so colour is not the only code.

## Known Issues

- Examples 2 and 4 in the compiled PDF have rendering issues (see catalog for details)
- Font sizes may need adjustment for conference templates (NeurIPS uses 10pt)

## Reach for a neighbour instead when

- the figure plots **data** rather than a concept — bars, lines, scatter, small multiples: `tufte-data-viz` for the quality pass and the `house-plots` skill for the house palette and matplotlib/PGF setup
- the diagram goes on an **Artifact page** rather than into a paper — mermaid renders natively there with no library, and the built-in `artifact-diagramming` skill covers inline SVG
- the question is what the figure must **say** and where it sits in the argument: `~/.claude/checklists/presentation.md`
- you are checking **arrow anchoring, label placement and spacing floors** on a drawn figure: `house-plots/references/visual-layout-quality.md`
