# Fix Code Review Issues from Astro Migration

## Context

Code review of the `astro-migration` branch found 2 critical, 7 important, and several minor issues. The critical issues affect dark mode badge rendering and a potentially broken image path. The important issues include XSS risk in hand-rolled markdown conversion, build config mismatches, and code duplication.

---

## Fix 1: CRITICAL — `dark:` prefix incompatible with `data-theme` theming

**Problem:** `dark:` Tailwind classes in badge components use `@media (prefers-color-scheme)` but the site uses `[data-theme="dark"]` attribute switching.

**Fix:** Add one line to `src/styles/global.css` — Tailwind v4's `@custom-variant` directive:

```css
@custom-variant dark (&:where([data-theme=dark], [data-theme=dark] *));
```

This makes ALL `dark:` utility classes respond to the `data-theme` attribute instead of the media query. No component changes needed.

**Files:** `src/styles/global.css` (add after `@import "tailwindcss"`)

**Also:** Update the misleading comment at line ~173 that mentions `dark:` variant support — it's now actually correct with this fix.

---

## Fix 2: CRITICAL — Relative image path in adversarial-defenses.md

**Problem:** `<img src="./defense-gan.png">` may not resolve in built output.

**Fix:** Change to absolute path: `src="/writing/adversarial-defenses/defense-gan.png"` (file exists in `public/`).

**Files:** `src/content/writing/adversarial-defenses.md` (line 26)

**Cleanup:** Remove the duplicate at `src/content/writing/defense-gan.png` since the canonical copy is in `public/`.

---

## Fix 3: IMPORTANT — URL scheme validation in `set:html` regex

**Problem:** Hand-rolled markdown→HTML regex in 4 files doesn't filter `javascript:` URLs.

**Fix:** Create a shared helper function and use it everywhere. **Request human input** on the URL validation logic (meaningful security design decision).

**Files:**
- `src/pages/index.astro` (lines 18-21, 30)
- `src/pages/about.astro` (lines 16-19, 34-35, 55)
- `src/components/ResearchCluster.astro` (lines 57-60)

**Approach:** Add a `safeHref()` filter inside the regex replacement that rejects non-safe URL schemes.

---

## Fix 4: IMPORTANT — Build config fixes

**4a: netlify.toml** — Change `npm run build` → keep as-is or update to bun (need to verify Netlify bun support). Safest: keep npm since it works and Netlify may not have bun pre-installed.

**4b: .gitignore** — Remove `bun.lock` from `.gitignore` so the lockfile is tracked for reproducible builds.

**Files:** `netlify.toml`, `.gitignore`

---

## Fix 5: IMPORTANT — Extract duplicated SVG icons in Nav

**Problem:** Social icon SVGs (GitHub, Twitter, LinkedIn, Calendar) duplicated between desktop nav (lines 33-57) and mobile menu (lines 89-112).

**Fix:** Extract icon rendering into a reusable Astro snippet or define the icons array once and map over it in both locations.

**Files:** `src/components/Nav.astro`

---

## Fix 6: IMPORTANT — Consolidate tag-pill CSS

**Problem:** `.tag-pill` and `.tag-pill-sm` defined in 3 separate scoped style blocks with slight inconsistencies.

**Fix:** Move both to `src/styles/global.css` as `@utility` definitions. Standardize the properties.

**Files:**
- `src/styles/global.css` (add utilities)
- `src/pages/writing/index.astro` (remove scoped styles)
- `src/pages/writing/[slug].astro` (remove scoped styles)
- `src/pages/writing/tags/[tag].astro` (remove scoped styles)

---

## Fix 7: Minor cleanups + canary string per-post flag

- **Footer.astro** line 21: Change comment from "deterministic per build" to "random per build — same across all pages within a single build"
- **Canary string** — instead of removing, make it per-post:
  1. Keep `canaryString` in `src/config.ts`
  2. Add `canary: z.boolean().optional().default(false)` to the writing schema in `src/content.config.ts`
  3. In `src/pages/writing/[slug].astro`, conditionally render the canary string as a visually-hidden element when `post.data.canary === true`
  4. User can then flag sensitive posts with `canary: true` in frontmatter

---

## Implementation Strategy: Agent Teams

These fixes are largely independent (different files), making them ideal for parallel agent work. One constraint: Fix 6 (tag-pill) and Fix 1 (dark variant) both touch `global.css`, so they must be sequential.

### Phase 1: Leader does sequential `global.css` edits + quick fixes (me)
- Fix 1: Add `@custom-variant dark` to `global.css`
- Fix 6: Add `tag-pill` utilities to `global.css`
- Fix 7: Footer comment + canary string schema/rendering setup

### Phase 2: Dispatch parallel agents (3 agents)
- **Agent A** — Fix 2 (image path) + Fix 4 (netlify.toml + .gitignore)
- **Agent B** — Fix 5 (Nav SVG dedup) + remove scoped tag-pill CSS from 3 writing pages (after Fix 6 adds them to global.css)
- **Agent C** — Fix 3 (URL validation helper — prep the TODO(human) for Learn by Doing)

### Phase 3: Human contribution
- User implements URL validation logic (Learn by Doing)

### Phase 4: Verification + commit
1. `bun run build` — no build errors
2. `bun dev` — visually verify dark mode badges, image, nav icons, tag pills
3. Commit all changes
