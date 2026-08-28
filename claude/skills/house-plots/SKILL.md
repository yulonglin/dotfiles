---
name: house-plots
description: House visual style — pastel matplotlib defaults, Anthropic palette, annotation helpers, TikZ and web-CSS references. Use for any figure, chart, diagram, slide or styled page.
---

# House Plot And Visual Style

One skill for everything that should carry the house look: matplotlib figures first, plus TikZ diagrams, HTML/CSS and slides. `pastelplot` is the current default module; the Anthropic brand palette and the per-domain references sit beside it.

## Quick Start — Copy The Module In, Then Set Defaults

`references/pastelplot.py` is a **copy-in module, not a pip package** (the anthroplot convention). Copy it into the project, then:

```python
import pastelplot
pastelplot.set_defaults()  # call before plotting
```

**Alternative** (no module, no helpers): `plt.style.use('/path/to/dotfiles/config/matplotlib/pastel.mplstyle')` — or `plt.style.use('pastel')` if symlinked into `~/.config/matplotlib/stylelib/`.

**Brand-strict alternative**, when the output must match Anthropic's official look rather than the pastel house default:

```python
from anthro_colors import use_anthropic_defaults
use_anthropic_defaults()
```

That loads `~/.config/matplotlib/stylelib/anthropic.mplstyle`: white background, PRETTY_CYCLE colors, no top/right spines, 300 DPI saves with tight bbox.

## Check For Overlapping Text Before Shipping A Figure

Eyeballing catches the collisions you happen to look at; a caption lying across a legend or a label sitting on a bar survives review and then gets noticed by the reader. `references/figcheck.py` walks every rendered Text, Legend and bar artist, takes its true window extent after a draw, and fails on real intersections.

Copy it in beside `pastelplot.py`, then either check one figure:

```python
from figcheck import assert_no_overlaps
fig.savefig(path, dpi=150, bbox_inches="tight")
assert_no_overlaps(fig, "fig_name")
```

or cover every figure the script writes with one line at the top:

```python
import figcheck; figcheck.install()      # strict=False to warn instead of raise
```

For a script you did not write, `figcheck make_figs.py` (on PATH) runs it with the hook installed and exits non-zero on any collision; `figcheck --warn` reports without failing. Checking must happen on the live `Figure` — a saved PNG no longer knows where its text boxes were.

Two gotchas it was built around: `axvspan`/`axhspan` shading is decoration, not a bar, so full-height patches are excluded (otherwise every value label reads as a collision), and a legend's own entries sitting inside its frame are not collisions.

## Pastel Cycle For Series, Accents For Emphasis

| Pastel (cycle order) | Hex | Accent (saturated brand) | Hex |
|---|---|---|---|
| PASTEL_CLAY | #E8A288 | ACCENT_CLAY | #D97757 |
| PASTEL_SKY | #9DBFE3 | ACCENT_SKY | #6A9BCC |
| PASTEL_OLIVE | #A9BC8F | ACCENT_OLIVE | #788C5D |
| PASTEL_FIG | #D99BB4 | ACCENT_FIG | #C46686 |
| PASTEL_VIOLET | #B3A5D3 | — | |
| PASTEL_SAND | #E3C692 | — | |
| PASTEL_AQUA | #93C7C1 | — | |
| PASTEL_GRAY | #B9B6AE | — | |

Text is `SLATE` (#141413); background white (`IVORY` #FAF9F5 available). Pastel hexes are softened derivations of the Anthropic secondaries, NOT official brand values — the ACCENT_* and SLATE/IVORY hexes are official. Highlight-one-series pattern: draw everything in pastels, the emphasized series in its matching accent (`pastelplot.ACCENT_FOR[color]`).

Official brand accents, for output that must be brand-strict:

| Name | Hex | Use |
|------|-----|-----|
| DARK_ORANGE (BOOK_CLOTH) | `#B86046` | Primary accent, first in cycle |
| GREY | `#656565` | Secondary, neutral elements |
| DARK_BLUE | `#40668C` | Tertiary accent |
| SLATE (GREY_950) | `#141413` | Text, axes |
| IVORY (GREY_050) | `#FAF9F5` | Light backgrounds (brand) |
| CLAY | `#D97757` | Warm accent |
| SKY | `#6A9BCC` | Cool accent |
| OLIVE | `#788C5D` | Nature/green accent |

## Helpers

```python
pastelplot.annotate_values(ax, format=lambda x: f"{x:.0%}")  # bar heights + line endpoints
pastelplot.format_yaxis(ax, format=lambda x: f"{x:.0%}")
pastelplot.make_axes_transparent(ax)                          # clean overlay plots
```

## Load The Reference For Your Output Type

| Domain | Reference | When |
|--------|-----------|------|
| **matplotlib** | `references/matplotlib.md` | Python plots, charts, figures |
| **Colors** | `references/colors.md` | Full palette — all 9 hue ramps (orange through red, 100-900 each). Accent colors have AA text-tier variants; check it before coloring text, because brand accents fail AA as text on Ivory |
| **HTML/CSS** | `references/web-css.md` | Web pages, HTML artifacts |
| **TikZ** | `references/tikz.md` | LaTeX diagrams for papers |
| **Annotations & layout** | `references/visual-layout-quality.md` | Arrow anchoring, label placement in empty space, spacing minimums — read whenever adding annotations (callouts, gap markers, brackets) to any chart |

## Conventions

- Matplotlib (not Plotly) for paper figures — conferences require PDF with embedded fonts.
- Figures self-explanatory: title, axis labels, legend; embed in report.html rather than loose PNGs (see workflow-defaults § Visual Outputs).
- Fonts fall back sanely (Styrene B LC → Helvetica → DejaVu Sans); there is no S3 font install step.
- Legacy: `references/anthroplot.md` documents the old module (its `.py` reference file no longer exists); brand tertiary gradients (ORANGE/…/GRAY 100–900) are documented there if a sequential ramp is needed.

## Ground Truth For Brand Hexes

All official color values come from `lib/plotting/anthro_colors.py` — that file is the single source of truth. If a hex code here conflicts with that file, the file wins. The PASTEL_* values are house derivations and live in `references/pastelplot.py`.
