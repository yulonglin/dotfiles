# Visual Layout Quality Reference

On-demand reference for visual output quality. Loaded by skills, not auto-loaded.

## Cross-Domain Principles

1. **Use layout systems, not manual coordinates** — flexbox/grid (CSS), positioning library (TikZ), CSS Grid (Slidev)
2. **Container padding, not per-child padding** — `> :not(x)` selectors break with varying DOM structures
3. **No negative margins for spacing** — use gap/node distance instead
4. **Verify rendered output** — screenshots (Playwright), compiled PDF, browser preview

## Domain-Specific Guidance

| Domain | Primary guide | Gap-filling guidance |
|--------|--------------|---------------------|
| **HTML/CSS** | ui-ux-pro-max plugin (Layout & Spacing, Pre-Delivery Checklist) | This doc (safety net when ui-ux-pro-max not loaded) |
| **TikZ** | viz → tikz-diagrams (Spacing Quick Reference, Arrow Routing Rules) | — |
| **Slidev** | writing → fix-slide | — |
| **matplotlib** | `docs/petri-plotting.md`, anthropic.mplstyle | — |

## CSS Spacing Safety Net

These rules apply ALWAYS, even when frontend-design encourages "overlap" and "asymmetry." Intentional overlap means z-index layering with visual breathing room — NOT content touching container edges.

### Hard Rules

1. **Every content container must have padding** — minimum `p-2`/`0.5rem`/`8px`. No exceptions
2. **Text must never touch its container edge** — if text is inside a box/card/section, there must be padding
3. **Siblings need gap** — use `gap-2`/`0.5rem` minimum between adjacent elements (flex/grid gap, not margin hacks)
4. **Full-bleed elements get negative margin, not zero-padding parents** — if a child needs to touch edges, use negative margin on that child, not remove padding from parent

### Minimum Spacing (hard floor — never go below)

| Domain | Container padding | Content-to-edge gap | Between sibling elements |
|--------|------------------|--------------------|-----------------------|
| **HTML/CSS** | `p-3` / `0.75rem` / `12px` | `p-2` / `0.5rem` / `8px` | `gap-2` / `0.5rem` |
| **TikZ** | `inner sep>=10pt` | `inner sep>=8pt` | `node distance>=1.5cm` |
| **Slidev** | `p-4` / `1rem` on slide content | `p-2` on nested elements | `gap-3` / `0.75rem` |

### Anti-Patterns (with fixes)

```css
/* BAD — per-child padding (breaks with markdown content) */
details > :not(summary) { padding: 0 1.25rem; }
/* GOOD — container padding */
details { padding: 0 1.25rem; }
details > summary { margin: 0 -1.25rem; padding: 0 1.25rem; }

/* BAD — no padding on content card */
.card { border: 1px solid; border-radius: 0.5rem; }
/* GOOD — content has breathing room */
.card { border: 1px solid; border-radius: 0.5rem; padding: 1rem; }

/* BAD — fixed heights causing overflow */
.container { height: 200px; overflow: hidden; }
/* GOOD — min-height or auto with padding */
.container { min-height: 200px; padding: 1rem; }

/* BAD — absolute positioning without container padding */
.parent { position: relative; }
.child { position: absolute; top: 0; left: 0; }
/* GOOD — offset from edges */
.parent { position: relative; padding: 0.5rem; }
.child { position: absolute; top: 0.5rem; left: 0.5rem; }
```

## Chart Annotations (matplotlib, TikZ, Plotly, vega)

### Hard Rule: arrows must anchor to what they reference

An arrow that floats from text-in-empty-space toward a single data element is hard to parse — the reader has to guess what the arrow is *from*. **Both endpoints of an arrow should land on a meaningful chart element** (bar, point, line, region edge), not in blank space.

| Annotation type | Anchoring rule |
|----------------|----------------|
| **Single-element callout** ("this point is interesting") | One arrow, head on the element, tail on label text. Label sits in nearby empty space. |
| **Two-element comparison** ("gap between A and B", "improvement from X to Y") | One arrow with **both** endpoints on the elements (head on one bar/point, tail on the other). Label beside the curve. Or use a bracket spanning the two with a label. |
| **Region annotation** ("this band is the safe zone") | Anchor to region edges via `axvspan`/`axhspan` + edge labels, not floating text + arrow into the region. |

