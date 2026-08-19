---
name: pastelplot
description: House plot styling — pastel matplotlib defaults + annotation helpers. Use when making publication-quality figures, when the user asks to "style my plots", "use house style", "use pastelplot/anthroplot", or when generating any matplotlib figure for reports, papers, or decks.
---

# pastelplot

Successor to anthroplot: same drop-in-module idea, pastel categorical palette, no internal-font (S3) dependency. The module lives at `references/pastelplot.py` in this skill.

## Quick start

Copy `references/pastelplot.py` into the project (per anthroplot convention — it is a copy-in module, NOT a pip package), then:

```python
import pastelplot
pastelplot.set_defaults()  # call before plotting
```

**Alternative** (no module, no helpers): `plt.style.use('/path/to/dotfiles/config/matplotlib/pastel.mplstyle')` — or `plt.style.use('pastel')` if symlinked into `~/.config/matplotlib/stylelib/`.

## Check for overlapping text before shipping a figure

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

## Palette

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

## Helpers

```python
pastelplot.annotate_values(ax, format=lambda x: f"{x:.0%}")  # bar heights + line endpoints
pastelplot.format_yaxis(ax, format=lambda x: f"{x:.0%}")
pastelplot.make_axes_transparent(ax)                          # clean overlay plots
```

## Conventions

- Matplotlib (not Plotly) for paper figures — conferences require PDF with embedded fonts.
- Figures self-explanatory: title, axis labels, legend; embed in report.html rather than loose PNGs (see workflow-defaults § Visual Outputs).
- Fonts fall back sanely (Styrene B LC → Helvetica → DejaVu Sans); there is no S3 font install step.
- Legacy: `docs/anthroplot.md` documents the old module (its `.py` reference file no longer exists); brand tertiary gradients (ORANGE/…/GRAY 100–900) are documented there if a sequential ramp is needed.
