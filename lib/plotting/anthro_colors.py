"""
This is a lightweight module for making Anthropic-y plots.

anthroplot.set_defaults()

- You can change the color cycle to be more/less readable with pretty=True/False.
- If the fonts don't load, set `install_brand_fonts=True` in `set_defaults` to download the fonts from S3.
"""

import os
from collections.abc import Callable
from pathlib import Path

import matplotlib.pyplot as plt
from matplotlib import font_manager
from seaborn.palettes import SEABORN_PALETTES

import log

# updated Anthropic colors (from go/brand)

# Primary Brand Colors
GREY_950 = SLATE = "#141413"
GREY_050 = IVORY = "#FAF9F5"
CLAY = "#D97757"

# Secondary Brand Colors
OAT = "#E3DACC"
CORAL = "#EBCECE"

# Other Seconday Colors
FIG = "#C46686"
SKY = "#6A9BCC"
OLIVE = "#788C5D"
HEATHER = "#CBCADB"
CACTUS = "#BCD1CA"


# Grayscale System
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


# Tertiary System
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

# Anthropic colors
BACKGROUND = "#FFFBF9"
LIGHT_ORANGE = MANILLA = "#F2E0BD"
MEDIUM_ORANGE = KRAFT = "#D19B75"
DARK_ORANGE = BOOK_CLOTH = "#B86046"

# Non-branding colors
DARK_BLUE = "#40668C"
GREY = "#656565"
LIGHT_PURPLE = "#8778AB"
DARK_PURPLE = "#4A366F"

# Monochrome colors
LIGHT_IVORY = "#FAF9F7"
MEDIUM_IVORY = "#F0EFEB"
DARK_IVORY = "#E5E5E1"
LIGHT_SLATE = "#666664"
MEDIUM_SLATE = "#424241"
DARK_SLATE = "#1F1F1E"

# Legacy colors
LIGHT_OCHRE = "#CCA485"
DARK_OCHRE = "#CC7D5E"

# Fonts
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

# Cycles
PRETTY_CYCLE = [
    DARK_ORANGE,
    GREY,
    DARK_BLUE,
    MEDIUM_ORANGE,
    LIGHT_PURPLE,
    DARK_PURPLE,
]
ALT_CYCLE = [
    SEABORN_PALETTES["colorblind"][i] for i in [0, 3, 7, 4, 1, 2, 9, 6, 5, 8]
]  # rearrange s.t. Anthropic-y colors come earlier: dark blue, dark orange, grey, pink, orange, green, light blue...

# Annotation
BBOX_FORMAT = dict(fc="whitesmoke", ec="lightgrey", alpha=1, boxstyle="round")
PROMPT_FORMAT = dict(fontfamily="serif", fontsize=8, bbox=BBOX_FORMAT)


def annotate_values(
    ax: plt.Axes,
    x_offset: float = 0.0,
    y_offset: float = 0.02,
    format=lambda x: f"{x:.0%}",
    fontsize: int = 8,
    bbox: dict | None = None,
    annotate_bars: bool = True,
    annotate_lines: bool = True,
):
    if annotate_bars:
        for p in ax.patches:
            x, y = p.get_x() + p.get_width() / 2, p.get_height()  # pyright: ignore[reportAttributeAccessIssue]
            ax.text(
                x + x_offset,
                y + y_offset,
                format(y),
                ha="center",
                fontsize=fontsize,
                bbox=bbox,
            )

    if annotate_lines:
        for l in ax.get_lines():
            for x, y in zip(l.get_xdata(), l.get_ydata(), strict=True):  # pyright: ignore[reportArgumentType]
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
    ax.set_yticklabels([format(x) for x in ax.get_yticks()])  # pyright: ignore[reportCallIssue]


def make_axes_transparent(ax: plt.Axes):
    ax.set_xticks([])
    ax.set_yticks([])
    ax.spines["right"].set_visible(False)
    ax.spines["top"].set_visible(False)
    ax.spines["bottom"].set_visible(False)
    ax.spines["left"].set_visible(False)
    ax.set_facecolor("none")


def add_fonts(fontpaths: str | list[str]):
    font_files = font_manager.findSystemFonts(fontpaths=fontpaths)
    for font_file in font_files:
        font_manager.fontManager.addfont(font_file)


def _install_brand_fonts() -> str:
    """Internal function to install brand fonts and return the font directory path."""
 	fonts = TODO
    # Copy all the fonts to the local directory
    for font in fonts:
        destination = font_dir / font.name
        if destination.exists():
            log.warn(f"Font {font.name} already exists in {font_dir}. Skipping copy.")
        else:
            try:
                font.copy(font_dir / font.name)
            except FileExistsError:
                # Sometimes this function is called multiple times in parallel, and we might experience a race condition
                # where the other invocation completes the font copy first after the existence check above. We don't
                # want to crash, so we ignore the error. We still want to keep the font existence check above, as
                # the `FileExistsError` is thrown only _after_ the file is downloaded and we want to avoid unnecessary
                # IO.
                pass

    return font_dir.path


