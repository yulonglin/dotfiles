"""pastelplot — pastel matplotlib styling with small annotation helpers.

Successor to the internal anthroplot module (whose .py reference is no longer
available): same idea — drop-in defaults plus a few helpers — but with a pastel
categorical palette and no internal-font (S3) dependency. Copy this file into a
project, or add its directory to sys.path from the skill.

The pastel hexes are softened derivations of the Anthropic brand secondaries
(CLAY/SKY/OLIVE/FIG), NOT official brand values. SLATE/IVORY and the ACCENT_*
colors are the original brand hexes.

Usage:
    import pastelplot
    pastelplot.set_defaults()  # call before plotting
"""

from __future__ import annotations

from collections.abc import Callable, Iterable

import matplotlib as mpl
import matplotlib.pyplot as plt
from cycler import cycler
from matplotlib import ticker

# --- Brand anchors (official hexes) ---
SLATE = "#141413"  # text / near-black
IVORY = "#FAF9F5"  # brand background (defaults below use white for figures)

# --- Pastel categorical palette (derived, softened) ---
PASTEL_CLAY = "#E8A288"
PASTEL_SKY = "#9DBFE3"
PASTEL_OLIVE = "#A9BC8F"
PASTEL_FIG = "#D99BB4"
PASTEL_VIOLET = "#B3A5D3"
PASTEL_SAND = "#E3C692"
PASTEL_AQUA = "#93C7C1"
PASTEL_GRAY = "#B9B6AE"

PASTEL_CYCLE: list[str] = [
    PASTEL_CLAY,
    PASTEL_SKY,
    PASTEL_OLIVE,
    PASTEL_FIG,
    PASTEL_VIOLET,
    PASTEL_SAND,
    PASTEL_AQUA,
    PASTEL_GRAY,
]

# --- Saturated accents (official brand secondaries) for emphasis ---
ACCENT_CLAY = "#D97757"
ACCENT_SKY = "#6A9BCC"
ACCENT_FIG = "#C46686"
ACCENT_OLIVE = "#788C5D"

# Pastel → matching accent, for "highlight one series" patterns
ACCENT_FOR: dict[str, str] = {
    PASTEL_CLAY: ACCENT_CLAY,
    PASTEL_SKY: ACCENT_SKY,
    PASTEL_FIG: ACCENT_FIG,
    PASTEL_OLIVE: ACCENT_OLIVE,
}

_FONT_STACK = ["Styrene B LC", "Helvetica Neue", "Helvetica", "Arial", "DejaVu Sans"]


def set_defaults(cycle: Iterable[str] | None = None) -> None:
    """Apply pastel defaults to matplotlib rcParams. Call before plotting.

    Args:
        cycle: optional replacement color cycle (defaults to PASTEL_CYCLE).
    """
    colors = list(cycle) if cycle is not None else PASTEL_CYCLE
    mpl.rcParams.update(
        {
            "figure.facecolor": "white",
            "figure.figsize": (8, 5),
            "figure.dpi": 150,
            "axes.facecolor": "white",
            "axes.edgecolor": SLATE,
            "axes.labelcolor": SLATE,
            "axes.linewidth": 0.8,
            "axes.spines.top": False,
            "axes.spines.right": False,
            "axes.prop_cycle": cycler(color=colors),
            "axes.titlesize": 14,
            "axes.titleweight": "bold",
            "axes.labelsize": 11,
            "axes.grid": False,
            "grid.color": "#E5E5E5",
            "grid.linewidth": 0.5,
            "grid.alpha": 0.7,
            "xtick.color": SLATE,
            "ytick.color": SLATE,
            "xtick.labelsize": 10,
            "ytick.labelsize": 10,
            "legend.frameon": False,
            "legend.fontsize": 10,
            "lines.linewidth": 2,
            "lines.markersize": 6,
            "patch.linewidth": 0.5,
            "patch.edgecolor": SLATE,
            "font.family": "sans-serif",
            "font.sans-serif": _FONT_STACK,
            "font.size": 10,
            "savefig.dpi": 300,
            "savefig.facecolor": "white",
            "savefig.bbox": "tight",
            "savefig.pad_inches": 0.1,
        }
    )


def annotate_values(
    ax: plt.Axes, format: Callable[[float], str] = lambda x: f"{x:g}"
) -> None:
    """Label bar heights (all bar containers) and line endpoints on `ax`."""
    for container in ax.containers:
        labels = [format(v) if v is not None else "" for v in container.datavalues]
        ax.bar_label(container, labels=labels, color=SLATE, fontsize=9, padding=2)
    for line in ax.get_lines():
        xdata, ydata = line.get_xdata(), line.get_ydata()
        if len(xdata) == 0:
            continue
        ax.annotate(
            format(float(ydata[-1])),
            (xdata[-1], ydata[-1]),
            textcoords="offset points",
            xytext=(6, 0),
            va="center",
            fontsize=9,
            color=SLATE,
        )


def format_yaxis(ax: plt.Axes, format: Callable[[float], str]) -> None:
    """Apply a formatting function to y-axis tick labels, e.g. lambda x: f"{x:.0%}"."""
    ax.yaxis.set_major_formatter(ticker.FuncFormatter(lambda x, _pos: format(x)))


def make_axes_transparent(ax: plt.Axes) -> None:
    """Strip spines, ticks, and background for clean overlay plots."""
    for spine in ax.spines.values():
        spine.set_visible(False)
    ax.tick_params(left=False, bottom=False, labelleft=False, labelbottom=False)
    ax.patch.set_alpha(0)
