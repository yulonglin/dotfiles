# Plan: Self-Host LXGW WenKai Font + Fix Reading Speed

## Context

The Chinese font (LXGW WenKai) isn't rendering because Google Fonts returns **400: Font family not found** for `LXGW+WenKai`. The user sees system KaiTi fallback instead. Self-hosting solves this and eliminates the external dependency.

**Critical discovery from 4-agent review**: `@fontsource/lxgw-wenkai` ships **Latin subset only** (confirmed via metadata: `"subsets": ["latin"]"`). It has zero CJK glyphs and would not render any Chinese text. The correct package is `lxgw-wenkai-webfont` by chawyehsu, which provides 116 unicode-range subsets with full CJK coverage.

---

## 1. Install `lxgw-wenkai-webfont` via bun

```bash
bun add lxgw-wenkai-webfont
```

This package provides:
- 116 woff2 subset files per weight with `unicode-range` declarations
- Full CJK Unified Ideographs coverage (U+4E00-U+9FFF and beyond)
- `font-display: swap` built in
- Browser only downloads subsets needed for characters on the page (~200-500KB typical)
- Declares `font-family: 'LXGW WenKai'` — matches our existing `--font-chinese` variable

### Files
- `package.json` — new dependency
- `bun.lockb` — updated

## 2. Import webfont CSS in global.css

In `src/styles/global.css`, add before `@import "tailwindcss"`:
```css
@import "lxgw-wenkai-webfont/style.css";
```

This registers ~116 `@font-face` declarations with `unicode-range`. The CSS is a few KB; actual woff2 files only download when the browser encounters matching CJK characters. Pages without Chinese text pay zero font-file cost.

Vite processes the import at build time — woff2 files get hashed and placed in `dist/_astro/`, served from Netlify CDN.

### Files
- `src/styles/global.css` — add webfont import

## 3. Remove Google Fonts CJK `<link>` + `needsCJKFont` prop

In `src/layouts/BaseLayout.astro`:
- Remove the `{needsCJKFont && <link ... LXGW+WenKai ...>}` line (returns 400 anyway)
- Remove `needsCJKFont` from the Props interface and destructuring

In `src/pages/writing/[slug].astro`:
- Remove `needsCJKFont={isBilingual}` from the `<BaseLayout>` call

Rationale: the webfont CSS is now in the global bundle. The `@font-face` declarations are tiny overhead. Font files themselves are lazy-loaded via `unicode-range` — they only download on pages that actually render CJK characters.

### Files
- `src/layouts/BaseLayout.astro` — remove `needsCJKFont` prop and conditional link
- `src/pages/writing/[slug].astro` — remove `needsCJKFont={isBilingual}`

## 4. Verify `font-family` name matches

After install, check that the package declares `font-family: 'LXGW WenKai'`:
```bash
grep "font-family" node_modules/lxgw-wenkai-webfont/style.css | head -3
```

This must match `--font-chinese: 'LXGW WenKai', 'STKaiti', 'KaiTi', serif;` in global.css. If the package uses a different name, update `--font-chinese` to match.

## 5. Update Chinese reading speed

Based on user research: native speakers read 300-430 cpm for leisure. Current rate is 350 cpm (low end). Blog reading is casual/leisure, so **400 cpm** is more representative of the middle.

In `src/pages/writing/[slug].astro`, change:
```typescript
// Chinese reading time: ~400 characters/min (leisure reading, 300-430 cpm range)
zhReadingTime = Math.ceil(zhPlainText.length / 400);
```

### Files
- `src/pages/writing/[slug].astro` — update divisor from 350 to 400

## 6. Add font caching headers (optional)

In `netlify.toml`, add long-lived caching for font files:
```toml
[[headers]]
  for = "/_astro/*.woff2"
  [headers.values]
    Cache-Control = "public, max-age=31536000, immutable"
```

Netlify defaults to `max-age=0, must-revalidate` — this ensures fonts are cached for 1 year since their hashed filenames change on updates.

### Files
- `netlify.toml` — add caching header rule

---

## Implementation Order

1. `bun add lxgw-wenkai-webfont`
2. Verify font-family name in installed CSS
3. Add import to `global.css`
4. Remove Google Fonts CJK link + `needsCJKFont` prop
5. Update reading speed to 400 cpm
6. Add caching headers to `netlify.toml`
7. Build and verify

## Verification

1. `bun run build` — no errors
2. Check `dist/_astro/` for woff2 font files (proves self-hosting works)
3. `bun dev` → navigate to `/writing/ai-guide/` → toggle to Chinese → verify WenKai renders (not system KaiTi)
4. Check non-bilingual pages don't download CJK font files (network tab)
5. Chinese reading time reflects 400 cpm

## Decisions from review

- **Not preloading**: With 116 subsets, we can't predict which ones a page needs. `font-display: swap` gives immediate text with fallback, then swaps in WenKai as subsets arrive.
- **Not self-hosting Latin fonts**: Google Fonts CDN caching benefits outweigh the consistency of same-origin serving for a personal site.
- **Keeping 1.05em bump**: Reasonable for LXGW WenKai + Lora pairing. Verify visually with mixed-language paragraphs.
- **Global import over conditional**: The `@font-face` CSS cost is negligible (~few KB), and the simplification (removing needsCJKFont plumbing) is worth it.
