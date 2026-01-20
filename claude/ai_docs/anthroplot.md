# Anthropic Plot Styling

**What this is**: An internal Anthropic styling module (a `.py` file you copy into projects). NOT a pip package.

**For paper figures**: Use matplotlib (not Plotly) - conferences require PDF with embedded fonts.

## Quick Start

Copy `anthroplot.py` from `~/.claude/skills/research-presentation/references/anthroplot.py` into your project, then:

```python
import anthroplot
anthroplot.set_defaults(pretty=True)  # Call before plotting
# Use install_brand_fonts=True if fonts don't load (requires internal S3 access)
```

**Alternative** (no module needed): Use the matplotlib style file:
```python
import matplotlib.pyplot as plt
plt.style.use('~/.config/matplotlib/stylelib/anthropic.mplstyle')
# Or: plt.style.use('/path/to/dotfiles/config/matplotlib/anthropic.mplstyle')
```

## Key Colors

| Primary | Hex | Secondary | Hex |
|---------|-----|-----------|-----|
| SLATE | #141413 | SKY | #6A9BCC |
| IVORY | #FAF9F5 | FIG | #C46686 |
| CLAY | #D97757 | OLIVE | #788C5D |

## Color Cycles

- `pretty=True`: DARK_ORANGE, GREY, DARK_BLUE, MEDIUM_ORANGE, LIGHT_PURPLE, DARK_PURPLE
- `pretty=False`: Colorblind-friendly (seaborn colorblind rearranged)

## Tertiary Gradients (100=light, 900=dark)

ORANGE, YELLOW, GREEN, AQUA, BLUE, VIOLET, MAGENTA, RED, GRAY

Example: `BLUE_500 = "#2C84DB"`, `BLUE_200 = "#BAD7F5"`

## Helper Functions

```python
# Annotate bar/line values directly on plot
anthroplot.annotate_values(ax, format=lambda x: f"{x:.0%}")

# Format y-axis tick labels
anthroplot.format_yaxis(ax, format=lambda x: f"{x:.0%}")

# Remove all axes for clean overlay plots
anthroplot.make_axes_transparent(ax)
```

## Fonts

- Sans-serif: Styrene B LC (default) - requires internal font access
- Serif: Tiempos Text
- Fallbacks: Avenir, DejaVu Sans Mono, Helvetica

## anthroplot.py vs anthropic.mplstyle

| Feature | anthroplot.py | anthropic.mplstyle |
|---------|---------------|-------------------|
| Colors & cycle | ✓ | ✓ |
| Helper functions | ✓ | ✗ |
| Font setup | ✓ (with S3) | ✓ (fallbacks) |
| Plotly support | ✓ | ✗ |
| No dependencies | ✗ | ✓ |

Use `.mplstyle` for quick styling; use `anthroplot.py` when you need helpers.
