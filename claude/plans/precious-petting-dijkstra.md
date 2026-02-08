# Lowercase Page Titles & Nav

## Context

The site's tone is already warm and conversational (greeting, humorous footer, sentence-case prose), but the Title Case `<h1>` headings and nav links feel slightly formal by comparison. Lowercasing these elements brings the typography in line with the voice.

Design principle: **lowercase for identity/navigation, capitalized for action/function.**

## Changes

### 1. Nav links — lowercase in config (`src/config.ts`)

```
Research → research
Writing  → writing
About    → about
```

CV stays uppercase (it's an acronym).

### 2. Page `<h1>` titles — lowercase in templates

| File | Before | After |
|------|--------|-------|
| `src/pages/research.astro:31` | `Research` | `research` |
| `src/pages/writing/index.astro:16` | `Writing` | `writing` |
| `src/pages/about.astro:84` | `About` | `about` |

### 3. `<title>` / SEO metadata — keep capitalized

The `title` prop passed to `BaseLayout` stays `"Research"`, `"Writing"`, `"About"` — browser tabs and search results follow standard capitalization conventions.

### What stays as-is

- **Homepage hero** (`Yulong Lin.`) — proper noun, already perfect
- **Section headings** (`Featured Work`, cluster titles like `Alignment & Control`) — functional labels within pages
- **Monospace labels** (`CURRENTLY`, `EXPERIENCE`, `BEYOND THE LAB`, `BROWSE BY TOPIC`) — separate typographic register, uppercase is intentional
- **CTA buttons** (`Get in Touch`, `Read My Writing`) — capitalization adds authority
- **Status badges** (`UNDER REVIEW`, `PREPRINT`) — technical labels
- **Footer social links** — these are proper nouns (Twitter, GitHub, LinkedIn)

## Files to edit

1. `src/config.ts` — navLinks names (3 strings)
2. `src/pages/research.astro` — h1 text
3. `src/pages/writing/index.astro` — h1 text
4. `src/pages/about.astro` — h1 text

## Verification

1. `bun dev` — check all pages visually
2. Verify nav links show lowercase on desktop and mobile menu
3. Verify browser tab titles remain capitalized
4. Verify h1 titles are lowercase on Research, Writing, About pages
5. Verify nothing else changed (homepage hero, section headings, CTAs, badges)
