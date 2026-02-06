# Plotting Library Refactor - Implementation Summary

**Completed:** 2026-02-02

## Overview

Successfully refactored plotting library to consolidate color definitions and ensure consistent styling. `lib/plotting/` is now the single source of truth for Anthropic brand colors and plotting utilities.

## Changes Implemented

### 1. File Organization

**Moved files:**
- `specs/anthro_colors.py` → `lib/plotting/anthro_colors.py`
- `config/matplotlib/petriplot.py` → `lib/plotting/petriplot.py`

**Updated .gitignore:**
- Added `lib/` and `lib64/` to ignored patterns
- Added `!lib/plotting/` exception to version-control the plotting library

**Result:** Clean separation - lib/plotting is the canonical source for both color definitions and plotting helpers.

### 2. petriplot.py Refactor

**Changes:**
- Now imports shared colors from `anthro_colors`: `IVORY`, `SLATE`, `OAT`, `SKY`, `CACTUS`
- Defines petri-specific colors: `CORAL` (#D97757), `MINT` (#B8D4C8), `ORANGE` (#E6A860)
- Created backward-compatible aliases: `BLUE = SKY`, `CORAL_ALIAS`

**Key design decision:** Petri's `MINT` (#B8D4C8) intentionally differs from anthro's `CACTUS` (#BCD1CA) to preserve the editorial aesthetic of the Petri paper.

### 3. Matplotlib Style Updates

**anthropic.mplstyle:**
- Changed background from ivory (#FAF9F5) to white (#FFFFFF)
- Updated color cycle to PRETTY_CYCLE: `['B86046', '656565', '40668C', 'D19B75', '8778AB', '4A366F']`
- Applied to figure, axes, and savefig settings

**petri.mplstyle:**
- No changes (intentionally keeps ivory background and petri-specific colors)

**deepmind.mplstyle:**
- No changes (already had white background)

### 4. use_anthropic_defaults() Function

Added to `anthro_colors.py`:
```python
def use_anthropic_defaults():
    """Set anthropic style as default for all matplotlib plots."""
```

**Purpose:** Allows users to set anthropic as the default style globally without explicit `plt.style.use()` calls.

**Fallback:** If .mplstyle file not deployed, applies key settings programmatically.

### 5. Deployment Configuration

**deploy.sh updates (lines 322-357):**
- Copies `lib/plotting/*.py` to `~/.local/lib/plotting/` (code copied for isolation)
- Symlinks `*.mplstyle` files to `~/.config/matplotlib/stylelib/` (config symlinked for live updates)
- Added helpful logging showing usage examples

**zshrc.sh updates:**
- Exports PYTHONPATH to include `~/.local/lib/plotting/`
- Enables seamless imports: `from anthro_colors import ...`

### 6. Documentation

**CLAUDE.md:**
- Added "Plotting with Anthropic Style" section
- Documents three available styles (anthropic, petri, deepmind)
- Shows recommended usage: `use_anthropic_defaults()`
- Updated architecture section with new directory structure
- Updated matplotlib deployment explanation

**lib/plotting/README.md (new):**
- Explains module purposes (anthro_colors vs petriplot)
- Documents all colors and functions
- Justifies design decisions (why petri's MINT is separate)
- Shows usage examples
- Links to related documentation

## File Structure

```
lib/plotting/             # Python plotting library (deployed to ~/.local/lib/plotting/)
├── anthro_colors.py      # Anthropic brand colors (ground truth)
├── petriplot.py          # Petri helpers (imports anthro_colors)
└── README.md             # Module documentation

config/matplotlib/        # Matplotlib style files (.mplstyle only)
├── anthropic.mplstyle    # Anthropic brand (white bg, PRETTY_CYCLE)
├── deepmind.mplstyle     # DeepMind (Google colors, white bg)
└── petri.mplstyle        # Petri (ivory bg, editorial aesthetic)
```

## Deployment

### For Users

Run once to deploy:
```bash
./deploy.sh --matplotlib
```

This will:
1. Copy Python modules to `~/.local/lib/plotting/`
2. Symlink matplotlib styles to `~/.config/matplotlib/stylelib/`
3. PYTHONPATH automatically configured in zshrc.sh

### Using in Code

```python
from anthro_colors import use_anthropic_defaults, CLAY, SKY, PRETTY_CYCLE
use_anthropic_defaults()

import matplotlib.pyplot as plt
fig, ax = plt.subplots()
ax.bar(['A', 'B'], [1, 2], color=[CLAY, SKY])
```

For Petri-style diagrams:
```python
import petriplot as pp
plt.style.use('petri')
pp.flow_box(ax, "Step", (0.5, 3), color=CLAY)
pp.flow_arrow(ax, (1.5, 3), (1.5, 2.8))
```

## Design Decisions

### 1. Copy vs Symlink

| Component | Method | Reason |
|-----------|--------|--------|
| Python modules | Copy | Code isolation, safe if dotfiles moved |
| .mplstyle files | Symlink | Config, auto-updates on edits |

### 2. White vs Ivory Background

- **Anthropic style:** White (#FFFFFF) - professional, default
- **Petri style:** Ivory (#FAF9F5) - warm editorial aesthetic
- **DeepMind style:** White (#FFFFFF) - consistent with Google brand

### 3. Petri's Separate MINT

Petri defines its own `MINT` (#B8D4C8) rather than using anthro's `CACTUS` (#BCD1CA) because:
- The specific pastel tone is integral to Petri paper's editorial aesthetic
- Petriplot is style-specific; reusing different colors would break visual consistency
- Allows independent evolution of petri and anthropic styles

### 4. Default Anthropic Style

`use_anthropic_defaults()` makes anthropic the implicit default for Claude Code plotting because:
- Ensures professional, on-brand appearance
- Users explicitly choose alternative styles if needed (petri for editorial work)
- Reduces friction: users don't need to remember style imports

## Verification

All verification tests pass:
- ✓ Files moved to lib/plotting/ and old locations deleted
- ✓ petriplot.py imports from anthro_colors
- ✓ petri-specific colors properly defined
- ✓ matplotlib styles have correct backgrounds
- ✓ PRETTY_CYCLE colors correct in anthropic style
- ✓ deployment.sh configured for lib/plotting/
- ✓ PYTHONPATH configured in zshrc
- ✓ CLAUDE.md documents the changes

## Git Commits

```
e2bfb65 fix: remove TODO placeholder with mixed indentation in anthro_colors
4bceca9 docs: add lib/plotting/README.md with module documentation
4cc92ed docs: update CLAUDE.md for lib/plotting/ refactor and anthropic style
0cc486a feat(deploy): add lib/plotting/ deployment and PYTHONPATH
09ccf5e feat(plotting): add use_anthropic_defaults() function
1762ef6 fix(matplotlib): anthropic style white background and PRETTY_CYCLE
aa7abee refactor: petriplot imports shared colors from anthro_colors
f6a835e refactor: move plotting library to lib/plotting/
```

## Next Steps for Users

1. Run `./deploy.sh --matplotlib` to deploy to system
2. Test with: `python3 -c "from anthro_colors import use_anthropic_defaults; use_anthropic_defaults()"`
3. Update any existing plotting code to use `use_anthropic_defaults()` for consistency

## Backward Compatibility

- petriplot still works exactly as before
- All color names unchanged
- Style files names unchanged
- Only the import paths and deployment locations changed
- petri.MINT and anthro.CACTUS remain intentionally different

## Related Documentation

- CLAUDE.md - Usage guidelines for Claude Code
- lib/plotting/README.md - Technical module documentation
- claude/docs/petri-plotting.md - Petri plotting guide (references updated)
- config/matplotlib/*.mplstyle - Style implementations
