# Plan: Gatsby Cleanup + Content Extraction

## Context

The Astro migration is complete but ~50 dead Gatsby `.js` files remain in `src/`, React deps are configured but unused, and page content is embedded in `.astro` template markup. This plan cleans up the dead code, extracts editable content into markdown files, and adds pronouns.

---

## Part 1: Delete Dead Gatsby Code

### 1a. Delete 50 dead `.js` files

All React/styled-components/hooks files — none imported by any `.astro` file.

```
src/components/{email,footer,head,index,layout,loader,menu,nav,side,social,ThemeToggle}.js
src/components/sections/{about,contact,featured,hero,jobs,projects,writing}.js
src/components/icons/*.js  (22 files)
src/hooks/*.js  (5 files)
src/styles/*.js  (9 files)
src/utils/*.js  (2 files)
src/context/ThemeContext.js
```

### 1b. Remove empty directories

Delete now-empty dirs: `src/hooks/`, `src/utils/`, `src/context/`, `src/components/icons/`, `src/components/sections/`.

### 1c. Remove unused React dependencies

- `astro.config.mjs` — remove `import react` and `react()` from integrations
- `package.json` — remove `react`, `react-dom`, `@astrojs/react`
- `bun install` to sync lockfile

### 1d. Delete `.cache/`

Gatsby build cache (gitignored, just disk waste).

---

## Part 2: Extract Content to Markdown

Separate editable content from layout templates so pages can be updated by editing markdown, not `.astro` files.

### 2a. Create content collection for site pages

Add to `src/content.config.ts`:
```ts
// "site" collection for editable page content
const site = defineCollection({ ... });
```

### 2b. Homepage content → `src/content/site/home.md`

Frontmatter for structured fields, body for "Currently" bullets:

```md
---
tagline: "AI safety researcher exploring how to build trustworthy AI systems."
subtitle: "Currently at MATS, working with Mary Phuong (DeepMind) on detecting deceptive AI behavior."
badge: "Open to AI safety research roles — H-1B1 visa, no lottery needed"
---

- AI safety research fellow at [MATS](https://www.matsprogram.org/) — detecting deceptive behavior in frontier models via black-box sandbagging detection
- Previously: jailbreak defense research at [CHAI](https://humancompatible.ai) (UC Berkeley) and production LLM systems at ByteDance
- Open to AI safety research roles and fellowships in the Bay Area, London, or Singapore — [H-1B1 visa eligible](/h1b1-visa)
```

Update `src/pages/index.astro` to import from this collection and render the fields.

### 2c. About content → `src/content/site/about.md`

```md
---
intro: "I'm Yulong, an AI safety researcher at MATS, working with Mary Phuong (DeepMind)..."
---

My research sits at the intersection of adversarial robustness...

## Beyond the Lab

Outside of research, I used to write for...
```

Update `src/pages/about.astro` to import and render, splitting on the `## Beyond the Lab` heading.

### 2d. Content schema

Minimal Zod schema in `content.config.ts` — just validate frontmatter fields exist, keep body flexible.

---

## Part 3: Add Pronouns

Add "(he/him)" to homepage hero, subtle text near the name:

```html
<h1>Yulong Lin.</h1>
<p class="text-muted text-sm">(he/him)</p>
```

This goes in `src/pages/index.astro` hero section. Also update JSON-LD if appropriate.

---

## Files to modify

| File | Action |
|------|--------|
| 50 `.js` files | Delete |
| `.cache/` | Delete |
| `astro.config.mjs` | Remove react integration |
| `package.json` | Remove 3 deps |
| `src/content.config.ts` | Add `site` collection schema |
| `src/content/site/home.md` | Create (extracted homepage content) |
| `src/content/site/about.md` | Create (extracted about content) |
| `src/pages/index.astro` | Import from content collection + add pronouns |
| `src/pages/about.astro` | Import from content collection |

## Verification

1. `bun run build` — site builds cleanly
2. `bun dev` — visually verify homepage, about page look identical to before
3. Edit `home.md` text → confirm change appears on dev server
4. `git diff --stat` — ~50 deletions, ~5 file edits, 2 new content files
