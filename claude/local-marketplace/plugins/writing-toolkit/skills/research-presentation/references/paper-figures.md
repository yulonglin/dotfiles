# Paper Figures Guide

Publication-quality figures for ICML, NeurIPS, ICLR, and other ML conferences.

## Quick Setup

**Option 1: Matplotlib style file (recommended for simplicity)**
```python
import matplotlib.pyplot as plt
plt.style.use('/path/to/dotfiles/config/matplotlib/anthropic.mplstyle')
# Or symlink to ~/.config/matplotlib/stylelib/ then: plt.style.use('anthropic')
```

**Option 2: anthroplot module (when you need helpers)**
```python
# Copy anthroplot.py from this skill's references/ into your project
import anthroplot
anthroplot.set_defaults(pretty=True)
```

See `~/.claude/docs/anthroplot.md` for color reference.

## Why Matplotlib (Not Plotly) for Papers

| Aspect | Matplotlib | Plotly |
|--------|------------|--------|
| PDF/vector export | Native, publication-quality | Requires kaleido, can be finicky |
| LaTeX integration | Seamless (`text.usetex=True`) | Poor |
| File size | Small vector PDFs | Often larger |
| Font embedding | Reliable | Can fail |
| Conference standard | Yes | No |

## Figure Specifications

### Size Guidelines

```python
# Single column (most common)
fig, ax = plt.subplots(figsize=(3.5, 2.5))  # inches

# Double column (full width)
fig, ax = plt.subplots(figsize=(7, 3))

# Square (confusion matrices, heatmaps)
fig, ax = plt.subplots(figsize=(3.5, 3.5))
```

Conference column widths:
- **Single column**: ~3.25-3.5 inches
- **Double column**: ~6.5-7 inches
- **DPI**: 300+ for camera-ready

### Font Sizes

```python
plt.rcParams.update({
    'font.size': 8,           # Base font
    'axes.titlesize': 9,      # Title
    'axes.labelsize': 8,      # Axis labels
    'xtick.labelsize': 7,     # Tick labels
    'ytick.labelsize': 7,
    'legend.fontsize': 7,
})
```

Rule of thumb: Figures are often scaled down; fonts should be readable at 50% size.

### LaTeX Integration

```python
plt.rcParams.update({
    'text.usetex': True,
    'font.family': 'serif',
    'text.latex.preamble': r'\usepackage{amsmath}'
})

# Use in labels
ax.set_xlabel(r'$\mathcal{L}(\theta)$')
ax.set_ylabel(r'Accuracy (\%)')
```

## Export Checklist

```python
# Standard export
plt.savefig('figure.pdf', bbox_inches='tight', dpi=300)

# With transparent background (for overlays)
plt.savefig('figure.pdf', bbox_inches='tight', transparent=True)
```

**Pre-submission checks:**
- [ ] Vector format (PDF, not PNG)
- [ ] Fonts embedded (open PDF, check fonts menu)
- [ ] Readable at 50% zoom
- [ ] Colors distinguishable in grayscale
- [ ] No text overlapping
- [ ] Axis labels have units
- [ ] Error bars/CIs present

## Common Figure Types

### Bar Chart with Error Bars

```python
import matplotlib.pyplot as plt
import numpy as np

methods = ['Baseline', 'Method A', 'Method B']
means = [0.65, 0.78, 0.82]
cis = [0.03, 0.04, 0.02]  # 95% CI half-widths

fig, ax = plt.subplots(figsize=(3.5, 2.5))
bars = ax.bar(methods, means, yerr=cis, capsize=3, color='#D97757')
ax.set_ylabel('Accuracy')
ax.set_ylim(0, 1)

# Add value labels
for bar, mean in zip(bars, means):
    ax.text(bar.get_x() + bar.get_width()/2, bar.get_height() + 0.05,
            f'{mean:.0%}', ha='center', fontsize=7)

plt.tight_layout()
plt.savefig('comparison.pdf', bbox_inches='tight')
```

