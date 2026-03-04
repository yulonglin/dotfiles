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
- **Accents**: Clay (`#D97757`) for interactive elements, links, CTAs
- **Borders**: `#E8E6DC` for subtle dividers
- **Minimum spacing**: `0.75rem` container padding, `0.5rem` content-to-edge, `0.5rem` between siblings (per `rules/coding-conventions.md`)

## Comparison Tables

When comparing items (models, products, features), combine multiple indicator types for clarity:
- **Quantitative**: Horizontal bars or numeric scores for concrete metrics
- **Qualitative**: Color-coded labels (e.g., "Excellent" in Olive, "Good" in Sky, "Limited" in Clay) for subjective assessments
- **Visual hierarchy**: Use the PRETTY_CYCLE or secondary colors to distinguish the compared items

Don't rely on just one indicator type — readers benefit from seeing both the number and a quick visual/textual summary.

## Accent Usage

| Element | Color |
|---------|-------|
| Primary buttons, links | Clay `#D97757` |
| Hover states | darken Clay ~10% |
| Info/highlight | Sky `#6A9BCC` |
| Success/positive | Olive `#788C5D` |
| Warning | Clay `#D97757` |
| Cards/sections | Ivory `#FAF9F5` background |
