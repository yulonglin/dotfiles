# Plotting Library

Python modules for consistent, brand-aligned plotting across all projects.

## Modules

### anthro_colors.py

Ground truth for Anthropic brand colors and plotting styles.

**Purpose:** Central color definitions, PRETTY_CYCLE palette, and style utilities.

**Key Colors:**
- Primary: `CLAY` (#D97757), `SKY` (#6A9BCC), `IVORY` (#FAF9F5), `SLATE` (#141413)
- Secondary: `OAT` (#E3DACC), `CACTUS` (#BCD1CA), `OLIVE` (#788C5D)
- Extended palettes: Orange, Yellow, Green, Blue, Violet, Magenta, Red systems

**Usage:**
```python
from anthro_colors import CLAY, SKY, IVORY, SLATE, PRETTY_CYCLE, use_anthropic_defaults

# Set anthropic as default for all plots
use_anthropic_defaults()

# Or use specific colors
fig, ax = plt.subplots()
ax.bar(['A', 'B'], [1, 2], color=[CLAY, SKY])
```

**Functions:**
- `use_anthropic_defaults()` - Set anthropic.mplstyle as global default
- `set_defaults()` - Configure fonts, colors, cycles (from original anthroplot)
- Other utilities: `annotate_values()`, `format_yaxis()`, `make_axes_transparent()`

### petriplot.py

Plotting helpers for Petri-paper style diagrams.

**Purpose:** Flowchart and diagram functions using Petri-specific aesthetic.

**Colors:**
- Imports shared colors from `anthro_colors`: `IVORY`, `SLATE`, `OAT`
- Petri-specific colors: `CORAL` (#D97757), `MINT` (#B8D4C8), `ORANGE` (#E6A860)
- **Note:** Petri's `MINT` (#B8D4C8) differs from anthro's `CACTUS` (#BCD1CA) - intentional design choice

**Usage:**
```python
import petriplot as pp
from anthro_colors import CLAY, SKY

plt.style.use('petri')
fig, ax = plt.subplots()

# Flow boxes
pp.flow_box(ax, "Step 1", (0.5, 3), color=CLAY)
pp.flow_box(ax, "Step 2", (0.5, 2), color=SKY, alpha=0.3)

# Arrows
pp.flow_arrow(ax, (1.5, 3), (1.5, 2.8))

ax.set_xlim(0, 4)
ax.set_ylim(-0.5, 4)
ax.axis('off')
plt.savefig('flowchart.png')
```

**Functions:**
- `flow_box()` - Draw rounded rectangle boxes
- `flow_arrow()` - Draw arrows between boxes
- `set_petri_style()` - Apply petri.mplstyle
- `utc_timestamp()` - Get UTC timestamp in DD-MM-YYYY_HH-MM-SS format

## Deployment

**Location:** `~/.local/lib/plotting/` (copied, not symlinked)

**Setup:**
1. Run `./deploy.sh --matplotlib` in dotfiles repo
2. PYTHONPATH is auto-configured in zshrc.sh

**Why copied, not symlinked?** Python modules are code (not config), copied for safety and isolation. If dotfiles repo moves, imports still work.

**Updates:** Run `./deploy.sh --matplotlib` again to refresh.

## Design Decisions

### Color Separation
- **anthro_colors.py:** Ground truth for all Anthropic brand colors, used across projects
- **petriplot.py:** Petri-specific extensions (CORAL, MINT, ORANGE) that differ from or extend anthropic palette
- Petri's MINT (#B8D4C8) deliberately kept separate from anthro's CACTUS (#BCD1CA) to preserve editorial aesthetic

### PRETTY_CYCLE
PRETTY_CYCLE in anthro_colors defines the default color cycle:
```python
PRETTY_CYCLE = [
    DARK_ORANGE,    # BOOK_CLOTH (#B86046)
    GREY,           # #656565
    DARK_BLUE,      # #40668C
    MEDIUM_ORANGE,  # KRAFT (#D19B75)
    LIGHT_PURPLE,   # #8778AB
    DARK_PURPLE,    # #4A366F
]
```

This is baked into `anthropic.mplstyle` and available for explicit use.

### Matplotlib Styles
Three styles available, each with different aesthetic:

| Style | Background | Purpose | Use When |
|-------|-----------|---------|----------|
| `anthropic` | White (#FFFFFF) | Default, professional | All Claude-generated plots |
| `petri` | Ivory (#FAF9F5) | Editorial, warm | Petri paper or editorial aesthetics |
| `deepmind` | White (#FFFFFF) | Google/DeepMind colors | DeepMind-related work |

## Related Documentation

- **CLAUDE.md** - Usage guidelines for Claude Code users
- **claude/ai_docs/petri-plotting.md** - Detailed Petri plotting guide
- **config/matplotlib/\*.mplstyle** - Style file implementations

## Cross-References

- Original anthroplot: Anthropic internal (this is extracted subset)
- Petri paper: https://alignment.anthropic.com/2025/petri/
