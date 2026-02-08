# Content Accuracy Fixes & Homepage Tuning

## Context

The 17-item Post-Migration Polish plan is **complete** — all phases implemented, built (19 pages, 0 errors), and visually verified. During final cross-checking, we found content inaccuracies (hallucinated details, wrong locations), a generic homepage that doesn't use language matching target employers, and a TODO(human) still in the codebase. This plan addresses the remaining fixes.

---

## Changes

### 1. Fix job locations and names (user-confirmed values)

All 9 job files at `src/content/jobs/*.md` — update `location` frontmatter:

| File | Current | Correct location |
|------|---------|-----------------|
| `mats.md` | Berkeley, CA | Berkeley, CA ✓ |
| `chai2.md` | Berkeley, CA | Berkeley, CA ✓ |
| `chai.md` | Boston, MA | **Berkeley, CA** |
| `tiktok.md` | San Jose, CA | **Singapore** (also rename company to "TikTok / ByteDance Seed") |
| `cohere.md` | Cupertino, CA | **London** |
| `aws.md` | Northeastern University | **Cambridge, UK** |
| `cambridge.md` | Cupertino, CA | **Cambridge, UK** |
| `nus.md` | Boston, MA | **Singapore** |
| `astar.md` | Boston, MA | **Singapore** |

Also fix `chai.md` date inconsistency: `date: '2018-05-14'` doesn't match `range: 'June - September 2021'`.

### 2. Update homepage "Currently" bullets to match target employer language

**File**: `src/pages/index.astro` (lines 78-94)

Based on job postings from Anthropic Fellows, GDM Safety, and Apollo Research, these orgs value: deceptive alignment/scheming detection, black-box monitoring, fast empirical research, frontier model experience.

**Current bullets** (generic):
1. "Research scholar at MATS, working on AI safety evaluations"
2. "Writing about adversarial robustness, AI control, and jailbreak defenses"
3. "Open to AI safety research roles — H-1B1 visa eligible"

**Proposed bullets** (specific, using employer language — user requested mentioning "AI safety" and "research fellowship"):
1. "AI safety research fellow at [MATS](link) — detecting deceptive behavior in frontier models via black-box sandbagging detection"
2. "Previously: jailbreak defense research at [CHAI](link) (UC Berkeley) and production LLM systems at ByteDance"
3. "Open to AI safety research roles and fellowships in the Bay Area, London, or Singapore — [H-1B1 visa eligible](link)"

### 3. Sharpen homepage hero subtitle

**File**: `src/pages/index.astro` (lines 45-48)

**Current**: "AI safety researcher exploring how to build trustworthy AI systems. Currently at MATS, working on detecting deceptive AI behavior."

**Proposed**: "AI safety researcher exploring how to build trustworthy AI systems. Currently at MATS, working with Mary Phuong (DeepMind) on detecting deceptive AI behavior."

Keeps the original phrasing but adds the mentor/affiliation signal. Also update "Research scholar" → "Research Fellow" (matches old Gatsby hero.js).

### 4. Update role badge with location preferences

**File**: `src/pages/index.astro` (lines 50-57)

**Current**: "Open to AI safety research roles — H-1B1 visa, no lottery needed"
**Proposed**: "Open to AI safety research roles in the Bay Area, London, or Singapore — H-1B1 visa, no lottery needed"

### 5. Fix about page education line

**File**: `src/pages/about.astro` (line 71)

User confirmed "BA and MEng" is accurate. Revert from "I studied at Cambridge" back to "I did my BA and MEng at Cambridge".

### 6. About page — credibility signals placement (don't overwhelm)

User doesn't want to overload the bio. Instead of cramming GPT-2/RLHF, Chinese AI lab insights, and Scott Emmons into the main bio, keep the bio clean and let the expandable timeline entries + research page carry the depth:

- **GPT-2/RLHF**: Already in `ml-implementations.md` research entry (visible on research page) and expandable under Redwood Research timeline if we add a job entry. **No change to bio.**
- **Chinese AI lab insight**: Already implied by "ByteDance (contributing to Doubao)" in the bio. **No change.**
- **Scott Emmons**: Already in `jailbreak-defenses.md` body text (currently draft:true). When that research is un-drafted, the attribution will be visible on the research page. **No change to bio for now.**

Net: Keep bio as-is (clean, not overwhelming). The depth lives in expandable timeline entries and the research page.

### 7. Beyond the Lab — leave for user to rewrite

**File**: `src/pages/about.astro` (line 91)

User will rewrite this section themselves. **Leave the TODO(human) comment in place** as a reminder. Don't modify this section's content.

### 8. Update H-1B comparison table stats (research complete)

**File**: `src/pages/h1b1-visa.astro` (lines 39-58)

Research agent findings (sourced from USCIS, NFAP, VisaGrader, immigration law firms):

| Stat | Current | Research finding | Action |
|------|---------|-----------------|--------|
| H-1B lottery | ~25% | 25-29% (FY2024-25) | **Keep ~25%** — accurate enough |
| H-1B cost | $100,000+ | $5-10K traditional; $100K+ with Sept 2025 proclamation fee for workers abroad | **Keep $100,000+** — reflects current regime |
| H-1B processing | 6+ months | 3-6 months (Texas 4.5mo, CA/VT 6mo) | **Keep "6+ months"** — Bay Area uses CA Service Center (6mo) |
| H-1B approval | ~85% | ~97% (FY2022-2025) | **Remove row entirely** — approval rate is misleading when the real bottleneck is the lottery |
| H-1B1 approval | 95-100% | Never hit cap (939/5400 used in 2024). Consular ~90-95%, higher on final resolution | **Update to "~100%"** per user |