def set_plotly_defaults(
    fontpaths: str | list[str] | None = TEMP_FONT_DIR,
    pretty: bool = False,
):
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


def set_default_fonts(fontpaths: str | list[str] | None = TEMP_FONT_DIR):
    if fontpaths is not None:
        add_fonts(fontpaths)
    if SERIF_FONT not in ignore_type(plt.rcParams["font.serif"]):
        plt.rcParams["font.serif"] = (
            [SERIF_FONT]
            + SERIF_FONT_FALLBACKS
            + ignore_type(
                plt.rcParams["font.serif"],
            )
        )
    if SANS_SERIF_FONT not in ignore_type(plt.rcParams["font.sans-serif"]):
        plt.rcParams["font.sans-serif"] = (
            [SANS_SERIF_FONT]
            + SANS_SERIF_FONT_FALLBACKS
            + ignore_type(plt.rcParams["font.serif"])
        )
    plt.rcParams["font.family"] = "sans-serif"


def set_default_colors():
    plt.rcParams["xtick.color"] = LIGHT_SLATE
    plt.rcParams["ytick.color"] = LIGHT_SLATE
    plt.rcParams["axes.edgecolor"] = LIGHT_SLATE
    plt.rcParams["axes.titlecolor"] = DARK_ORANGE


def set_default_cycle(pretty: bool = False) -> None:
    from cycler import cycler

    cycle = PRETTY_CYCLE if pretty else ALT_CYCLE
    plt.rcParams["axes.prop_cycle"] = cycler(color=cycle)


def set_default_axes(
    figsize: tuple = (5, 5),
    autolayout: bool = True,
) -> None:
    plt.rcParams["figure.figsize"] = figsize
    plt.rcParams["figure.autolayout"] = autolayout


def set_defaults(
    fontpaths: str | list[str] | None = TEMP_FONT_DIR,
    pretty: bool = False,
    figsize: tuple = (5, 5),
    autolayout: bool = True,
    matplotlib: bool = True,
    plotly: bool = True,
    install_brand_fonts: bool = False,
):
    """Configure default plotting settings for matplotlib and/or plotly. Brand fonts
    will be downloaded if `install_brand_fonts` is True or you are using the default
    `fontpaths` and the directory is empty or does not exist.

    Args:
        fontpaths: Path(s) to font directories. Defaults to TEMP_FONT_DIR.
        pretty: Use prettier plot styling with enhanced aesthetics.
        figsize: Default figure size as (width, height) tuple.
        autolayout: Enable automatic tight layout adjustment.
        matplotlib: Apply settings to matplotlib.
        plotly: Apply settings to plotly.
        install_brand_fonts: Download and include Anthropic brand fonts.
            If True, appends the brand fonts directory to fontpaths.
    """

    # Normalize fontpaths to a list
    if isinstance(fontpaths, str):
        fontpaths = [fontpaths]
    elif fontpaths is None:
        fontpaths = []

    # Install the brand fonts if:
    # - install_brand_fonts is True
    # - fontpaths is [TEMP_FONT_DIR] and it is empty/does not exist
    if install_brand_fonts or (
        fontpaths == [TEMP_FONT_DIR]
        and not (os.path.isdir(TEMP_FONT_DIR) and os.listdir(TEMP_FONT_DIR))
    ):
        fontpaths.append(_install_brand_fonts())

    if matplotlib:
        set_default_fonts(fontpaths=fontpaths)
        set_default_colors()
        set_default_cycle(pretty=pretty)
        set_default_axes(figsize=figsize, autolayout=autolayout)
    if plotly:
        set_plotly_defaults(fontpaths=fontpaths, pretty=pretty)


def use_anthropic_defaults():
    """Set anthropic style as default for all matplotlib plots.

    This configures matplotlib to use the anthropic.mplstyle by default
    without requiring explicit plt.style.use('anthropic') calls.

    Usage in Claude Code plotting:
        from anthro_colors import use_anthropic_defaults
        use_anthropic_defaults()

    All plots will then use:
    - White background (#FFFFFF)
    - Anthropic's PRETTY_CYCLE colors
    - Consistent typography and spacing
    """
    from pathlib import Path

    # Load anthropic style from absolute path
    style_path = Path.home() / '.config' / 'matplotlib' / 'stylelib' / 'anthropic.mplstyle'
    if style_path.exists():
        plt.style.use(str(style_path))
    else:
        # Fallback: apply key settings programmatically if style file not deployed
        plt.rcParams['figure.facecolor'] = '#FFFFFF'
        plt.rcParams['axes.facecolor'] = '#FFFFFF'
        plt.rcParams['savefig.facecolor'] = '#FFFFFF'
        # Use PRETTY_CYCLE
        from cycler import cycler
        plt.rcParams['axes.prop_cycle'] = cycler(color=PRETTY_CYCLE)
