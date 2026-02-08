---
name: tikz-diagrams
description: Create Anthropic-style TikZ diagrams for ML/AI safety papers. 17 patterns, semantic colors, NeurIPS-ready.
---

# Anthropic-Style TikZ Diagrams

Create publication-quality TikZ diagrams in Anthropic's pastel minimalist style for ML papers (NeurIPS, ICML, ICLR).

## Quick Start

1. Read `references/diagram-pattern-catalog.md` to find the closest pattern
2. Check `reference-images/` for visual targets
3. Use `anthropic-tikz.sty` for consistent styling
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
