"""
Anthropic Plot Styling Module

A lightweight module for making Anthropic-branded plots.

Usage:
    import anthroplot
    anthroplot.set_defaults(pretty=True)

- pretty=True: Editorial colors (warm, visually appealing)
- pretty=False: Colorblind-friendly (seaborn colorblind rearranged)

Note: Brand fonts (Styrene B LC, Tiempos Text) require internal font access.
The module falls back to system fonts if brand fonts are unavailable.
"""

import os
from collections.abc import Callable
from pathlib import Path

import matplotlib.pyplot as plt
from matplotlib import font_manager
from seaborn.palettes import SEABORN_PALETTES


# =============================================================================
# PRIMARY BRAND COLORS (from go/brand)
# =============================================================================

GREY_950 = SLATE = "#141413"
GREY_050 = IVORY = "#FAF9F5"
CLAY = "#D97757"

# Secondary Brand Colors
OAT = "#E3DACC"
CORAL = "#EBCECE"

# Other Secondary Colors
FIG = "#C46686"
SKY = "#6A9BCC"
OLIVE = "#788C5D"
HEATHER = "#CBCADB"
CACTUS = "#BCD1CA"


# =============================================================================
# GRAYSCALE SYSTEM
# =============================================================================

GRAY_1000 = "#000000"
GRAY_950 = "#141413"
GRAY_900 = "#1A1918"
GRAY_850 = "#1F1E1D"
GRAY_800 = "#262624"
GRAY_750 = "#30302E"
GRAY_700 = "#3D3D3A"
GRAY_650 = "#4D4C48"
GRAY_600 = "#5E5D59"
GRAY_550 = "#73726C"
GRAY_500 = "#87867F"
GRAY_450 = "#9C9A92"
GRAY_400 = "#B0AEA5"
GRAY_350 = "#C2C0B6"
GRAY_300 = "#D1CFC5"
GRAY_250 = "#DEDCD1"
GRAY_200 = "#E8E6DC"
GRAY_150 = "#F0EEE6"
GRAY_100 = "#F5F4ED"
GRAY_050 = "#FAF9F5"


# =============================================================================
# TERTIARY SYSTEM (Gradients: 100=light, 900=dark)
# =============================================================================

ORANGE_900 = "#301107"
ORANGE_800 = "#5E230F"
ORANGE_700 = "#8C3619"
ORANGE_600 = "#BA4C27"
ORANGE_500 = "#E86235"
ORANGE_400 = "#ED8461"
ORANGE_300 = "#F2A88F"
ORANGE_200 = "#F5CBBC"
ORANGE_100 = "#FAEFEB"

YELLOW_900 = "#301901"
YELLOW_800 = "#633806"
YELLOW_700 = "#965B0E"
YELLOW_600 = "#C77F1A"
YELLOW_500 = "#FAA72A"
YELLOW_400 = "#FABD5A"
YELLOW_300 = "#FACF89"
YELLOW_200 = "#FAE1B9"
YELLOW_100 = "#FAF3E8"

GREEN_900 = "#0E2402"
GREEN_800 = "#214708"
GREEN_700 = "#386910"
GREEN_600 = "#568C1C"
GREEN_500 = "#76AD2A"
GREEN_400 = "#90BF4E"
GREEN_300 = "#AFD47D"
GREEN_200 = "#D0E5B1"
GREEN_100 = "#F1F7E9"

AQUA_900 = "#02211C"
AQUA_800 = "#07473B"
AQUA_700 = "#0E6B54"
AQUA_600 = "#188F6B"
AQUA_500 = "#24B283"
AQUA_400 = "#4DC49C"
AQUA_300 = "#7AD6B7"
AQUA_200 = "#AEE5D3"
AQUA_100 = "#E9F7F2"

BLUE_900 = "#011A33"
BLUE_800 = "#06325E"
BLUE_700 = "#0F4B87"
BLUE_600 = "#1B67B2"
BLUE_500 = "#2C84DB"
BLUE_400 = "#599EE3"
BLUE_300 = "#86B8EB"
BLUE_200 = "#BAD7F5"
BLUE_100 = "#EDF5FC"

VIOLET_900 = "#141133"
VIOLET_800 = "#26215C"
VIOLET_700 = "#383182"
VIOLET_600 = "#4D44AB"
VIOLET_500 = "#6258D1"
VIOLET_400 = "#827ADE"
VIOLET_300 = "#A49EE8"
VIOLET_200 = "#CAC6F5"
VIOLET_100 = "#F1F0FF"

