# Anthropic Web/CSS Style

## Colors

Use CSS custom properties for consistency:

```css
:root {
  /* Primary */
  --slate: #141413;
  --ivory: #FAF9F5;
  --clay: #D97757;

  /* Secondary */
  --sky: #6A9BCC;
  --olive: #788C5D;
  --fig: #C46686;
  --cactus: #BCD1CA;
  --oat: #E3DACC;

  /* Text-tier accents — AA-compliant (≥4.5:1) as text on Ivory/white.
     Brand accents above fail AA as text on light backgrounds (Clay 2.96:1,
     Sky 2.78:1, Olive 3.49:1) — use these for links, labels, and any text
     <24px in light contexts. Keep brand values for fills/borders/large display
     and for text on dark Slate (where they already pass). See colors.md. */
  --clay-text: #BE4F2B;   /* 4.59:1 on Ivory */
  --sky-text: #3C75AE;    /* 4.58:1 on Ivory */
  --olive-text: #66774F;  /* 4.62:1 on Ivory */

  /* Neutrals */
  --gray-700: #3D3D3A;
  --gray-400: #B0AEA5;
  --gray-200: #E8E6DC;
}
```

## Typography

```css
body {
  font-family: "Styrene B LC", "Helvetica Neue", Helvetica, Arial, sans-serif;
  color: var(--slate);
  font-size: 16px;
  line-height: 1.5;
}

h1, h2, h3 {
  font-family: "Styrene B LC", "Helvetica Neue", Helvetica, Arial, sans-serif;
  font-weight: 600;
}
```

For long-form text (blog posts, documentation), use serif:
```css
.prose {
  font-family: "Tiempos Text", Georgia, serif;
}
```

## Layout Principles

- **Backgrounds**: White (`#FFFFFF`) for content areas, Ivory (`#FAF9F5`) for page-level or card backgrounds
- **Text**: Slate (`#141413`) for primary, `#3D3D3A` for secondary
- **Accents**: brand Clay (`#D97757`) for decorative fills/borders; for link *text* and CTA labels on light backgrounds use `--clay-text` (`#BE4F2B`) — brand Clay fails AA as text (see Accent Usage below)
- **Borders**: `#E8E6DC` for subtle dividers
- **Minimum spacing**: `0.75rem` container padding, `0.5rem` content-to-edge, `0.5rem` between siblings (per `rules/coding-conventions.md`)

## Comparison Tables

When comparing items (models, products, features), combine multiple indicator types for clarity:
- **Quantitative**: Horizontal bars or numeric scores for concrete metrics
- **Qualitative**: Color-coded labels (e.g., "Excellent" in `--olive-text`, "Good" in `--sky-text`, "Limited" in `--clay-text`) for subjective assessments — use the text-tier variants since these are small text on a light background
- **Visual hierarchy**: Use the PRETTY_CYCLE or secondary colors to distinguish the compared items

Don't rely on just one indicator type — readers benefit from seeing both the number and a quick visual/textual summary.

## Accent Usage

Two tiers: **brand** hexes for decorative use (fills, borders, large display, anything on dark Slate), **text-tier** hexes for text <24px on light (Ivory/white) backgrounds. The brand accents fail WCAG AA as light-background text, so don't color small text with them.

| Element | Light-background text/link | Decorative fill / on dark Slate |
|---------|----------------------------|---------------------------------|
| Primary buttons (solid fill, white label) | white label on Clay `#D97757` fill | Clay `#D97757` |
| Text links, ghost-button labels | `--clay-text` `#BE4F2B` | brand Clay on Slate is fine |
| Hover states | darken text-tier ~10% | darken Clay ~10% |
| Info/highlight text | `--sky-text` `#3C75AE` | Sky `#6A9BCC` |
| Success/positive text | `--olive-text` `#66774F` | Olive `#788C5D` |
| Warning text | `--clay-text` `#BE4F2B` | Clay `#D97757` |
| Cards/sections | — | Ivory `#FAF9F5` background |

A filled button (white text on a solid Clay fill) is fine — the fill is decorative and the white label carries the contrast. The trap is brand-accent-colored *text* on Ivory: use the text-tier variant. See `references/colors.md` for the full contrast table.
