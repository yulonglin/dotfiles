---
name: house-plots
description: House chart style — pastel matplotlib defaults, palette, overlap checking. Use for any figure, chart or plot.
---

# House Plots

All plotting code lives in `lib/plotting/` (deployed to `~/.local/lib/plotting`). Nothing importable lives in this skill any more — it was moved out on 2026-08-28 when `pastelplot.py` was merged into the package.

## Pick The Renderer By Destination, Not By Habit

| Destination | Draw with | Why |
|---|---|---|
| Artifact / report page | **Native SVG** — load the built-in `dataviz` skill | Theme-aware, kilobytes not megabytes, selectable text, crisp at any zoom. A matplotlib PNG bakes its light ground into the pixels and glares in dark mode |
| Paper figure | **matplotlib**, PGF backend for camera-ready | LaTeX typesets the text, so fonts match the document exactly. Reproducible from data |
| Slide deck | matplotlib to SVG/PNG | Marp embeds files; the deck is not theme-reactive |

Both surfaces read the same hexes: `lib/plotting/tokens.json` is generated from `palette.py`, so an SVG chart on a page and a matplotlib figure in a paper cannot drift apart. Regenerate it with `python3 lib/plotting/palette.py` after any palette edit — a test fails if it goes stale.

**`svg.fonttype` defaults to `"path"`**, which turns every label into outlines. Set it to `"none"` if you want an SVG whose text is still text. For LaTeX, prefer the PGF backend over SVG-to-PDF: it needs no converter (none of inkscape, rsvg-convert or cairosvg is installed here) and it matches document fonts properly.

## Quick Start

```python
import sys; sys.path.append("~/.local/lib/plotting")  # not at import time in a session
import style as house

house.set_defaults()                    # pastel + soft grid, the house default
fig, ax = plt.subplots()
ax.bar(arms, values, color=house.emphasis_colors(len(arms), highlight=2))
house.rounded_bars(ax)                  # optional; call BEFORE annotate_values
house.annotate_values(ax, format=lambda x: f"{x:.0%}")
house.format_yaxis(ax, format=lambda x: f"{x:.0%}")
```

`set_defaults(style=...)` takes `pastel_grid` (default), `pastel`, `brand`, `petri`. An unknown name raises rather than silently falling back.

## The Pastel Cycle Carries Series, The Accent Carries Emphasis

Draw every series in pastels and the one you mean in its matching saturated accent — `emphasis_colors(n, highlight=i)` does exactly that via `palette.ACCENT_FOR`.

| Pastel | Hex | Matching accent | Hex |
|---|---|---|---|
| PASTEL_CLAY | #E8A288 | ACCENT_CLAY | #D97757 |
| PASTEL_SKY | #9DBFE3 | ACCENT_SKY | #6A9BCC |
| PASTEL_OLIVE | #A9BC8F | ACCENT_OLIVE | #788C5D |
| PASTEL_FIG | #D99BB4 | ACCENT_FIG | #C46686 |
| PASTEL_VIOLET | #B3A5D3 | — | |
| PASTEL_SAND | #E3C692 | — | |
| PASTEL_AQUA | #93C7C1 | — | |
| PASTEL_GRAY | #B9B6AE | — | |

Text is `SLATE` (#141413). The pastels are softened derivations, **not** official brand values; the accents, SLATE and IVORY are official. Every hex, including the full brand ramps, lives in `lib/plotting/palette.py` — that file is the source of truth, and there is deliberately no Markdown copy of it to drift.

## Check For Overlapping Text Before Shipping A Figure

Eyeballing catches the collisions you happen to look at. A caption lying across a legend survives review and then gets noticed by the reader. `figcheck` walks every rendered Text, Legend and bar artist, takes its true window extent after a draw, and fails on real intersections.

```python
from figcheck import assert_no_overlaps
fig.savefig(path, dpi=150, bbox_inches="tight")
assert_no_overlaps(fig, "fig_name")
```

Or cover every figure a script writes with `import figcheck; figcheck.install()` (`strict=False` to warn). For a script you did not write, `figcheck make_figs.py` runs it with the hook installed and exits non-zero on any collision.

Checking must happen on the live `Figure` — a saved PNG no longer knows where its text boxes were. Two deliberate exclusions: `axvspan`/`axhspan` shading is decoration rather than a bar, and a legend's own entries inside its frame are not collisions.

## Load The Reference For What You Are Doing

| Reference | When |
|---|---|
| `references/matplotlib.md` | Callout shapes, curved annotation arrows, error bars, common chart patterns |
| `references/visual-layout-quality.md` | Arrow anchoring, label placement in empty space, spacing floors — read whenever adding annotations to any chart |

For chart *design* — mark choice, colour assignment, legends, dashboards — load the built-in `dataviz` skill instead; it covers that across every medium. **This file owns the house style; `tufte-data-viz` owns the quality pass** — load it to review or clean up any chart, in any library or medium, against data-ink, direct labeling, range-frame axes and accessibility, once the style here is picked. For LaTeX diagrams use the `tikz-diagrams` skill. For mechanisms and flows on a page, mermaid renders natively in Artifacts with no library.

## Conventions

- **Numbers belong in the plot, not in prose and not in a table.** The surrounding text says how to read the chart — direction, comparison, what to look at — and leaves the values to the chart itself. Hyperparameters are the exception: they are settings rather than results, so a table suits them.
- Figures are self-explanatory: title, axis labels, legend. Embed in the report page rather than shipping loose PNGs.
- Fonts fall back sanely (Styrene B LC → Helvetica → DejaVu Sans); there is no font install step.
- `lib/plotting` has **no `__init__.py` on purpose** — it goes on `sys.path` as a bare directory, so every import inside it is flat. A relative import there breaks the deployed copy while looking fine locally. Pinned by `tests/test_plotting_merge.py`.