MAGENTA_900 = "#2E0B17"
MAGENTA_800 = "#5E1C32"
MAGENTA_700 = "#8A2D4C"
MAGENTA_600 = "#B54369"
MAGENTA_500 = "#E05A87"
MAGENTA_400 = "#E87DA1"
MAGENTA_300 = "#F0A1BB"
MAGENTA_200 = "#F5C6D6"
MAGENTA_100 = "#FCF0F4"

RED_900 = "#300B0B"
RED_800 = "#5C1616"
RED_700 = "#8A2424"
RED_600 = "#B53333"
RED_500 = "#E04343"
RED_400 = "#E86B6B"
RED_300 = "#F09595"
RED_200 = "#F7C1C1"
RED_100 = "#FCEDED"


# =============================================================================
# LEGACY / NON-BRAND COLORS
# =============================================================================

BACKGROUND = "#FFFBF9"
LIGHT_ORANGE = MANILLA = "#F2E0BD"
MEDIUM_ORANGE = KRAFT = "#D19B75"
DARK_ORANGE = BOOK_CLOTH = "#B86046"

DARK_BLUE = "#40668C"
GREY = "#656565"
LIGHT_PURPLE = "#8778AB"
DARK_PURPLE = "#4A366F"

LIGHT_IVORY = "#FAF9F7"
MEDIUM_IVORY = "#F0EFEB"
DARK_IVORY = "#E5E5E1"
LIGHT_SLATE = "#666664"
MEDIUM_SLATE = "#424241"
DARK_SLATE = "#1F1F1E"

LIGHT_OCHRE = "#CCA485"
DARK_OCHRE = "#CC7D5E"


# =============================================================================
# FONTS
# =============================================================================

SERIF_FONT = "Tiempos Text"
SANS_SERIF_FONT = "Styrene B LC"
TEMP_FONT_DIR = "/mnt/notebooks/meg/fonts/"

SERIF_FONT_FALLBACKS = ["cmb10"]
SANS_SERIF_FONT_FALLBACKS = [
    "Avenir",
    "DejaVu Sans Mono",
    "cmss10",
    "Liberation Mono",
]


# =============================================================================
# COLOR CYCLES
# =============================================================================

PRETTY_CYCLE = [
    DARK_ORANGE,
    GREY,
    DARK_BLUE,
    MEDIUM_ORANGE,
    LIGHT_PURPLE,
    DARK_PURPLE,
]

# Rearranged seaborn colorblind: Anthropic-y colors come earlier
# (dark blue, dark orange, grey, pink, orange, green, light blue...)
ALT_CYCLE = [
    SEABORN_PALETTES["colorblind"][i] for i in [0, 3, 7, 4, 1, 2, 9, 6, 5, 8]
]


# =============================================================================
# ANNOTATION HELPERS
# =============================================================================

BBOX_FORMAT = dict(fc="whitesmoke", ec="lightgrey", alpha=1, boxstyle="round")
PROMPT_FORMAT = dict(fontfamily="serif", fontsize=8, bbox=BBOX_FORMAT)


def annotate_values(
    ax: plt.Axes,
    x_offset: float = 0.0,
    y_offset: float = 0.02,
    format: Callable[[float], str] = lambda x: f"{x:.0%}",
    fontsize: int = 8,
    bbox: dict | None = None,
    annotate_bars: bool = True,
    annotate_lines: bool = True,
) -> None:
    """Add value labels to bars and/or lines on a plot."""
    if annotate_bars:
        for p in ax.patches:
            x, y = p.get_x() + p.get_width() / 2, p.get_height()
            ax.text(
                x + x_offset,
                y + y_offset,
                format(y),
                ha="center",
                fontsize=fontsize,
                bbox=bbox,
            )
    if annotate_lines:
        for line in ax.get_lines():
            for x, y in zip(line.get_xdata(), line.get_ydata(), strict=True):
                ax.text(
                    x + x_offset,
                    y + y_offset,
                    format(y),
                    ha="center",
                    fontsize=fontsize,
                    bbox=bbox,
                )


def format_yaxis(
    ax: plt.Axes,
    format: Callable[[float], str] = lambda x: f"{x:.0%}",
) -> None:
    """Format y-axis tick labels using a custom format function."""
    ax.set_yticklabels([format(x) for x in ax.get_yticks()])


def make_axes_transparent(ax: plt.Axes) -> None:
    """Remove all axes elements for a clean transparent plot."""
    ax.set_xticks([])
    ax.set_yticks([])
    ax.spines["right"].set_visible(False)
    ax.spines["top"].set_visible(False)
    ax.spines["bottom"].set_visible(False)
    ax.spines["left"].set_visible(False)
    ax.set_facecolor("none")


# =============================================================================
# FONT MANAGEMENT
# =============================================================================


