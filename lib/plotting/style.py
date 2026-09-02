"""style — matplotlib defaults and annotation helpers for the house look.

Merged from `pastelplot.py` (which lived, wrongly, inside a skill's references/)
and the same-named functions in `anthro_colors.py`. Where the two had drifted,
the pastelplot implementation won every time, and for concrete reasons worth
keeping written down:

- `format_yaxis` — the old version called `ax.set_yticklabels(...)`, which pins
  labels to the tick positions as they were at call time. Any later rescale and
  the labels silently describe the wrong values. This uses a `FuncFormatter`,
  which re-runs on every draw.
- `annotate_values` — the old version iterated raw `ax.patches` (which catches
  any patch, not just bars) and put a label on *every point* of every line.
  This uses `ax.bar_label` per container, and labels only line endpoints.
- `make_axes_transparent` — equivalent behaviour, less repetition.

`set_defaults` keeps the breadth of the anthro_colors version (it can still be
pointed at another palette) but is styled by name rather than by flag.

Colours all come from `palette.py`; nothing here defines a hex.
"""

from __future__ import annotations

from collections.abc import Callable, Iterable

import matplotlib as mpl
import matplotlib.pyplot as plt
from cycler import cycler
from matplotlib import ticker
from matplotlib.patches import FancyBboxPatch

# Flat imports, not relative: lib/plotting is deployed to ~/.local/lib/plotting and
# put on sys.path as a bare directory, not installed as a package. There is no
# __init__.py, so `from . import palette` would raise here.
import palette
from palette import ACCENT_FOR, SLATE  # noqa: F401  (re-exported for callers)

__all__ = [
    "set_defaults",
    "annotate_values",
    "format_yaxis",
    "make_axes_transparent",
    "rounded_bars",
    "emphasis_colors",
]


def set_defaults(style: str | None = None, cycle: Iterable[str] | None = None) -> None:
    """Apply house defaults to matplotlib rcParams. Call before plotting.

    Args:
        style: a name from `palette.STYLES` (default `palette.DEFAULT_STYLE`).
        cycle: explicit colour cycle, overriding the style's own.
    """
    st = palette.style(style)
    colors = list(cycle) if cycle is not None else st["cycle"]
    bg = st["background"]
    mpl.rcParams.update({
        "figure.facecolor": bg,
        "figure.figsize": (8, 5),
        "figure.dpi": 150,
        "axes.facecolor": bg,
        "axes.edgecolor": SLATE,
        "axes.labelcolor": SLATE,
        "axes.linewidth": 0.8,
        "axes.spines.top": False,
        "axes.spines.right": False,
        "axes.prop_cycle": cycler(color=colors),
        "axes.titlesize": 14,
        "axes.titleweight": "bold",
        "axes.labelsize": 11,
        "axes.grid": st["grid"],
        "axes.axisbelow": True,
        "grid.color": "#E5E5E5",
        "grid.linewidth": 0.6,
        "grid.alpha": 0.8,
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
        "font.sans-serif": palette.FONT_STACK,
        "font.size": 10,
        "savefig.dpi": 300,
        "savefig.facecolor": bg,
        "savefig.bbox": "tight",
        "savefig.pad_inches": 0.1,
    })
    if st["grid"]:
        mpl.rcParams["axes.grid.axis"] = "y"


def emphasis_colors(n: int, highlight: int | None = None, style: str | None = None) -> list[str]:
    """`n` colours from the style's cycle, with one swapped for its accent.

    The house "highlight one series" pattern: everything pastel, the series you
    mean in its matching saturated brand colour.
    """
    st = palette.style(style)
    cyc = st["cycle"]
    out = [cyc[i % len(cyc)] for i in range(n)]
    if highlight is not None:
        base = out[highlight]
        out[highlight] = ACCENT_FOR.get(base, st["emphasis"])
    return out


def annotate_values(ax: plt.Axes, format: Callable[[float], str] = lambda x: f"{x:g}") -> None:
    """Label bar heights (all bar containers) and line endpoints on `ax`."""
    for container in ax.containers:
        labels = [format(v) if v is not None else "" for v in container.datavalues]
        ax.bar_label(container, labels=labels, color=SLATE, fontsize=9, padding=2)
    for line in ax.get_lines():
        xdata, ydata = line.get_xdata(), line.get_ydata()
        if len(xdata) == 0:
            continue
        ax.annotate(
            format(float(ydata[-1])), (xdata[-1], ydata[-1]),
            textcoords="offset points", xytext=(6, 0),
            va="center", fontsize=9, color=SLATE,
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


def rounded_bars(ax: plt.Axes, radius: float = 0.06) -> None:
    """Swap each bar on `ax` for a rounded-corner patch, keeping its colour.

    Call AFTER plotting the bars and BEFORE `annotate_values`, since it replaces
    the artists. `radius` is in data-x units; the aspect correction keeps the
    corner visually round rather than stretched by the axes' aspect ratio.

    Bars are removed and re-added rather than mutated because a `Rectangle`
    cannot become a `FancyBboxPatch` in place.
    """
    for patch in list(ax.patches):
        bb = patch.get_bbox()
        if bb.width <= 0 or bb.height <= 0:
            continue  # zero-height bars have no corner to round
        color = patch.get_facecolor()
        patch.remove()
        ax.add_patch(FancyBboxPatch(
            (bb.xmin, bb.ymin), bb.width, bb.height,
            boxstyle=f"round,pad=0,rounding_size={radius}",
            mutation_aspect=bb.height / bb.width * 0.6,
            facecolor=color, edgecolor="none", linewidth=0,
        ))
