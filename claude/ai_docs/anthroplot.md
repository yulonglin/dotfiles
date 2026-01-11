# Anthropic Plot Styling

```python
import anthroplot
anthroplot.set_defaults(pretty=True)  # Call before plotting
# Use install_brand_fonts=True if fonts don't load
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

ORANGE, YELLOW, GREEN, AQUA, BLUE, VIOLET, MAGENTA, RED, GRAY (050-1000)

Example: `BLUE_500 = "#2C84DB"`, `BLUE_200 = "#BAD7F5"`

## Helpers

```python
anthroplot.annotate_values(ax, format=lambda x: f"{x:.0%}")
anthroplot.format_yaxis(ax, format=lambda x: f"{x:.0%}")
anthroplot.make_axes_transparent(ax)
```

## Fonts

- Sans-serif: Styrene B LC (default)
- Serif: Tiempos Text
