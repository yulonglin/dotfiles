"""Programmatic overlap detection for matplotlib figures.

Eyeballing a figure catches the collisions you happen to look at. This walks
every rendered Text and Legend artist, takes its true window extent after a
draw, and reports pairs whose boxes intersect by more than a tolerance — so a
caption sitting on a legend, or tick labels colliding with annotations, fails
loudly instead of shipping.

Usage — explicit, one figure:
    from figcheck import assert_no_overlaps
    fig.savefig(path, dpi=150, bbox_inches="tight")
    assert_no_overlaps(fig, "my figure")

Usage — automatic, every figure the process saves:
    import figcheck; figcheck.install()

Usage — a script you did not write:
    figcheck path/to/make_figs.py

Deliberately NOT checked: bar-vs-text (text above a bar is normal), and any
pair where one box fully contains the other and the outer one is a legend
frame (a legend's own entries live inside it).
"""

from __future__ import annotations

from matplotlib.legend import Legend
from matplotlib.patches import Rectangle
from matplotlib.text import Text


def _boxes(fig):
    fig.canvas.draw()
    renderer = fig.canvas.get_renderer()
    out = []
    for artist in fig.findobj(Text):
        if not artist.get_visible():
            continue
        s = artist.get_text()
        if not s or not s.strip():
            continue
        try:
            bb = artist.get_window_extent(renderer=renderer)
        except Exception:  # noqa: BLE001 — artists without a renderer path
            continue
        if bb.width <= 0 or bb.height <= 0:
            continue
        out.append((artist, s, bb))
    legends = []
    for artist in fig.findobj(Legend):
        try:
            legends.append(artist.get_window_extent(renderer=renderer))
        except Exception:  # noqa: BLE001
            pass
    return out, legends


def _overlap_area(a, b) -> float:
    dx = min(a.x1, b.x1) - max(a.x0, b.x0)
    dy = min(a.y1, b.y1) - max(a.y0, b.y0)
    return dx * dy if dx > 0 and dy > 0 else 0.0


def find_overlaps(fig, min_area_px: float = 12.0, min_frac: float = 0.06):
    """Text pairs whose boxes intersect. Returns [(s1, s2, area, frac)]."""
    items, legends = _boxes(fig)
    hits = []
    for i in range(len(items)):
        ai, si, bi = items[i]
        for j in range(i + 1, len(items)):
            aj, sj, bj = items[j]
            if ai.axes is not None and ai.axes is aj.axes and ai is aj:
                continue
            area = _overlap_area(bi, bj)
            if area <= min_area_px:
                continue
            frac = area / min(bi.width * bi.height, bj.width * bj.height)
            if frac < min_frac:
                continue
            # a legend's own label sitting inside its frame is not a collision
            inside_same_legend = any(
                _overlap_area(bi, lg) > 0.9 * bi.width * bi.height
                and _overlap_area(bj, lg) > 0.9 * bj.width * bj.height
                for lg in legends)
            if inside_same_legend:
                continue
            hits.append((si.replace("\n", " ⏎ ")[:60],
                         sj.replace("\n", " ⏎ ")[:60], round(area, 1), round(frac, 3)))
    return hits


def text_over_legend(fig, min_frac: float = 0.05):
    """Text artists that land on top of a legend frame they do not belong to."""
    items, legends = _boxes(fig)
    hits = []
    for artist, s, bb in items:
        for lg in legends:
            area = _overlap_area(bb, lg)
            if area <= 0:
                continue
            frac = area / (bb.width * bb.height)
            if frac >= min_frac and not (bb.x0 >= lg.x0 and bb.x1 <= lg.x1
                                         and bb.y0 >= lg.y0 and bb.y1 <= lg.y1):
                hits.append((s.replace("\n", " ⏎ ")[:60], round(frac, 3)))
    return hits


def text_over_bars(fig, min_frac: float = 0.12):
    """Text whose box lands on a drawn bar. A value label sitting ABOVE its bar
    is fine; a caption lying across one is not, and eyeballing misses it."""
    items, _ = _boxes(fig)
    fig.canvas.draw()
    renderer = fig.canvas.get_renderer()
    bars = []
    for patch in fig.findobj(Rectangle):
        if not patch.get_visible() or patch.get_height() <= 0:
            continue
        if patch.axes is None or patch.get_width() <= 0:
            continue
        try:
            bb = patch.get_window_extent(renderer=renderer)
        except Exception:  # noqa: BLE001
            continue
        # Skip the axes background AND full-height/width span patches
        # (axvspan/axhspan shading is decoration, not a bar; counting it makes
        # every value label look like a collision).
        ax_bb = patch.axes.get_window_extent(renderer=renderer)
        if bb.height >= 0.9 * ax_bb.height or bb.width >= 0.9 * ax_bb.width:
            continue
        if bb.width > 0 and bb.height > 0:
            bars.append(bb)
    hits = []
    for artist, s, bb in items:
        for bar in bars:
            area = _overlap_area(bb, bar)
            if area <= 0:
                continue
            frac = area / (bb.width * bb.height)
            if frac >= min_frac:
                hits.append((s.replace("\n", " ⏎ ")[:60], round(frac, 3)))
                break
    return hits


def assert_no_overlaps(fig, name: str = "figure", check_bars: bool = True, **kw) -> None:
    hits = find_overlaps(fig, **kw)
    over = text_over_legend(fig)
    bars = text_over_bars(fig) if check_bars else []
    if not hits and not over and not bars:
        print(f"[figcheck] {name}: no text overlaps")
        return
    lines = [f"[figcheck] {name}: {len(hits)} overlapping text pairs, "
             f"{len(over)} text-on-legend, {len(bars)} text-on-bar"]
    for a, b, area, frac in hits:
        lines.append(f"  OVERLAP {frac:>5.1%}  {a!r}  ×  {b!r}")
    for s, frac in over:
        lines.append(f"  ON-LEGEND {frac:>5.1%}  {s!r}")
    for s, frac in bars:
        lines.append(f"  ON-BAR    {frac:>5.1%}  {s!r}")
    raise SystemExit("\n".join(lines))


def install(strict: bool = True, **kw) -> None:
    """Check every figure at savefig time, for the rest of the process.

    One line at the top of a plotting script then covers every figure it
    writes, including ones added later. ``strict=False`` prints findings
    instead of raising, for retrofitting onto a script whose figures you have
    not cleaned up yet.
    """
    from matplotlib.figure import Figure

    if getattr(Figure, "_figcheck_installed", False):
        return
    original = Figure.savefig

    def savefig(self, *args, **kwargs):
        result = original(self, *args, **kwargs)
        name = str(args[0]) if args else kwargs.get("fname", "figure")
        try:
            assert_no_overlaps(self, str(name), **kw)
        except SystemExit as exc:
            if strict:
                raise
            print(exc)
        return result

    Figure.savefig = savefig
    Figure._figcheck_installed = True