**Why:** the trajectory of the arrow itself communicates the relationship. If only one end is anchored, the reader sees "label points at X" but loses the *what it's compared to*. Anchoring both ends makes the comparison the visual subject.

**matplotlib pattern (two-bar gap):**
```python
from matplotlib.patches import FancyArrowPatch

# Anchor head at bar A top, tail at bar B top
arrow = FancyArrowPatch(
    (a_x, a_top_y), (b_x, b_top_y),
    arrowstyle="-|>", mutation_scale=18,
    color=ACCENT, linewidth=1.8,
    connectionstyle="arc3,rad=0.40",  # bow into empty space
    shrinkA=4, shrinkB=4,
)
ax.add_patch(arrow)
# Label sits beside the curve, in the bow's empty side
ax.text(midpoint_x, midpoint_y, "+51 pp gap",
        color=ACCENT, fontweight="bold")
```

**Anti-pattern (DO NOT do this):**
```python
# BAD — text floats high in empty space, only one anchor
ax.annotate("+51 pp gap",
            xy=(b_x, b_top_y),         # only B anchored
            xytext=(b_x, 78),          # tail floats in sky
            arrowprops=dict(arrowstyle="->"))
```

**Choosing the bow direction:** `connectionstyle="arc3,rad=±N"` bows the arc perpendicular to the head→tail direction. Pick the sign that bows *into empty chart space* (away from other bars/points/labels), then place the label inside the bow. Verify visually — `rad` sign behaviour depends on endpoint order.

### Hard Rule: annotations live in empty space, never on top of data

**Find the largest contiguous empty region in the chart and put the label there.** Don't drop labels, arrow tails, or callouts on top of bars, points, lines, or other annotations — even if the overlap is "only a little." Visual hierarchy collapses when annotations and data fight for the same pixels.

**Inventory empty space before placing:**
1. Above the tallest bar/point (chart ylim usually leaves headroom)
2. Between groups (gap regions in grouped bar charts)
3. In a corner the data doesn't reach
4. Outside the axes entirely (figure-level text, gutter labels)

**For two-element gap annotations**, the cleanest pattern is usually:

```python
# Label sits HIGH in empty space above; two arrows fan out, both anchored on bars
label_x, label_y = (a_x + b_x) / 2, ymax * 0.92  # well above tallest bar
ax.annotate("", xy=(a_x, a_top), xytext=(label_x - dx, label_y - dy),
            arrowprops=dict(arrowstyle="-|>", color=ACCENT,
                            connectionstyle="arc3,rad=0.25"))   # bow outward
ax.annotate("", xy=(b_x, b_top), xytext=(label_x + dx, label_y - dy),
            arrowprops=dict(arrowstyle="-|>", color=ACCENT,
                            connectionstyle="arc3,rad=-0.25"))  # bow outward
ax.text(label_x, label_y, "+51 pp gap",
        ha="center", va="bottom", color=ACCENT, fontweight="bold")
```

This puts both arrowheads on the data (anchored), bends the curves outward into empty space (don't overlap data), and parks the label in the largest empty zone (top of chart). The two arrows fan out from the label so it visibly *labels both sides of the comparison*.

**Anti-pattern (DO NOT do this):**
```python
# BAD — label collides with neighbouring bar; arrow curves through bar territory
ax.text(group_idx + 0.42, mid_y, "+51 pp gap")  # overflows into next group
```

If after one iteration the label still overlaps something, **don't nudge by 0.05** — re-pick the empty region. Nudging hides the problem; the next data update will re-create the collision.

### Pre-Ship Spacing Check (when ui-ux-pro-max not loaded)

Before declaring CSS work complete, verify:
- [ ] No text touching container edges (inspect with browser dev tools)
- [ ] All cards/sections have visible padding
- [ ] Sibling elements have consistent gaps (not zero)
- [ ] Layout survives 20% longer text content
- [ ] Mobile viewport doesn't clip or overflow
