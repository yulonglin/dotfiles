# Petri Plotting Style Guide

Inspired by Anthropic's Petri paper: https://alignment.anthropic.com/2025/petri/

## Color Palette

Use these colors for consistency across matplotlib, TikZ, Excalidraw, and other tools.

### Primary Colors
- **Background**: `#FAF9F5` (warm ivory)
- **Text**: `#141413` (slate, near-black)

### Accent Colors
- **Coral/Clay** (primary): `#D97757`
- **Blue**: `#6A9BCC`
- **Mint/Green**: `#B8D4C8`
- **Orange**: `#E6A860`
- **Tan/Oat** (neutral): `#E3DACC`

### Usage Guidelines
- **Backgrounds**: Always `#FAF9F5`, never pure white
- **Box fills**: Use accent colors with 30% opacity (alpha=0.3)
- **Text**: `#141413` for all labels and annotations
- **Borders**: Thin (0.8pt), `#141413`
- **No gridlines**: Clean, minimal aesthetic

## Matplotlib
```python
import matplotlib.pyplot as plt
plt.style.use('petri')
```

Or with helper functions:
```python
import petriplot as pp

fig, ax = plt.subplots()
pp.flow_box(ax, "Step 1", (0, 0), color=pp.CORAL)
pp.flow_arrow(ax, (1, 0.8), (1, 1.8))
plt.savefig(f'figure_{pp.utc_timestamp()}.png')
```

## TikZ
```latex
\definecolor{ivory}{HTML}{FAF9F5}
\definecolor{slate}{HTML}{141413}
\definecolor{coral}{HTML}{D97757}
\definecolor{blue}{HTML}{6A9BCC}
\definecolor{mint}{HTML}{B8D4C8}
\definecolor{orange}{HTML}{E6A860}
\definecolor{oat}{HTML}{E3DACC}
```

## Excalidraw
Import color palette:
- Background: `#FAF9F5`
- Stroke: `#141413`
- Fill options: `#D97757`, `#6A9BCC`, `#B8D4C8`, `#E6A860`, `#E3DACC`
- Opacity: 30% for fills

## Fonts
- **Sans-serif**: Inter, SF Pro Text, Helvetica Neue, Arial
- **Fallback**: System default sans-serif
- **Size**: 10-11pt for labels, 12-14pt for titles

## Design Principles
1. **Warm editorial feel**: Beige background vs stark white
2. **Pastel accents**: Soft, muted colors (avoid saturated primaries)
3. **Rounded corners**: Use rounded rectangles for boxes
4. **Minimal borders**: Thin lines, remove unnecessary spines
5. **Clean layout**: Generous whitespace, no clutter

## File Naming
Always use timestamps for plot files to prevent overwrites:
```python
plt.savefig(f'figure_{utc_timestamp()}.png')  # e.g., figure_25-01-2026_14-30-22.png
```

Never overwrite existing plots. Each experiment run produces uniquely timestamped outputs.
