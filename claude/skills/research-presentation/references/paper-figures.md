# Paper Figures

Publication figures for ICML, NeurIPS, ICLR and similar. This file carries only what is specific to a **camera-ready paper**: the physical sizes, the font sizes that survive scaling, LaTeX integration, export and the pre-submission checks.

## Colours and setup come from house-plots, never from here

Set defaults with the house package — `lib/plotting/`, deployed to `~/.local/lib/plotting` — and read the `house-plots` skill for the API. There is no style file to install and nothing to copy into your project.

```python
import sys; sys.path.append("~/.local/lib/plotting")  # not at import time in a session
import style as house

house.set_defaults()                       # pastel + soft grid
colors = house.emphasis_colors(n, highlight=i)   # pastels for the series, accent for the one you mean
```

**Every hex lives in `lib/plotting/palette.py`, which is the single source of truth.** This file lists no colours, and neither should your figure code — a hardcoded hex is a copy that drifts the moment the palette changes.

For camera-ready output prefer the **PGF backend** over SVG-to-PDF: LaTeX typesets the text, so the figure's fonts match the document exactly, and no converter is needed. `house-plots` has the detail.

## Size the figure in inches, to the column it will sit in

```python
fig, ax = plt.subplots(figsize=(3.5, 2.5))   # single column, the common case
fig, ax = plt.subplots(figsize=(7, 3))       # double column, full width
fig, ax = plt.subplots(figsize=(3.5, 3.5))   # square: confusion matrices, heatmaps
```

Conference column widths are ~3.25-3.5 inches single column and ~6.5-7 inches double column. Render at 300 DPI or better for camera-ready.

## Set font sizes for 50% scaling, not for your screen

A figure drawn at 3.5 inches is often printed smaller still, so size the type for the printed page rather than the preview.

```python
plt.rcParams.update({
    'font.size': 8,           # base
    'axes.titlesize': 9,
    'axes.labelsize': 8,
    'xtick.labelsize': 7,
    'ytick.labelsize': 7,
    'legend.fontsize': 7,
})
```

Rule of thumb: every label must stay readable at 50% of the size you are looking at.

## LaTeX integration makes the maths match the body text

```python
plt.rcParams.update({
    'text.usetex': True,
    'font.family': 'serif',
    'text.latex.preamble': r'\usepackage{amsmath}',
})

ax.set_xlabel(r'$\mathcal{L}(\theta)$')
ax.set_ylabel(r'Accuracy (\%)')
```

Escape percent signs in labels once `usetex` is on, or LaTeX eats the rest of the line as a comment.

## Export vector, and check the PDF rather than trusting it

```python
plt.savefig('figure.pdf', bbox_inches='tight', dpi=300)
plt.savefig('figure.pdf', bbox_inches='tight', transparent=True)   # for an overlay
```

**Pre-submission checks**, run on the actual PDF you are about to upload:

- Vector format (PDF, not PNG) — raster pixelates when the reviewer zooms
- Fonts embedded — open the PDF and check its fonts panel
- Readable at 50% zoom
- Colours distinguishable in grayscale — convert and look: `Image.open('figure.png').convert('L')`
- No overlapping text — run `figcheck.assert_no_overlaps` from the house package rather than eyeballing it
- Axis labels carry units
- Error bars or confidence intervals present, and the chance line drawn where one exists

## The mistakes that survive review and get noticed by readers

1. **PNG instead of PDF** — raster images pixelate when scaled
2. **Missing error bars** — every estimate carries an interval
3. **No baseline or chance line** — a number with nothing to compare against says little
4. **Tiny fonts** — test at 50% zoom
5. **Legend obscuring data** — label the series directly, or move the legend outside the axes
6. **Y-axis not starting at zero on a bar chart** — mark the truncation if you must truncate
7. **Too many colours** — past four or five distinguishable series, the reader stops tracking them
8. **Hardcoded hexes** — use `house.emphasis_colors`, so the figure follows the palette

## Related

- Drawing the chart at all, the palette, the overlap checker: the `house-plots` skill
- Whether the figure earns its place on a slide rather than in a paper: `~/.claude/checklists/presentation.md`
- Whether the numbers in it hold up — intervals, nulls, chance correction: `~/.claude/checklists/results-analysis.md`
