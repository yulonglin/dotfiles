#!/usr/bin/env python3
"""Guards for the lib/plotting merge (pastelplot + anthro_colors, 2026-08-28).

The merge deleted pastelplot.py and replaced three anthro_colors functions with
its implementations. These tests pin the reasons that was safe, so a future
"tidy-up" cannot quietly reintroduce the bugs:

- format_yaxis must survive a rescale (the set_yticklabels bug).
- annotate_values must label line ENDPOINTS, not every point.
- the palette must import with no matplotlib installed.
- lib/plotting is a flat sys.path dir, NOT a package — relative imports break it.
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parent.parent
PLOTDIR = REPO / "lib" / "plotting"

matplotlib = pytest.importorskip("matplotlib", reason="matplotlib not installed")
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

sys.path.insert(0, str(PLOTDIR))
import palette  # noqa: E402
import style as house  # noqa: E402


@pytest.fixture(autouse=True)
def _clean_rc():
    plt.rcParams.update(matplotlib.rcParamsDefault)
    yield
    plt.close("all")


# --- structure ---------------------------------------------------------------

def test_no_package_init_so_imports_must_stay_flat():
    """lib/plotting is put on sys.path as a bare directory by custom_bins/figcheck
    and by deploy. An __init__.py would make relative imports look fine locally
    while still failing there, so its ABSENCE is the contract."""
    assert not (PLOTDIR / "__init__.py").exists()
    # Check real import statements, not the whole file — style.py's own comment
    # quotes the broken form to explain why it is banned.
    for line in (PLOTDIR / "style.py").read_text().splitlines():
        stripped = line.strip()
        if stripped.startswith(("import ", "from ")):
            assert not stripped.startswith("from ."), f"relative import: {stripped}"


def test_pastelplot_is_gone_from_the_skill():
    assert not (REPO / "claude/skills/house-plots/references/pastelplot.py").exists()
    assert (PLOTDIR / "figcheck.py").exists()


def test_figcheck_bin_points_at_lib_not_the_skill():
    src = (REPO / "custom_bins" / "figcheck").read_text()
    assert "lib/plotting" in src
    assert "house-plots/references" not in src


# --- palette -----------------------------------------------------------------

def test_palette_imports_without_matplotlib():
    """export_tokens must run in a bare interpreter — it feeds artifact pages."""
    r = subprocess.run(
        [sys.executable, "-c", "import palette; print(palette.DEFAULT_STYLE)"],
        cwd=PLOTDIR, capture_output=True, text=True,
        env={"PATH": "/usr/bin:/bin", "PYTHONPATH": str(PLOTDIR)},
    )
    assert r.returncode == 0, r.stderr
    assert r.stdout.strip() == "pastel_grid"


def test_default_style_is_pastel_grid():
    assert palette.DEFAULT_STYLE == "pastel_grid"
    assert palette.style()["grid"] is True


def test_unknown_style_raises_rather_than_falling_back():
    with pytest.raises(KeyError):
        palette.style("no-such-style")


def test_tokens_json_matches_the_module():
    tokens = json.loads((PLOTDIR / "tokens.json").read_text())
    assert tokens == palette.tokens(), "tokens.json is stale — run `python3 palette.py`"


def test_every_cycle_is_valid_hex():
    for name, cyc in palette.tokens()["cycles"].items():
        for hexval in cyc:
            assert hexval.startswith("#") and len(hexval) == 7, f"{name}: {hexval}"


# --- the three fixed functions ------------------------------------------------

def test_format_yaxis_survives_a_rescale():
    """The old set_yticklabels version pinned labels to the ticks at call time."""
    fig, ax = plt.subplots()
    ax.plot([0, 1], [0, 0.5])
    house.format_yaxis(ax, lambda x: f"{x:.0%}")
    ax.set_ylim(0, 5)          # rescale AFTER formatting
    fig.canvas.draw()
    labels = [t.get_text() for t in ax.get_yticklabels() if t.get_text()]
    assert "500%" in labels, f"formatter did not follow the rescale: {labels}"


def test_annotate_values_labels_line_endpoints_only():
    fig, ax = plt.subplots()
    ax.plot(range(10), range(10))
    house.annotate_values(ax)
    assert len(ax.texts) == 1, f"expected 1 endpoint label, got {len(ax.texts)}"


def test_annotate_values_labels_every_bar():
    fig, ax = plt.subplots()
    ax.bar(["a", "b", "c"], [1, 2, 3])
    house.annotate_values(ax)
    assert len([t for t in ax.texts if t.get_text()]) == 3


def test_make_axes_transparent_hides_all_spines():
    fig, ax = plt.subplots()
    house.make_axes_transparent(ax)
    assert not any(s.get_visible() for s in ax.spines.values())
    assert ax.patch.get_alpha() == 0


# --- rounded bars -------------------------------------------------------------

def test_rounded_bars_preserves_count_and_colour():
    from matplotlib.patches import FancyBboxPatch
    fig, ax = plt.subplots()
    bars = ax.bar(["a", "b", "c"], [1, 2, 3], color=["#E8A288", "#9DBFE3", "#A9BC8F"])
    before = [b.get_facecolor() for b in bars]
    house.rounded_bars(ax)
    assert len(ax.patches) == 3
    assert all(isinstance(p, FancyBboxPatch) for p in ax.patches)
    assert [p.get_facecolor() for p in ax.patches] == before


def test_rounded_bars_leaves_zero_height_bars_alone():
    """A zero-height bar has no corner to round, so it is left as-is rather than
    removed — dropping it would silently change the artist count that bar_label
    and downstream code walk."""
    from matplotlib.patches import FancyBboxPatch, Rectangle
    fig, ax = plt.subplots()
    ax.bar(["a", "b"], [0, 2])
    house.rounded_bars(ax)
    assert len(ax.patches) == 2
    kinds = sorted(type(p).__name__ for p in ax.patches)
    assert kinds == ["FancyBboxPatch", "Rectangle"], kinds


def test_rounded_bars_then_annotate_still_labels():
    """rounded_bars replaces artists, so the documented order must keep working."""
    fig, ax = plt.subplots()
    ax.bar(["a", "b"], [1, 2])
    house.rounded_bars(ax)
    house.annotate_values(ax)
    assert len([t for t in ax.texts if t.get_text()]) == 2


# --- set_defaults -------------------------------------------------------------

def test_set_defaults_applies_the_named_cycle_and_grid():
    house.set_defaults("pastel_grid")
    cyc = [c["color"] for c in matplotlib.rcParams["axes.prop_cycle"]]
    assert cyc == palette.PASTEL_CYCLE
    assert matplotlib.rcParams["axes.grid"] is True

    house.set_defaults("brand")
    cyc = [c["color"] for c in matplotlib.rcParams["axes.prop_cycle"]]
    assert cyc == palette.BRAND_CYCLE
    assert matplotlib.rcParams["axes.grid"] is False


def test_petri_keeps_the_ivory_ground():
    house.set_defaults("petri")
    assert matplotlib.rcParams["figure.facecolor"] == palette.IVORY


def test_emphasis_swaps_one_series_for_its_accent():
    out = house.emphasis_colors(4, highlight=1, style="pastel_grid")
    assert out[1] == palette.ACCENT_SKY
    assert out[0] == palette.PASTEL_CLAY
