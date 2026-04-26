# Anthropic Matplotlib Style

## Setup

```python
from anthro_colors import use_anthropic_defaults
use_anthropic_defaults()
```

This loads `~/.config/matplotlib/stylelib/anthropic.mplstyle`. If the style file isn't deployed, it falls back to programmatic rcParams.

## What the Style Sets

- **Background**: White (`#FFFFFF`) — figure, axes, and savefig
- **Color cycle**: PRETTY_CYCLE (6 colors: `#B86046`, `#656565`, `#40668C`, `#D19B75`, `#8778AB`, `#4A366F`)
- **Spines**: Top and right hidden
- **Text/axes**: Slate (`#141413`)
- **Font**: Styrene B LC (sans-serif) with Helvetica/Arial fallback
- **Figure size**: 8x5 inches at 150 DPI (saves at 300 DPI)
- **Grid**: Off by default
- **Legend**: No frame

## Available Styles

| Style file | Background | Cycle | Use case |
|-----------|------------|-------|----------|
| `anthropic` | White | PRETTY_CYCLE | Default for all plots |
| `petri` | Ivory | Warm editorial | Petri paper aesthetic |
| `deepmind` | White | Google/DeepMind | DeepMind-related work |

Switch styles: `plt.style.use('petri')` or `plt.style.use('deepmind')`

## Helpers from anthro_colors.py

```python
from anthro_colors import annotate_values, format_yaxis, make_axes_transparent

# Annotate bar heights and line points
annotate_values(ax, format=lambda x: f"{x:.1%}")

# Format y-axis as percentages
format_yaxis(ax, format=lambda x: f"{x:.0%}")

# Make axes fully transparent (for overlay plots)
make_axes_transparent(ax)
```

## Petri Helpers

```python
import petriplot as pp
# Additional helpers for Petri paper-style plots
```

## Common Patterns

### Categorical bar chart
```python
from anthro_colors import use_anthropic_defaults, DARK_ORANGE, GREY
use_anthropic_defaults()

fig, ax = plt.subplots()
ax.bar(categories, values, color=DARK_ORANGE)
ax.set_title("Title")
fig.savefig("plot.png")
```

### Error bars and uncertainty
When data has variance, confidence intervals, or standard deviations — always show them:
```python
ax.bar(categories, means, yerr=stds, capsize=4, color=DARK_ORANGE,
       error_kw=dict(color=SLATE, linewidth=1.2))
# or for line plots:
ax.fill_between(x, mean - ci, mean + ci, alpha=0.2)
```
Omitting error bars when the data has uncertainty is misleading. If you have per-category variance, show it.

### Annotations on bars
Keep annotations light — use the axis text color at normal weight, not bold:
```python
annotate_values(ax, format=lambda x: f"{x:.1%}")
# If doing it manually, use fontweight="normal" (never "bold"):
ax.text(x, y, label, ha="center", va="bottom", fontweight="normal", fontsize=9)
```

### Callouts: pick the right shape for the point

Before placing any callout, decide *what claim* it is making, then pick the
shape that encodes that claim directly. Don't reach for `arc3` curved arrows
by default — they're for one specific case.

| Claim | Right shape | Wrong shape |
|---|---|---|
| "This bar is the headline" (single value) | One arrow from text to bar top | Two arrows |
| "The gap between these two bars is N" | **Double-headed arrow `<->` between the two bar tops** — arrow length = the gap | Curved arrow with text on top |
| "This region matters" | Filled `axvspan` / shaded box | Arrow |
| "These two things differ" | Bracket spanning both, label outside | Two separate annotations |

For the **gap** case (most common in comparison bar charts), the double-headed
arrow's *length* literally encodes the value. The reader sees "+51 pp" and the
arrow length agreeing — that's the strongest possible visual:

```python
# Gap callout: arrow IS the gap.
ax.annotate(
    "",
    xy=(gap_x, c3_top),    # high endpoint
    xytext=(gap_x, tm_top), # low endpoint
    arrowprops=dict(arrowstyle="<->", color=CLAY, lw=2.2),
)
ax.text(gap_x, c3_top + 3, "+51 pp gap",
        ha="center", va="bottom",
        fontsize=13, fontweight="bold", color=CLAY)
```

Place `gap_x` in the visually-empty band beside the bar pair (not on top of
bars, not in another group's column). For grouped bars, that's typically just
to the right of the second bar in the pair.

### Curved callout arrows (`ax.annotate` with `connectionstyle`)

Use these only when pointing *at* a single mark from a label sitting in empty
space — not for showing a gap. Rules:

1. **Never cross unrelated bars/lines/marks.** Locate the empty quadrant
   above/beside/below the target first.
2. **Anchor the text in that empty area**, with `ha`/`va` chosen so the text
   block stays clear of bars.
3. **`connectionstyle="arc3,rad=±N"`** — the rad sign chooses bulge direction;
   pick whichever bulges *away* from any bar between start and end.
4. **One arrow per claim.** Two arrows from the same label fan-out and read as
   two separate annotations sharing a label — confusing.
5. **Verify visually** at print scale. Curve fragility is invisible in code
   review; a screenshot or PDF preview is mandatory before commit.

If text would clip a tall bar or whisker, **raise `ax.set_ylim` headroom**
instead of squeezing the text into the bar.

### Multi-series line plot
```python
# PRETTY_CYCLE auto-assigns colors to each series
for name, data in series.items():
    ax.plot(data, label=name)
ax.legend()
```

### Custom colors beyond the cycle
```python
from anthro_colors import CLAY, SKY, OLIVE, FIG
ax.bar(x, y, color=[CLAY, SKY, OLIVE, FIG])
```
