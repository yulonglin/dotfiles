# Anthropic Color Palette

Source of truth: `lib/plotting/anthro_colors.py`

## Primary Brand Colors

| Name | Variable | Hex |
|------|----------|-----|
| Slate | `GREY_950` / `SLATE` | `#141413` |
| Ivory | `GREY_050` / `IVORY` | `#FAF9F5` |
| Clay | `CLAY` | `#D97757` |

## Secondary Brand Colors

| Name | Variable | Hex |
|------|----------|-----|
| Oat | `OAT` | `#E3DACC` |
| Coral | `CORAL` | `#EBCECE` |
| Fig | `FIG` | `#C46686` |
| Sky | `SKY` | `#6A9BCC` |
| Olive | `OLIVE` | `#788C5D` |
| Heather | `HEATHER` | `#CBCADB` |
| Cactus | `CACTUS` | `#BCD1CA` |

## PRETTY_CYCLE (default plot color cycle)

Used by `anthropic.mplstyle` and `use_anthropic_defaults()`:

| Order | Name | Variable | Hex |
|-------|------|----------|-----|
| 1 | Dark Orange (Book Cloth) | `DARK_ORANGE` / `BOOK_CLOTH` | `#B86046` |
| 2 | Grey | `GREY` | `#656565` |
| 3 | Dark Blue | `DARK_BLUE` | `#40668C` |
| 4 | Medium Orange (Kraft) | `MEDIUM_ORANGE` / `KRAFT` | `#D19B75` |
| 5 | Light Purple | `LIGHT_PURPLE` | `#8778AB` |
| 6 | Dark Purple | `DARK_PURPLE` | `#4A366F` |

## ALT_CYCLE (colorblind-friendly)

Rearranged seaborn colorblind palette with Anthropic-adjacent ordering (dark blue, dark orange, grey first).

## Grayscale System

Full 17-step gray ramp from `GRAY_1000` (`#000000`) to `GRAY_050` (`#FAF9F5`). Common stops:

| Variable | Hex | Use |
|----------|-----|-----|
| `GRAY_950` | `#141413` | Primary text |
| `GRAY_700` | `#3D3D3A` | Secondary text |
| `GRAY_400` | `#B0AEA5` | Muted elements |
| `GRAY_200` | `#E8E6DC` | Light borders |
| `GRAY_050` | `#FAF9F5` | Background (Ivory) |

## Tertiary Hue Ramps (100-900)

Each hue has 9 stops from lightest (100) to darkest (900):

- **Orange**: `#FAEFEB` → `#301107`
- **Yellow**: `#FAF3E8` → `#301901`
- **Green**: `#F1F7E9` → `#0E2402`
- **Aqua**: `#E9F7F2` → `#02211C`
- **Blue**: `#EDF5FC` → `#011A33`
- **Violet**: `#F1F0FF` → `#141133`
- **Magenta**: `#FCF0F4` → `#2E0B17`
- **Red**: `#FCEDED` → `#300B0B`

Use the 500 value as the "standard" intensity. Lighter (100-300) for backgrounds, darker (700-900) for text on light.

## Monochrome

| Variable | Hex |
|----------|-----|
| `LIGHT_IVORY` | `#FAF9F7` |
| `MEDIUM_IVORY` | `#F0EFEB` |
| `DARK_IVORY` | `#E5E5E1` |
| `LIGHT_SLATE` | `#666664` |
| `MEDIUM_SLATE` | `#424241` |
| `DARK_SLATE` | `#1F1F1E` |

## Typography

| Purpose | Font | Fallbacks |
|---------|------|-----------|
| Serif / body | Tiempos Text | cmb10 |
| Sans-serif / headings | Styrene B LC | Avenir, DejaVu Sans Mono, cmss10, Liberation Mono |

## Python Import

```python
from anthro_colors import (
    CLAY, SKY, OLIVE, CACTUS, IVORY, SLATE,
    DARK_ORANGE, DARK_BLUE, GREY,
    PRETTY_CYCLE, ALT_CYCLE,
    ORANGE_500, BLUE_500, GREEN_500,  # etc.
)
```
