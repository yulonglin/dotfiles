# Visual Variables — Picking the Right Encoding

The skill's rules clean charts. Bertin's framework picks the *right encoding in the first place* — which visual variable maps to which kind of data.

## The variables

**Planar (position on the page):**
- `x` and `y` — the most powerful encoding, quantitative for any data type

**Retinal (properties of a mark at a position):**
- **Size** — length, area
- **Value** — lightness/darkness
- **Texture (grain)** — density of sub-marks within a mark
- **Hue** — categorical color
- **Orientation** — rotation
- **Shape** — form (circle, square, glyph)

> Conventional count is "7 visual variables" if you treat position as one. Strict count is 8 (x, y, + 6 retinal). Citation convention, not a real disagreement.

## What each variable can do

| Variable | Selective | Associative | Ordered | Quantitative |
|----------|-----------|-------------|---------|--------------|
| Position | ✓ | — | ✓ | ✓ |
| Size | ✓ | — | ✓ | ✓ (length > area) |
| Value | ✓ | — | ✓ | partial |
| Hue | ✓ | ✓ | — | — |
| Texture | — | ✓ | ✓ | — |
| Orientation | — | ✓ | — | — |
| Shape | — | ✓ | — | — |

- **Selective** — reader can isolate one value at a glance
- **Associative** — reader can mentally group all marks sharing the value
- **Ordered** — clear perceptual ordering (more/less, lighter/darker)
- **Quantitative** — differences are perceived proportionally

**The crucial result:** only position and size are quantitative. Length encodes proportion most reliably; area is underread; angle and color are not quantitative at all.

## Encoding → data type table

| Data | Use | Why |
|------|-----|-----|
| One quantity over time | Position (line) | Quantitative |
| One quantity across categories | Length (bar) | Quantitative; bars beat dots for precision |
| Two quantities | Position × position (scatter) | Both axes quantitative |
| Categorical groups within a scatter | Shape + color | Shape groups (associative); color as accessibility backup |
| Ordered categorical (low/med/high) | Value (lightness ramp) | Value is ordered; hue is not |
| Geographic | Position is given; encode others on retinal | The plane is taken |
| Networks | Layout-position + size for node weight | — |

## Common red flags

- **Rainbow palettes for ordinal data** — hue isn't ordered. Use a sequential value ramp.
- **Pie charts for ranking** — encodes via angle and area, both poorly perceived. Use bars.
- **Bubble charts where area = magnitude** — area is underread. Use length, unless bubbles overlay a map (where position is taken).
- **Color as sole encoding** — kills accessibility, dark mode, and print. Always pair with shape or label.

## Why this matters here

The skill's rule 8 ("gray first, highlight selectively") works *because* hue is selective while gray is associative — your eye groups all gray series and isolates the colored one. The rule isn't an aesthetic preference; it's an exploitation of how retinal variables behave.

The deeper claim: **picking the right variable for the data type prevents most chart bugs at the source**. No amount of styling rescues a chart whose encoding was wrong.
