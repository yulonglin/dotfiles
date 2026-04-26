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

### Callout arrows (`ax.annotate`)
Callout arrows must never cross unrelated bars, lines, or data marks. The arrow
should travel through visually empty space and curve **toward** the target,
not over neighbours.

Decision tree before placing an arrow:
1. **Find the empty quadrant** above/beside/below the target bar — pick the
   side with no other bar in the path.
2. **Anchor the text in that empty area**, with `ha`/`va` chosen so the text
   block also stays clear of bars (right-anchored on the right, etc.).
3. **Choose `connectionstyle="arc3,rad=±N"`** so the arc bulges *away* from
   any bar between start and end. `rad>0` bulges one way, `rad<0` the other —
   if unsure, render both and pick the one that doesn't graze a neighbour.
4. **Verify visually** at print scale. Curve fragility is invisible in code
   review; a screenshot or PDF preview is mandatory before commit.

```python
# good: text in empty area to the right of MATH bar, arrow curves
# leftward to TM bar without crossing the C³ bar.
ax.annotate(
    "+51 pp gap",
    xy=(math_tm_x, tm_top + 1.5),
    xytext=(math_idx + 0.50, 78),
    ha="center", va="bottom",
    fontsize=13, fontweight="bold", color=CLAY,
    arrowprops=dict(arrowstyle="->", color=CLAY, lw=1.6,
                    connectionstyle="arc3,rad=-0.25"),
)
```

If text would clip a tall bar or whisker, **raise `ax.set_ylim` headroom** to
~115% of (bar + whisker top) instead of squeezing the text into the bar.

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
