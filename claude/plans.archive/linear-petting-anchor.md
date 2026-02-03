# Plotting Library Refactor - Implementation Plan

**Goal:** Consolidate color definitions into `lib/plotting/`, use `anthro_colors.py` as single source of truth, and ensure consistent white backgrounds (except petri style).

**User Decisions:**
- White backgrounds by default, petri.mplstyle keeps ivory (#FAF9F5) for editorial aesthetic
- Keep petriplot-specific colors (ORANGE, CORAL_LIGHT, MINT) separate from anthro_colors.py
- Petri keeps its own MINT (#B8D4C8) - it's petri-specific, not from anthro_colors
- **Default to anthropic style** for all Claude Code plotting (make this explicit)
- Use absolute paths (~/.local/lib/plotting/) for clarity
- Test scripts use ./tmp/ (project-relative) not /tmp

---

## Implementation Steps

### 1. Create Library Structure

```bash
# Create new directory
mkdir -p lib/plotting

# Move files
git mv specs/anthro_colors.py lib/plotting/anthro_colors.py
git mv config/matplotlib/petriplot.py lib/plotting/petriplot.py
```

**Commit:** `refactor: move anthro_colors.py to lib/plotting/`

### 2. Refactor petriplot.py

**File:** `lib/plotting/petriplot.py`

**Changes:**
1. Add import: `from anthro_colors import IVORY, SLATE, CLAY, SKY, OAT`
2. Replace hardcoded color definitions with imports where they match
3. Keep petri-specific colors:
   - `ORANGE = '#E6A860'`
   - `CORAL_LIGHT = '#EBCECE'`
   - `MINT = '#B8D4C8'` (petri-specific, different from anthro CACTUS)
4. Add backward-compatible aliases:
   - `CORAL = CLAY` (maps to anthro_colors.CLAY)
   - `BLUE = SKY` (maps to anthro_colors.SKY)
5. Keep `COLOR_CYCLE = [CORAL, BLUE, MINT, ORANGE, OAT]` (petri-specific palette)

**Commit:** `refactor: petriplot imports shared colors from anthro_colors`

### 3. Update Style Files

**File:** `config/matplotlib/anthropic.mplstyle`

Lines to change:
- Line 6: `figure.facecolor: FFFFFF` (was FAF9F5)
- Line 12: `axes.facecolor: FFFFFF` (was FAF9F5)
- Line 18: Update cycle to PRETTY_CYCLE from anthro_colors:
  ```
  axes.prop_cycle: cycler('color', ['B86046', '656565', '40668C', 'D19B75', '8778AB', '4A366F'])
  ```
  (DARK_ORANGE/BOOK_CLOTH, GREY, DARK_BLUE, MEDIUM_ORANGE/KRAFT, LIGHT_PURPLE, DARK_PURPLE)
- Line 63: `savefig.facecolor: FFFFFF`

**File:** `config/matplotlib/petri.mplstyle`

**No changes needed** - Keep existing colors including MINT (#B8D4C8).
Petri style is intentionally different from anthropic with its own aesthetic.

Background stays ivory (FAF9F5), colors stay as-is:
```
axes.prop_cycle: cycler('color', ['D97757', '6A9BCC', 'B8D4C8', 'E6A860', 'E3DACC'])
```
(CORAL/CLAY, BLUE/SKY, MINT, ORANGE, OAT)

**File:** `config/matplotlib/deepmind.mplstyle`

No changes needed (already white).

**Commit:** `fix(matplotlib): white backgrounds, consistent color cycles`

### 4. Make Anthropic Default Style for Claude Code

**Add to:** `lib/plotting/anthro_colors.py`

Add function to set anthropic as default (append after existing `set_defaults()` function):

```python
def use_anthropic_defaults():
    """Set anthropic style as default for all matplotlib plots.

    This configures matplotlib to use the anthropic.mplstyle by default
    without requiring explicit plt.style.use('anthropic') calls.

    Usage in Claude Code plotting:
        from anthro_colors import use_anthropic_defaults
        use_anthropic_defaults()
    """
    import matplotlib.pyplot as plt
    from pathlib import Path

    # Load anthropic style from absolute path
    style_path = Path.home() / '.config' / 'matplotlib' / 'stylelib' / 'anthropic.mplstyle'
    if style_path.exists():
        plt.style.use(str(style_path))
    else:
        # Fallback: apply key settings programmatically
        plt.rcParams['figure.facecolor'] = '#FFFFFF'
        plt.rcParams['axes.facecolor'] = '#FFFFFF'
        plt.rcParams['savefig.facecolor'] = '#FFFFFF'
        # Use PRETTY_CYCLE
        from cycler import cycler
        plt.rcParams['axes.prop_cycle'] = cycler(color=PRETTY_CYCLE)
```

**Add to:** `~/.claude/CLAUDE.md` (global instructions)

Add to plotting section:

```markdown
## Plotting with Anthropic Style

**ALWAYS use Anthropic style as default** for all plots created by Claude Code:

```python
from anthro_colors import use_anthropic_defaults
use_anthropic_defaults()

# Now all plots use anthropic style (white background, PRETTY_CYCLE colors)
import matplotlib.pyplot as plt
fig, ax = plt.subplots()
# ... your plotting code
```

**Why:** Ensures consistent, professional appearance across all Claude-generated plots.

**Absolute path to styles:** `~/.config/matplotlib/stylelib/anthropic.mplstyle`

**Available styles:**
- `anthropic` - Default, white background, brand colors (use this)
- `petri` - Ivory background, warm editorial aesthetic (use for specific Petri-paper style)
- `deepmind` - Google/DeepMind colors (use for DeepMind-related work)
```

**Commit:** `feat(plotting): add use_anthropic_defaults() and document in CLAUDE.md`

### 5. Update Deployment

**File:** `deploy.sh` (lines 322-353)

Add before existing matplotlib section:

```bash
# Deploy plotting library
PLOTLIB="$HOME/.local/lib/plotting"
if [[ -d "$DOT_DIR/lib/plotting" ]]; then
    mkdir -p "$PLOTLIB"
    for pyfile in "$DOT_DIR/lib/plotting"/*.py; do
        [[ -f "$pyfile" ]] && cp "$pyfile" "$PLOTLIB/$(basename "$pyfile")"
    done
    log_info "  Deployed plotting library to ~/.local/lib/plotting/"
fi
```

Update existing section to only handle .mplstyle files (remove petriplot.py copying).

**File:** `config/zshrc.sh` (after line 57)

Add:
```bash
if [[ -d "$HOME/.local/lib/plotting" ]]; then
    export PYTHONPATH="$HOME/.local/lib/plotting:${PYTHONPATH}"
fi
```

**Commit:** `feat(deploy): add lib/plotting/ deployment and PYTHONPATH`

### 6. Update Documentation

**File:** `CLAUDE.md`

Update directory structure section (line ~119):
```markdown
lib/plotting/             # Python plotting library (deployed to ~/.local/lib/plotting/)
├── anthro_colors.py      # Anthropic brand colors (ground truth)
└── petriplot.py          # Petri helpers (imports anthro_colors)

config/matplotlib/        # Matplotlib styles (.mplstyle files only)
├── anthropic.mplstyle    # Anthropic brand (white bg, PRETTY_CYCLE)
├── deepmind.mplstyle     # DeepMind (Google colors)
└── petri.mplstyle        # Petri (ivory bg, editorial)
```

Update matplotlib deployment section (line ~159):
- Document lib/plotting/ copying
- Update PYTHONPATH configuration
- Note library updates require re-running `deploy.sh --matplotlib`

**File:** `README.md`

Add matplotlib/plotting library section:
- Three styles (anthropic, deepmind, petri) with backgrounds noted
- Python library (anthro_colors, petriplot) usage examples
- Deployment command

**File:** `claude/ai_docs/petri-plotting.md`

Update import examples:
```python
from anthro_colors import CLAY, SKY, CACTUS, IVORY, SLATE
import petriplot as pp

pp.flow_box(ax, "Step", (0, 0), color=CLAY)  # Primary coral
```

**File:** `lib/plotting/README.md` (new)

Create documentation explaining:
- Module purposes (anthro_colors vs petriplot)
- Import patterns
- Deployment mechanism (copy not symlink)
- Design decisions (petri keeps its own colors including MINT, separate from anthro_colors)

**Commit:** `docs: update for lib/plotting/ refactor`

---

## Verification Steps

### After Implementation

1. **Check file moves:**
   ```bash
   ls lib/plotting/  # Should show: anthro_colors.py, petriplot.py, README.md
   ls specs/anthro_colors.py  # Should not exist
   ls config/matplotlib/petriplot.py  # Should not exist
   ```

2. **Deploy:**
   ```bash
   ./deploy.sh --matplotlib
   ```

3. **Verify deployment:**
   ```bash
   ls ~/.local/lib/plotting/  # Should show: anthro_colors.py, petriplot.py
   ls -l ~/.config/matplotlib/stylelib/  # Should show 3 symlinked .mplstyle files
   echo $PYTHONPATH | grep plotting  # Should include ~/.local/lib/plotting
   ```

### Test Imports

Create test directory and script:
```bash
mkdir -p ./tmp
```

Create `./tmp/test_plotting.py`:
```python
#!/usr/bin/env python3
from anthro_colors import CLAY, SKY, CACTUS, IVORY, SLATE, PRETTY_CYCLE
import petriplot as pp

# Test color aliases
assert pp.CORAL == CLAY, "CORAL should equal CLAY"
assert pp.BLUE == SKY, "BLUE should equal SKY"
# Note: pp.MINT is petri-specific (#B8D4C8), different from anthro CACTUS (#BCD1CA)

# Test styles load
import matplotlib.pyplot as plt
plt.style.use('petri')
plt.style.use('anthropic')
plt.style.use('deepmind')

print("✓ All imports and styles successful")
```

Run: `python3 ./tmp/test_plotting.py`

### Test End-to-End Plot

Create `./tmp/test_petri_plot.py`:
```python
#!/usr/bin/env python3
import matplotlib.pyplot as plt
import petriplot as pp
from anthro_colors import CLAY, SKY, CACTUS

plt.style.use('petri')
fig, ax = plt.subplots(figsize=(8, 6))

pp.flow_box(ax, "Step 1", (0.5, 3), color=CLAY, alpha=0.3)
pp.flow_box(ax, "Step 2", (0.5, 2), color=pp.ORANGE, alpha=0.3)
pp.flow_box(ax, "Step 3", (0.5, 1), color=SKY, alpha=0.3)
pp.flow_box(ax, "Step 4", (0.5, 0), color=CACTUS, alpha=0.3)

pp.flow_arrow(ax, (1.5, 3), (1.5, 2.8))
pp.flow_arrow(ax, (1.5, 2), (1.5, 1.8))
pp.flow_arrow(ax, (1.5, 1), (1.5, 0.8))

ax.set_xlim(0, 4)
ax.set_ylim(-0.5, 4)
ax.axis('off')

filename = f'./tmp/petri_test_{pp.utc_timestamp()}.png'
plt.savefig(filename, dpi=300)
print(f'✓ Saved: {filename}')
```

Run: `python3 ./tmp/test_petri_plot.py`

Expected: Creates PNG with Petri-style flowchart using correct colors.

### Verify Backgrounds

Check that:
- `anthropic.mplstyle` plots have white (#FFFFFF) backgrounds
- `deepmind.mplstyle` plots have white backgrounds
- `petri.mplstyle` plots have ivory (#FAF9F5) backgrounds

---

## Critical Files

- `lib/plotting/anthro_colors.py` - Ground truth (moved from specs/), add `use_anthropic_defaults()` function
- `lib/plotting/petriplot.py` - Import shared colors from anthro_colors (IVORY, SLATE, CLAY, SKY, OAT), keep MINT
- `deploy.sh` (lines 322-353) - Add lib/plotting/ deployment before .mplstyle deployment
- `config/zshrc.sh` (line ~57) - Add `~/.local/lib/plotting` to PYTHONPATH
- `config/matplotlib/anthropic.mplstyle` (lines 6, 12, 18, 63) - White bg, PRETTY_CYCLE
- `config/matplotlib/petri.mplstyle` - **No changes** (keep all existing colors)
- `~/.claude/CLAUDE.md` (global) - Add "always use anthropic style" instruction

---

## Rollback Plan

If issues occur:
```bash
git log --oneline -10  # Find commit before refactor
git revert <commit-hash>..HEAD
./deploy.sh --matplotlib
source ~/.zshrc
```

---

## Success Criteria

- ✓ Files moved to `lib/plotting/` and removed from old locations
- ✓ `deploy.sh --matplotlib` completes without errors
- ✓ PYTHONPATH includes `~/.local/lib/plotting`
- ✓ `from anthro_colors import CLAY` works
- ✓ `import petriplot as pp` works
- ✓ All three matplotlib styles load
- ✓ Test plot creates valid PNG with correct colors
- ✓ Background colors: white (anthropic, deepmind), ivory (petri)
- ✓ Documentation updated
