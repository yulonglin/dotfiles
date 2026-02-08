# Plan: Fix OG image + clean up asset organization

## Context

OG link previews show the old Gatsby screenshot because `BaseLayout.astro` imports `src/assets/og.png` (a stale static file) instead of the satori-generated `/og.png` endpoint. Additionally, assets are scattered with duplicates across `src/assets/` and `public/`.

## Changes

### 1. Fix OG meta tag (`src/layouts/BaseLayout.astro`)
- Remove `import ogSrc from '@/assets/og.png'`
- Remove `import { getImage } from 'astro:assets'`
- Remove `const optimizedOg = await getImage({ src: ogSrc, ... })`
- Change default `ogImage` from `optimizedOg.src` to `'/og.png'`

### 2. Delete stale/duplicate files
- `src/assets/og.png` — old Gatsby screenshot (replaced by satori endpoint)
- `public/images/og.png` — another old OG image
- `public/images/me.jpg` — duplicate of `src/assets/me.jpg`
- `public/favicon-32x32.png` + `public/favicon.ico` — duplicates of files in `public/favicons/`

### 3. Resulting asset layout

```
src/assets/              ← Astro-processed (import-able, optimized)
  me.jpg                 ← profile photo (used in index, about, og.ts)
  fonts/                 ← static TTFs for satori OG generation
    CrimsonPro-Bold.ttf
    JetBrainsMono-Regular.ttf
    Lora-Regular.ttf

public/                  ← served as-is (no processing)
  favicons/              ← all favicon variants
  fonts/                 ← WOFF2 variable fonts for web @font-face
  papers/                ← research PDFs
  slides/                ← talk slides
  resume.pdf
  writing/               ← blog post images (per-slug subdirectories)
    adversarial-defenses/
      defense-gan.png
```

OG image generated at build time by `src/pages/og.png.ts` → served at `/og.png`.

## Verification

1. `bun run build` succeeds (no broken imports)
2. `dist/og.png` exists and shows tricolor card
3. `grep 'og:image' dist/index.html` → contains `/og.png`
4. No broken image references on any page (`bun dev` and check index, about)
5. Commit, push, confirm Netlify build succeeds
