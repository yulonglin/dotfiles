# Plan: Create Homepage Redesign Specification

## Context

The current yulonglin.com portfolio (Gatsby + styled-components) is too long and overwhelming — hero, about, 8-job tabbed panel, 60+ project cards, writing section, and contact all on one scrolling page. The user wants to redesign into a clean, multi-page researcher site that communicates two things:

1. **"I want this person on my team"** — warm, collaborative, cares about people
2. **"This person is capable"** — strong AI safety researcher, ships real work

The user is open to migrating from Gatsby to a better-suited framework.

## Task

Create a specification file at `specs/homepage-redesign.md` that captures:
- Design vision, principles, and tone guidelines (drawn from 8 reference sites)
- Multi-page site architecture with page-by-page content structure
- Framework recommendation with migration rationale
- Technical requirements (RSS, math/LaTeX, search, mobile fixes)
- Content strategy (what to keep, cut, restructure)
- Phased implementation plan

## Key Decisions Made

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Layout | Multi-page | Keeps homepage clean; separate Research, Writing, About pages |
| Framework | Open to migration | Gatsby is heavy for a content site; simpler options exist |

## Reference Sites Summary

| Site | Key Takeaway | Apply To |
|------|-------------|----------|
| **ong.ac** | Thematic research clusters with thumbnails + narrative descriptions | Research page structure |
| **soumith.ch** | Radical simplicity, progressive disclosure, candid philosophy | Homepage brevity, tone |
| **heyyjudes** | "I do meaningful work and I care about people" | Intro tone/framing |
| **saffronhuang.com** | Idea-focused descriptions ("why it matters" > credentials) | Project descriptions |
| **getcoleman.com** | Personality-driven design elements | Consider fun/memorable touches |
| **Lil'Log** | Clean navigation: Posts, Archive, Search, Tags, FAQ | Writing page features |
| **inFERENCe** | Tags + RSS + author photo header + math support | Blog infrastructure |
| **kipply** | Honest, wholesome, knows her stuff | Overall writing voice |

## Spec Structure (what we'll create)

```
specs/homepage-redesign.md
├── 1. Vision & Goals
├── 2. Design Principles
├── 3. Tone & Voice Guidelines
├── 4. Site Architecture (multi-page map)
├── 5. Page Specifications
│   ├── Homepage (intro + featured work + CTA)
│   ├── Research (thematic clusters)
│   ├── Writing/Blog (posts + tags + search)
│   └── About (bio + CV + personal)
├── 6. Technical Requirements
│   ├── Framework recommendation (Astro)
│   ├── RSS, math/LaTeX, search
│   ├── Mobile responsiveness fixes
│   └── Optional: Substack sync
├── 7. Content Migration Strategy
│   └── What to keep, cut, restructure from current site
└── 8. Phased Implementation Plan
```

## Framework Recommendation: Astro

**Why Astro over Gatsby:**
- Content-first by design (exactly this use case)
- Native MDX support → LaTeX/math via remark-math + rehype-katex
- Built-in RSS feed support (`@astrojs/rss`)
- File-based routing (familiar from Gatsby)
- Can use React components where needed (via `@astrojs/react`)
- Much faster builds, zero JS by default (ships only what's interactive)
- Works great with Bun

**Migration scope:** ~4 blog posts, ~8 jobs, ~10-15 selected projects (prune the 60+), config, theme toggle, styled-components → CSS/Tailwind.

## Current Files to Reference

- `src/components/sections/hero.js` — current intro copy
- `src/components/sections/about.js` — current bio copy
- `src/components/sections/jobs.js` — tabbed work history
- `src/components/sections/projects.js` — project grid
- `src/pages/pensieve/index.js` — current blog page
- `src/config.js` — social links, nav, colors
- `content/` — all markdown content (jobs, projects, posts, featured)

## Verification

After creating the spec:
1. Read `specs/homepage-redesign.md` and verify all sections are complete
2. Cross-reference with user's original requirements (all changes listed, all reference sites incorporated)
3. Ensure spec is actionable enough to implement from
