---
name: anthropic-style
description: Anthropic visual style for plots, diagrams, slides, and web. Use when creating any visual output that should have Anthropic's look-and-feel — matplotlib charts, TikZ diagrams, HTML/CSS, or presentations.
---

# Anthropic Visual Style

Use this skill when generating any visual output that should look Anthropic-branded: plots, charts, diagrams, slides, or web pages.

## Quick Start (matplotlib — primary use case)

```python
from anthro_colors import use_anthropic_defaults
use_anthropic_defaults()

import matplotlib.pyplot as plt
fig, ax = plt.subplots()
# All plots now use Anthropic style automatically
```

This loads `~/.config/matplotlib/stylelib/anthropic.mplstyle` which sets:
- White background (`#FFFFFF`)
- PRETTY_CYCLE colors (see `references/colors.md`)
- No top/right spines, clean typography
- 300 DPI saves with tight bbox

## Domain-Specific References

Load the relevant reference for your output type:

| Domain | Reference | When |
|--------|-----------|------|
| **matplotlib** | `references/matplotlib.md` | Python plots, charts, figures |
| **Colors** | `references/colors.md` | Color palette lookup for any domain |
| **HTML/CSS** | `references/web-css.md` | Web pages, HTML artifacts |
| **TikZ** | `references/tikz.md` | LaTeX diagrams for papers |

## Key Colors (quick reference)

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

Full palette with all 9 hue ramps (orange through red, 100-900 each) in `references/colors.md`.

## Ground Truth

All color values come from `lib/plotting/anthro_colors.py` — that file is the single source of truth. If a hex code here conflicts with that file, the file wins.
