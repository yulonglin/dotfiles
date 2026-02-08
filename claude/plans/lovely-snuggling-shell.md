# Plan: Fix OG meta tag to use generated image

## Context

The OG link preview shows the old Gatsby screenshot because `BaseLayout.astro` imports `src/assets/og.png` (a 250KB static file that still exists) instead of the satori-generated `/og.png` endpoint.

## Changes

### 1. Delete old static OG image
- `trash src/assets/og.png` (250KB old Gatsby screenshot)

### 2. Update `src/layouts/BaseLayout.astro`
- **Remove** `import ogSrc from '@/assets/og.png';`
- **Remove** `import { getImage } from 'astro:assets';`
- **Remove** `const optimizedOg = await getImage({ src: ogSrc, format: 'png', width: 1200 });`
- **Change** default `ogImage` from `optimizedOg.src` to `'/og.png'`

Result: `<meta property="og:image">` resolves to `https://yulonglin.com/og.png` (satori-generated).

## Verification

1. `bun run build` succeeds
2. `dist/og.png` exists and shows tricolor card
3. `grep 'og:image' dist/index.html` shows `/og.png` URL
4. Commit, push, wait for Netlify deploy, then test with a link preview tool