### Line Plot with Error Bands

```python
x = np.array([10, 50, 100, 500, 1000])
y_mean = np.array([0.55, 0.68, 0.75, 0.82, 0.85])
y_std = np.array([0.05, 0.04, 0.03, 0.02, 0.02])

fig, ax = plt.subplots(figsize=(3.5, 2.5))
ax.plot(x, y_mean, '-o', color='#D97757', label='Our Method')
ax.fill_between(x, y_mean - 1.96*y_std, y_mean + 1.96*y_std,
                alpha=0.2, color='#D97757')
ax.axhline(0.5, linestyle='--', color='gray', label='Random')

ax.set_xscale('log')
ax.set_xlabel('Training samples')
ax.set_ylabel('Accuracy')
ax.legend(frameon=False)

plt.tight_layout()
plt.savefig('scaling.pdf', bbox_inches='tight')
```

### Grouped Bar Chart

```python
methods = ['Baseline', 'Ours']
datasets = ['MMLU', 'GSM8K', 'HumanEval']
data = {
    'Baseline': [0.65, 0.45, 0.32],
    'Ours': [0.78, 0.62, 0.48],
}

x = np.arange(len(datasets))
width = 0.35

fig, ax = plt.subplots(figsize=(4, 2.5))
for i, (method, values) in enumerate(data.items()):
    offset = (i - 0.5) * width
    ax.bar(x + offset, values, width, label=method)

ax.set_ylabel('Accuracy')
ax.set_xticks(x)
ax.set_xticklabels(datasets)
ax.legend(frameon=False)
ax.set_ylim(0, 1)

plt.tight_layout()
plt.savefig('grouped.pdf', bbox_inches='tight')
```

## Anthropic Color Palette

### Primary (use for main data)
```python
CLAY = '#D97757'      # Primary accent (orange)
SLATE = '#141413'     # Text, dark elements
IVORY = '#FAF9F5'     # Backgrounds
```

### Secondary (use for comparisons)
```python
SKY = '#6A9BCC'       # Blue
FIG = '#C46686'       # Pink
OLIVE = '#788C5D'     # Green
```

### Color Cycle (pretty=True)
```python
PRETTY_CYCLE = [
    '#B86046',  # DARK_ORANGE
    '#656565',  # GREY
    '#40668C',  # DARK_BLUE
    '#D19B75',  # MEDIUM_ORANGE
    '#8778AB',  # LIGHT_PURPLE
    '#4A366F',  # DARK_PURPLE
]
```

### Gradients (for heatmaps, sequential data)
```python
# Blue gradient: BLUE_100 (light) to BLUE_900 (dark)
BLUE_100 = '#EDF5FC'
BLUE_300 = '#86B8EB'
BLUE_500 = '#2C84DB'
BLUE_700 = '#0F4B87'
BLUE_900 = '#011A33'
```

## Accessibility

### Colorblind-Friendly

Use `pretty=False` in anthroplot for colorblind-friendly palette, or manually select:

```python
# Good colorblind-safe pairs
COLORBLIND_SAFE = ['#0072B2', '#E69F00', '#009E73', '#CC79A7']
```

### Grayscale Test

Before submitting, convert to grayscale to verify distinguishability:
```python
from PIL import Image
img = Image.open('figure.png').convert('L')
img.save('figure_gray.png')
```

## Common Mistakes

1. **PNG instead of PDF** - Raster images pixelate when scaled
2. **Missing error bars** - Always show uncertainty
3. **Tiny fonts** - Test at 50% zoom
4. **Legend obscuring data** - Use direct labels or move legend outside
5. **Y-axis not starting at 0** - Misleading for bar charts (mark truncation if necessary)
6. **Red-green color scheme** - Bad for colorblind readers
7. **Too many colors** - Limit to 4-5 distinguishable colors
8. **No baseline** - Include random/prior work for context