Changes to table: remove Approval Rate row for H-1B (keep H-1B1 "~100%"). Update Key Advantages bullet (line 71) from "95-100%" → "~100%".

### 9. Fix prose-content scoped CSS bug (paragraphs show 0px margins)

**File**: `src/pages/writing/[slug].astro` (lines 186-320)

**Bug**: All `.prose-content p`, `.prose-content h2`, etc. styles have **zero effect** because Astro's scoped `<style>` adds `data-astro-cid-*` to selectors, but `<Content />` rendered markdown children don't receive that attribute. Computed margins are all 0px.

**Fix**: Change `.prose-content p` → `.prose-content :global(p)` for ALL descendant selectors inside `.prose-content`. This tells Astro not to scope those child selectors.

Affected selectors (all need `:global()` wrapping):
- `.prose-content h2` → `.prose-content :global(h2)`
- `.prose-content h3` → `.prose-content :global(h3)`
- `.prose-content p` → `.prose-content :global(p)`
- `.prose-content a` / `a:hover` → `.prose-content :global(a)` / `:global(a:hover)`
- `.prose-content ul, ol` → `.prose-content :global(ul), .prose-content :global(ol)`
- `.prose-content li` → `.prose-content :global(li)`
- `.prose-content li > ul, li > ol` → `.prose-content :global(li > ul), .prose-content :global(li > ol)`
- `.prose-content blockquote` → `.prose-content :global(blockquote)`
- `.prose-content code` → `.prose-content :global(code)`
- `.prose-content pre` → `.prose-content :global(pre)`
- `.prose-content pre code` → `.prose-content :global(pre code)`
- `.prose-content strong` → `.prose-content :global(strong)`
- `.prose-content em` → `.prose-content :global(em)`
- `.prose-content hr` → `.prose-content :global(hr)`
- `.prose-content figure` / `figure img` / `figcaption` → wrap with `:global()`
- `.prose-content img` → `.prose-content :global(img)`

**Spacing values** (keep current — they're already more generous than Lilian Weng and Anthropic's blog once the bug is fixed):
- p margin-bottom: `1.75rem` (28px) — Weng uses 20px, Anthropic uses 17px
- h2 margin-top: `3rem` (48px) — Weng uses 24px, Anthropic uses 32px
- line-height: `1.8` — between Weng (1.6) and Anthropic (1.7)

### 10. Fix footer message on short pages

**File**: `src/components/Footer.astro`

The "If you've read this far, we should grab coffee" message is awkward on short pages (404, homepage) where the user hasn't "read far" at all.

**Fix**: Remove that specific message from the rotation. Keep the other 3 messages which work regardless of page length:
- "Built with Astro and too much black tea."
- "No LLMs were harmed in the making of this website."
- "Made in Berkeley, CA. Previously: Cambridge, Singapore."

---

## Execution Order

**I can do now (no user input needed):**
1. Fix prose-content scoped CSS bug (`:global()` wrapping) — **this is why paragraphs look crammed**
2. Update homepage: hero subtitle, "Currently" bullets, role badge with locations
3. Fix about page education line ("BA and MEng")
4. Bio: keep as-is (no overwhelming additions)
5. Update H-1B comparison table (remove approval row, H-1B1 → "~100%")
6. Fix footer: remove "if you've read this far" message

**Blocked on user input:**
7. Job locations — user provides correct values for 6 files → I update
8. `chai.md` date fix — user confirms correct date
9. Beyond the Lab — user rewrites in their own voice

**Housekeeping:**
7. Update CLAUDE.md with Astro scoping bug learning + update project overview from Gatsby to Astro
8. Update auto memory (`~/.claude/projects/.../memory/MEMORY.md`)
9. Fix job locations (all 7 files — user confirmed values)

**Blocked on user input:**
10. `chai.md` date fix — user confirms correct date
11. Beyond the Lab — user rewrites in their own voice

**After all input received:**
12. Build + verify + commit

## Files to Modify

| File | Changes |
|------|---------|
| `src/content/jobs/chai.md` | Fix location + date |
| `src/content/jobs/cohere.md` | Fix location |
| `src/content/jobs/aws.md` | Fix location |
| `src/content/jobs/cambridge.md` | Fix location |
| `src/content/jobs/nus.md` | Fix location |
| `src/content/jobs/astar.md` | Fix location |
| `src/pages/index.astro` | Hero text, Currently bullets, role badge |
| `src/pages/about.astro` | Education line |
| `src/pages/h1b1-visa.astro` | Remove approval rate row, H-1B1 → "~100%" |
| `src/pages/writing/[slug].astro` | Fix scoped CSS bug: wrap all `.prose-content` child selectors with `:global()` |
| `src/components/Footer.astro` | Remove "if you've read this far" message |

## Learnings to Record

Add to project CLAUDE.md `## Learnings` section:

- **Astro scoped CSS + `<Content />`**: Astro's `<style>` blocks scope selectors with `data-astro-cid-*` attributes, but markdown rendered via `<Content />` or `<slot />` does NOT receive these attributes. Use `.parent :global(child)` for any styles targeting rendered markdown content. (2026-02-07)
- **Astro `_redirects` portability**: `_redirects` file works on Netlify and Cloudflare Pages but NOT Vercel (needs `vercel.json`). Astro's built-in redirect config generates meta-refresh HTML, not true 301s. (2026-02-07)

Also update the project overview section from Gatsby to Astro (the migration is nearly complete).

## Verification

- `npx astro build && npx pagefind --site dist` — 0 errors
- Visual check: homepage (Currently bullets, role badge with locations), about (bio accuracy, timeline locations), H-1B1 (updated stats), footer (no awkward messages on short pages)
- Both themes (light + dark)
