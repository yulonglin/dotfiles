# Plan: Restyle Status Badges — Solid Light Mode, Subtle Dark Mode

## Context

The "Under Review" badge is nearly invisible on the site's warm `#faf9f5` / `#e8e6dc` backgrounds. After several iterations with translucent tints, we landed on solid `--accent` fill which works but doesn't differentiate badge types. The user wants:

- **Light mode**: Solid colored backgrounds with white text (high visibility)
- **Dark mode**: Keep the original subtle translucent style (colored text on faint tinted bg)

## Badge Color Mapping (Light Mode)

| Badge | Background | Text |
|-------|-----------|------|
| Under Review | `bg-amber-500` (#f59e0b) | `text-white` |
| Preprint | `bg-blue-500` (#3b82f6) | `text-white` |
| Ongoing | `bg-[var(--accent)]` (#d97757) | `text-white` |

## Badge Styling (Dark Mode — preserve original subtle look)

| Badge | Background | Text |
|-------|-----------|------|
| Under Review | `bg-amber-400/15` | `text-amber-400` |
| Preprint | `bg-blue-500/15` | `text-blue-400` |
| Ongoing | `bg-[var(--accent)]/15` | `text-accent` |

## Files to Modify

1. **`src/components/ResearchCluster.astro`** (lines 135–149) — all 3 badge types
2. **`src/components/FeaturedCard.astro`** (lines 21–33) — all 3 badge types

## Changes

### ResearchCluster.astro

**Under Review** (line 136):
```
bg-amber-500 text-white dark:bg-amber-400/15 dark:text-amber-400
```

**Preprint** (line 141):
```
bg-blue-500 text-white dark:bg-blue-500/15 dark:text-blue-400
```

**Ongoing** (line 146):
```
bg-[var(--accent)] text-white dark:bg-[var(--accent)]/15 dark:text-accent
```

### FeaturedCard.astro

Same color scheme applied to the equivalent badge spans (lines 22, 26, 30).

## Verification

1. Run `bun dev` and check `/research` page in light mode — badges should be solid colored pills with white text
2. Toggle to dark mode — badges should revert to subtle translucent tints with colored text
3. Check homepage Featured Work card — same behavior
4. Verify all 3 badge types if possible (under-review, preprint, ongoing)
