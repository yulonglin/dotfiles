# Plan: Smart Quotes + Heading Font Toggle

## Context

Two typography improvements for the portfolio site:

1. **Smart quotes in titles**: Frontmatter values bypass Astro's `remark-smartypants`, so post titles render with straight ASCII quotes (`"..."`, `'`) instead of typographic curly quotes (`"..."`, `'`). The markdown body already gets smart quotes automatically — this only affects frontmatter-sourced strings like `post.data.title`.

2. **Heading font toggle**: Add a config flag to swap heading font between Crimson Pro (current, classical serif) and Inter (modern sans-serif). Default stays Crimson Pro. Currently, heading font is declared in two inconsistent ways — the Tailwind `font-heading` utility uses the `--font-heading` CSS custom property, but `global.css` and `[slug].astro` hardcode `'Crimson Pro'` directly. Unifying these through the custom property is a prerequisite for the toggle.

---

## Step 1: Create `src/utils/smartquotes.ts`

Simple regex-based function (no new dependencies — `remark-smartypants` operates on ASTs, not strings):

```typescript
/**
 * Convert straight quotes to typographic curly quotes.
 * Handles double quotes, single quotes/apostrophes, and common punctuation.
 */
export function smartQuotes(text: string): string {
  return text
    // Double quotes: opening after whitespace/start, closing before whitespace/end/punctuation
    .replace(/(^|[\s(])"/g, '$1\u201C')  // opening "
    .replace(/"/g, '\u201D')              // closing "
    // Apostrophes in contractions (before the remaining single quotes)
    .replace(/(\w)'(\w)/g, '$1\u2019$2') // isn't, don't, etc.
    // Single quotes
    .replace(/(^|[\s(])'/g, '$1\u2018')  // opening '
    .replace(/'/g, '\u2019');             // closing '
}
```

## Step 2: Apply `smartQuotes()` to visible title renderings

Import and wrap `post.data.title` in these **visible/rendered** locations only (NOT metadata/SEO):

| File | Line(s) | What |
|------|---------|------|
| `src/pages/writing/index.astro` | 89 | Post listing link text |
| `src/pages/writing/[slug].astro` | 73, 81 | Post h1 (bilingual + regular) |
| `src/pages/writing/[slug].astro` | 166 | Prev/next nav title |
| `src/pages/writing/tags/[tag].astro` | 50 | Tag listing link text |

**Do NOT apply to** (machines consume these, curly quotes could cause issues):
- `BaseLayout title` prop (line 48) — becomes `<title>` and OG/Twitter meta tags
- JSON-LD `headline` (line 56)
- RSS feed titles (`rss.xml.ts:15`)
- Search `data-search` attribute (`index.astro:69`)

Each file needs: `import { smartQuotes } from '@/utils/smartquotes';` in the frontmatter, then `{smartQuotes(post.data.title)}` in the template.

## Step 3: Unify heading font references through `--font-heading`

Change hardcoded `'Crimson Pro'` font-family declarations to use `var(--font-heading)`:

| File | Line | Current | Change to |
|------|------|---------|-----------|
| `src/styles/global.css` | 110 | `font-family: 'Crimson Pro', Georgia, serif;` | `font-family: var(--font-heading);` |
| `src/pages/writing/[slug].astro` | 250 | `font-family: 'Crimson Pro', Georgia, serif;` | `font-family: var(--font-heading);` |
| `src/pages/writing/[slug].astro` | 260 | `font-family: 'Crimson Pro', Georgia, serif;` | `font-family: var(--font-heading);` |
| `src/pages/writing/[slug].astro` | 394 | `font-family: 'Crimson Pro', Georgia, serif;` | `font-family: var(--font-heading);` |

Also update the comment on line 108 of `global.css`: `/* Headings use Crimson Pro */` → `/* Headings use heading font */`

After this step, ALL heading font references flow through `--font-heading`.

## Step 4: Add heading font config flag

In `src/config.ts`, add to `siteConfig`:

```typescript
/** Heading font: 'crimson-pro' (classical serif) or 'inter' (modern sans) */
headingFont: 'crimson-pro' as 'crimson-pro' | 'inter',
```

## Step 5: Wire config to CSS custom property in BaseLayout

In `src/layouts/BaseLayout.astro`:

1. Read `siteConfig.headingFont`
2. If `'inter'`: set inline style on `<html>` to override `--font-heading`, and conditionally include the Inter Google Fonts import

```astro
---
const useInter = siteConfig.headingFont === 'inter';
const interFontUrl = 'https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap';
---
<html lang="en" style={useInter ? "--font-heading: 'Inter', system-ui, sans-serif" : undefined}>
<head>
  ...
  {useInter && <link rel="stylesheet" href={interFontUrl} />}
  ...
```

Inline styles on `<html>` override the `@theme`-generated `:root` custom property (inline > any selector specificity). When `headingFont` is `'crimson-pro'` (default), no inline style is set, and the `@theme` value applies normally.

---

## Files Modified

| File | Changes |
|------|---------|
| `src/utils/smartquotes.ts` | **New** — `smartQuotes()` function |
| `src/config.ts` | Add `headingFont` to `siteConfig` |
| `src/styles/global.css` | Line 110: use `var(--font-heading)` instead of hardcoded font |
| `src/layouts/BaseLayout.astro` | Conditional Inter font import + inline style override on `<html>` |
| `src/pages/writing/index.astro` | Import + apply `smartQuotes()` to title |
| `src/pages/writing/[slug].astro` | Import + apply `smartQuotes()` to titles; unify 3 hardcoded font-family |
| `src/pages/writing/tags/[tag].astro` | Import + apply `smartQuotes()` to title |

## Verification

1. `bun run build` — clean build with no errors
2. `bun dev` — visual check:
   - Navigate to `/writing` — "Sandbagging Isn't "Solved"" should show curly quotes
   - Navigate to `/writing/sandbagging` — h1 should show curly quotes, prev/next nav too
   - All headings should still use Crimson Pro (default config)
3. Flip `headingFont: 'inter'` in config → `bun dev` again:
   - All headings should switch to Inter
   - Body text should remain Lora
   - Code should remain JetBrains Mono
4. Flip back to `'crimson-pro'` → confirm it reverts cleanly
