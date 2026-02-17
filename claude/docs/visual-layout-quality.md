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

### Pre-Ship Spacing Check (when ui-ux-pro-max not loaded)

Before declaring CSS work complete, verify:
- [ ] No text touching container edges (inspect with browser dev tools)
- [ ] All cards/sections have visible padding
- [ ] Sibling elements have consistent gaps (not zero)
- [ ] Layout survives 20% longer text content
- [ ] Mobile viewport doesn't clip or overflow
