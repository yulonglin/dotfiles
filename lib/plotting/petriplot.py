"""
Petri plotting style helpers
Inspired by Anthropic's Petri paper: https://alignment.anthropic.com/2025/petri/

Color palette extracted from published figures.
Imports shared colors from anthro_colors.py (ground truth).
"""

import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
from matplotlib.patches import FancyBboxPatch
import numpy as np
import subprocess
from datetime import datetime

# Import shared colors from anthro_colors (ground truth)
from anthro_colors import IVORY, SLATE, CACTUS, SKY, OAT

# Petri-specific colors (not in anthro_colors, or different from anthropic brand)
CORAL = '#D97757'        # Primary accent (maps to anthro CLAY semantically, but kept as CORAL for petri)
BLUE = SKY               # Use SKY from anthro_colors (backward compat alias)
MINT = '#B8D4C8'         # Green/mint (petri-specific, different from CACTUS)
ORANGE = '#E6A860'       # Orange accent (petri-specific)

# Backward-compatible aliases mapping to anthro_colors
CORAL_ALIAS = CORAL      # Petri's CORAL is different from anthro's CORAL
BLUE_ALIAS = BLUE        # Petri's BLUE is same as anthro's SKY

# Semantic color mapping (petri-specific palette)
COLORS = {
    'background': IVORY,
    'text': SLATE,
    'accent_primary': CORAL,
    'accent_blue': BLUE,
    'accent_green': MINT,
    'accent_neutral': OAT,
    'accent_orange': ORANGE,
}

# Color cycle for petri plots (petri-specific palette order)
COLOR_CYCLE = [CORAL, BLUE, MINT, ORANGE, OAT]

def utc_timestamp():
    """Get UTC timestamp in DD-MM-YYYY_HH-MM-SS format"""
    try:
        result = subprocess.run(['utc_timestamp'], capture_output=True, text=True, check=True)
        return result.stdout.strip()
    except (subprocess.SubprocessError, FileNotFoundError):
        # Fallback if utc_timestamp command not available
        return datetime.utcnow().strftime('%d-%m-%Y_%H-%M-%S')

def flow_box(ax, text, xy, width=2, height=0.8, color=BLUE,
             text_color=SLATE, fontsize=10, alpha=0.3):
    """
    Add a rounded rectangle box for flowcharts

    Args:
        ax: matplotlib axes
        text: Label text
        xy: (x, y) bottom-left corner
        width, height: Box dimensions
        color: Fill color (hex or named)
        text_color: Text color
        fontsize: Font size for label
        alpha: Fill transparency (0-1)

    Returns:
        FancyBboxPatch object
    """
    box = FancyBboxPatch(
        xy, width, height,
        boxstyle="round,pad=0.1",
        facecolor=color,
        edgecolor=SLATE,
        linewidth=0.8,
        alpha=alpha
    )
    ax.add_patch(box)

    # Add centered text
    ax.text(
        xy[0] + width/2, xy[1] + height/2,
        text,
        ha='center', va='center',
        color=text_color,
        fontsize=fontsize,
        weight='normal'
    )

    return box

def flow_arrow(ax, start, end, color=SLATE, width=1.5):
    """
    Add arrow for flowcharts

    Args:
        ax: matplotlib axes
        start: (x, y) start point
        end: (x, y) end point
        color: Arrow color
        width: Line width
    """
    ax.annotate(
        '',
        xy=end,
        xytext=start,
        arrowprops=dict(
            arrowstyle='->',
            color=color,
            lw=width,
            shrinkA=0,
            shrinkB=0
        )
    )

def set_petri_style():
    """Apply Petri plotting style globally"""
    plt.style.use('petri')  # Assumes petri.mplstyle is installed

# Example usage
if __name__ == "__main__":
    fig, ax = plt.subplots(figsize=(8, 6))

    # Sample flowchart
    flow_box(ax, "Formulate\nhypothesis", (0.5, 3), color=OAT)
    flow_box(ax, "Design\nscenarios", (0.5, 2), color=ORANGE, alpha=0.3)
    flow_box(ax, "Run\nexperiments", (0.5, 1), color=BLUE, alpha=0.3)
    flow_box(ax, "Iterate", (0.5, 0), color=MINT, alpha=0.3)

    flow_arrow(ax, (1.5, 3), (1.5, 2.8))
    flow_arrow(ax, (1.5, 2), (1.5, 1.8))
    flow_arrow(ax, (1.5, 1), (1.5, 0.8))

    ax.set_xlim(0, 4)
    ax.set_ylim(-0.5, 4)
    ax.axis('off')

    plt.tight_layout()
    timestamp = utc_timestamp()
    filename = f'petri_example_{timestamp}.png'
    plt.savefig(filename, dpi=300)
    print(f'Saved {filename}')
    plt.show()
