"""palette — the single source of truth for every house colour.

One module, three palettes, no plotting code. Kept free of matplotlib imports so
that `export_tokens()` can run anywhere (including in a plain `python3` with no
scientific stack installed) and so artifact pages and matplotlib figures are
driven by the same hexes.

- `brand`  — official Anthropic values. Never edit these to taste.
- `pastel` — softened derivations of the brand secondaries. House default.
- `petri`  — the paper-figure palette on a warm ivory ground.

`ACCENT_FOR` maps each pastel to its saturated brand sibling, which is the
"draw everything pastel, draw the one series you mean in its accent" pattern.

Consumers:
    lib/plotting/style.py   matplotlib rcParams and helpers
    lib/plotting/diagrams.py  flow-diagram primitives
    lib/plotting/tokens.json  generated; imported by artifact pages for SVG charts
"""

from __future__ import annotations

import json
from pathlib import Path

# --- Brand anchors (official) -------------------------------------------------
SLATE = "#141413"  # text / near-black
IVORY = "#FAF9F5"  # warm brand background

# --- Official brand secondaries ----------------------------------------------
CLAY = "#D97757"
SKY = "#6A9BCC"
OLIVE = "#788C5D"
FIG = "#C46686"

# Emphasis aliases — same hexes, named for the role they play beside a pastel.
ACCENT_CLAY = CLAY
ACCENT_SKY = SKY
ACCENT_OLIVE = OLIVE
ACCENT_FIG = FIG

# --- Official brand tertiaries -----------------------------------------------
BOOK_CLOTH = DARK_ORANGE = "#B86046"
KRAFT = MEDIUM_ORANGE = "#D19B75"
MANILLA = LIGHT_ORANGE = "#F2E0BD"
DARK_BLUE = "#40668C"
GREY = "#656565"
LIGHT_PURPLE = "#8778AB"
DARK_PURPLE = "#4A366F"

# --- Pastel categorical palette (derived, softened — NOT brand values) --------
PASTEL_CLAY = "#E8A288"
PASTEL_SKY = "#9DBFE3"
PASTEL_OLIVE = "#A9BC8F"
PASTEL_FIG = "#D99BB4"
PASTEL_VIOLET = "#B3A5D3"
PASTEL_SAND = "#E3C692"
PASTEL_AQUA = "#93C7C1"
PASTEL_GRAY = "#B9B6AE"

# --- Petri (paper figures) ----------------------------------------------------
PETRI_CORAL = "#D97757"
PETRI_MINT = "#93C7C1"
PETRI_SAND = "#E3C692"

# --- Cycles -------------------------------------------------------------------
PASTEL_CYCLE: list[str] = [
    PASTEL_CLAY, PASTEL_SKY, PASTEL_OLIVE, PASTEL_FIG,
    PASTEL_VIOLET, PASTEL_SAND, PASTEL_AQUA, PASTEL_GRAY,
]

BRAND_CYCLE: list[str] = [
    BOOK_CLOTH, GREY, DARK_BLUE, LIGHT_PURPLE, CLAY, OLIVE,
]

PETRI_CYCLE: list[str] = [
    PETRI_CORAL, PETRI_MINT, PETRI_SAND, PASTEL_SKY, FIG, PASTEL_OLIVE,
]

# Colour-blind-safer alternative, for when the pastel cycle is too close together.
ALT_CYCLE: list[str] = [DARK_BLUE, CLAY, OLIVE, LIGHT_PURPLE, GREY, PETRI_MINT]

# Pastel → matching accent, for "highlight one series" patterns.
ACCENT_FOR: dict[str, str] = {
    PASTEL_CLAY: ACCENT_CLAY,
    PASTEL_SKY: ACCENT_SKY,
    PASTEL_FIG: ACCENT_FIG,
    PASTEL_OLIVE: ACCENT_OLIVE,
}

FONT_STACK = ["Styrene B LC", "Helvetica Neue", "Helvetica", "Arial", "DejaVu Sans"]

# --- Named styles -------------------------------------------------------------
# `grid` and `background` are the only things that differ beyond the cycle, so a
# style is data, not code. Chosen default: pastel_grid (Yulong, 2026-08-28) — the
# faint y-grid makes values readable without a label on every bar.
STYLES: dict[str, dict] = {
    "pastel_grid": {
        "cycle": PASTEL_CYCLE, "emphasis": ACCENT_CLAY,
        "background": "#FFFFFF", "grid": True,
    },
    "pastel": {
        "cycle": PASTEL_CYCLE, "emphasis": ACCENT_CLAY,
        "background": "#FFFFFF", "grid": False,
    },
    "brand": {
        "cycle": BRAND_CYCLE, "emphasis": BOOK_CLOTH,
        "background": "#FFFFFF", "grid": False,
    },
    "petri": {
        "cycle": PETRI_CYCLE, "emphasis": PETRI_CORAL,
        "background": IVORY, "grid": True,
    },
}

DEFAULT_STYLE = "pastel_grid"


def style(name: str | None = None) -> dict:
    """Return a named style dict. Unknown names fail loudly rather than falling back."""
    name = name or DEFAULT_STYLE
    if name not in STYLES:
        raise KeyError(f"unknown style {name!r}; known: {', '.join(sorted(STYLES))}")
    return STYLES[name]


def tokens() -> dict:
    """The palette as plain data, for artifact pages drawing charts in SVG."""
    return {
        "default_style": DEFAULT_STYLE,
        "ink": SLATE,
        "ivory": IVORY,
        "styles": STYLES,
        "accent_for": ACCENT_FOR,
        "cycles": {
            "pastel": PASTEL_CYCLE,
            "brand": BRAND_CYCLE,
            "petri": PETRI_CYCLE,
            "alt": ALT_CYCLE,
        },
    }


def export_tokens(path: str | Path | None = None) -> Path:
    """Write tokens.json beside this module. Artifacts read the hexes from here.

    This is what keeps an SVG chart on an artifact page and a matplotlib figure
    in a paper on the same colours: one source, two renderers.
    """
    path = Path(path) if path else Path(__file__).with_name("tokens.json")
    path.write_text(json.dumps(tokens(), indent=2) + "\n")
    return path


if __name__ == "__main__":
    print("wrote", export_tokens())