def add_fonts(fontpaths: str | list[str]) -> None:
    """Add fonts from specified paths to matplotlib's font manager."""
    if isinstance(fontpaths, str):
        fontpaths = [fontpaths]
    font_files = font_manager.findSystemFonts(fontpaths=fontpaths)
    for font_file in font_files:
        font_manager.fontManager.addfont(font_file)


def _ignore_type(x):
    """Helper to handle rcParams that may be list or other types."""
    if isinstance(x, list):
        return x
    return list(x) if hasattr(x, "__iter__") and not isinstance(x, str) else [x]


# =============================================================================
# DEFAULT SETTERS
# =============================================================================


def set_default_fonts(fontpaths: str | list[str] | None = TEMP_FONT_DIR) -> None:
    """Configure matplotlib to use Anthropic brand fonts with fallbacks."""
    if fontpaths is not None:
        add_fonts(fontpaths)

    current_serif = _ignore_type(plt.rcParams["font.serif"])
    if SERIF_FONT not in current_serif:
        plt.rcParams["font.serif"] = [SERIF_FONT] + SERIF_FONT_FALLBACKS + current_serif

    current_sans = _ignore_type(plt.rcParams["font.sans-serif"])
    if SANS_SERIF_FONT not in current_sans:
        plt.rcParams["font.sans-serif"] = (
            [SANS_SERIF_FONT] + SANS_SERIF_FONT_FALLBACKS + current_sans
        )

    plt.rcParams["font.family"] = "sans-serif"


def set_default_colors() -> None:
    """Set Anthropic brand colors for axes elements."""
    plt.rcParams["xtick.color"] = LIGHT_SLATE
    plt.rcParams["ytick.color"] = LIGHT_SLATE
    plt.rcParams["axes.edgecolor"] = LIGHT_SLATE
    plt.rcParams["axes.titlecolor"] = DARK_ORANGE


def set_default_cycle(pretty: bool = False) -> None:
    """Set the color cycle for plots."""
    from cycler import cycler

    cycle = PRETTY_CYCLE if pretty else ALT_CYCLE
    plt.rcParams["axes.prop_cycle"] = cycler(color=cycle)


def set_default_axes(
    figsize: tuple = (5, 5),
    autolayout: bool = True,
) -> None:
    """Set default figure size and layout options."""
    plt.rcParams["figure.figsize"] = figsize
    plt.rcParams["figure.autolayout"] = autolayout


def set_plotly_defaults(
    fontpaths: str | list[str] | None = TEMP_FONT_DIR,
    pretty: bool = False,
) -> None:
    """Configure Plotly to use Anthropic styling."""
    import plotly.graph_objects as go
    import plotly.io as pio

    if fontpaths is not None:
        add_fonts(fontpaths)

    pio.templates["anthroplot"] = go.layout.Template(
        layout=dict(
            font=dict(family=f"{SANS_SERIF_FONT}, sans-serif"),
            colorway=PRETTY_CYCLE if pretty else ALT_CYCLE,
        ),
    )
    pio.templates.default = "anthroplot"


def set_defaults(
    fontpaths: str | list[str] | None = TEMP_FONT_DIR,
    pretty: bool = False,
    figsize: tuple = (5, 5),
    autolayout: bool = True,
    matplotlib: bool = True,
    plotly: bool = True,
    install_brand_fonts: bool = False,
) -> None:
    """
    Configure default plotting settings for matplotlib and/or plotly.

    Args:
        fontpaths: Path(s) to font directories. Defaults to TEMP_FONT_DIR.
        pretty: Use prettier plot styling with enhanced aesthetics (True) or
                colorblind-friendly colors (False).
        figsize: Default figure size as (width, height) tuple.
        autolayout: Enable automatic tight layout adjustment.
        matplotlib: Apply settings to matplotlib.
        plotly: Apply settings to plotly.
        install_brand_fonts: If True, attempts to download Anthropic brand fonts.
            Note: This requires internal S3 access and will fail externally.
    """
    # Normalize fontpaths to a list
    if isinstance(fontpaths, str):
        fontpaths = [fontpaths]
    elif fontpaths is None:
        fontpaths = []

    # Note: install_brand_fonts requires internal Anthropic infrastructure
    # and is not functional in external environments
    if install_brand_fonts:
        print(
            "Warning: install_brand_fonts requires internal Anthropic font access. "
            "Fonts will fall back to system defaults."
        )

    if matplotlib:
        set_default_fonts(fontpaths=fontpaths if fontpaths else None)
        set_default_colors()
        set_default_cycle(pretty=pretty)
        set_default_axes(figsize=figsize, autolayout=autolayout)

    if plotly:
        try:
            set_plotly_defaults(fontpaths=fontpaths if fontpaths else None, pretty=pretty)
        except ImportError:
            pass  # Plotly not installed, skip
